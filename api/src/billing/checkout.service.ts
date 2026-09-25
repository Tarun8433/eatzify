import {
  HttpStatus,
  Injectable,
  Logger,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { randomUUID } from 'node:crypto';
import { CouponsService } from './coupons.service';
import { PaymentOrderEntity } from './entities/payment-order.entity';
import { SubscriptionEntity } from './entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { CashfreeClient } from './cashfree.client';
import { CommissionService } from '../partner/commission.service';
import { CashfreeMode } from './cashfree.config';
import { PRICES, type Tier } from './tiers';
import {
  LIVE_STATUSES,
  periodEnd,
  priceKeyFor,
  requiresAfa,
} from './subscription-rules';
import { SubscriptionService } from './subscription.service';
import {
  ALREADY_SUBSCRIBED,
  COUPON_INVALID,
  CHECKOUT_UNAVAILABLE,
  PHONE_REQUIRED,
  UNKNOWN_PRICE,
} from './billing-copy';

export type Duration = '1M' | '3M' | '6M' | '9M' | '12M';

const MONTHS: Record<Duration, number> = {
  '1M': 1,
  '3M': 3,
  '6M': 6,
  '9M': 9,
  '12M': 12,
};

export type CheckoutView = {
  order_id: string;
  amount_paise: string;
  tier: string;
  duration: string;
  /// What the app hands to Cashfree's SDK. Null in stub mode, where there is nothing to open.
  payment_session_id: string | null;
  /// So the app can say "this build takes no money" rather than opening a checkout that cannot work.
  mode: string;
};

/**
 * Buying a subscription, docs/11 §5.
 *
 * The one rule the whole class exists to hold: **a subscription is granted by a verified webhook
 * and by nothing else.** Not by the app saying the payment worked, not by a return URL being hit,
 * not by an order row existing. Anything else is a way to get PRO for free.
 */
@Injectable()
export class CheckoutService {
  private readonly log = new Logger(CheckoutService.name);

  constructor(
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly cashfree: CashfreeClient,
    private readonly commission: CommissionService,
    private readonly subscriptions_: SubscriptionService,
    private readonly coupons_: CouponsService,
  ) {}

  /**
   * docs/11 §7's mid-term upgrade: charge the difference, not the whole new price.
   *
   * The quote is recomputed here rather than taken from the request — a body that named its own
   * credit would name the full price. When the credit covers everything the order is settled on the
   * spot: a gateway cannot take ₹0, and asking somebody to "pay" nothing is a dead end.
   */
  async upgrade({
    userId,
    tier,
    duration,
    idempotencyKey,
    now,
  }: {
    userId: number;
    tier: Exclude<Tier, 'FREE'>;
    duration: Duration;
    idempotencyKey: string | null;
    now: Date;
  }): Promise<CheckoutView> {
    if (idempotencyKey) {
      const replay = await this.orders.findOne({ where: { idempotencyKey } });
      if (replay) return this.toView(replay);
    }

    const quote = await this.subscriptions_.upgradeQuote(
      userId,
      tier,
      duration,
      now,
    );
    const due = quote.proration.amount_due_paise;

    const user = await this.users.findOne({ where: { id: userId } });
    if (!user?.phone) throw this.refuse('PHONE_REQUIRED', PHONE_REQUIRED);

    const cashfreeOrderId = `eatzify_${randomUUID()}`;
    const order = await this.orders.save(
      this.orders.create({
        userId,
        cashfreeOrderId,
        tier,
        duration,
        amountPaise: String(due),
        creditPaise: String(quote.proration.credit_paise),
        kind: 'upgrade',
        status: 'created',
        idempotencyKey,
      }),
    );

    if (due === 0) {
      await this.markPaid(cashfreeOrderId, now);
      const settled = await this.orders.findOne({ where: { cashfreeOrderId } });
      return this.toView(settled ?? order);
    }

    try {
      const created = await this.cashfree.createOrder({
        orderId: cashfreeOrderId,
        amountPaise: BigInt(due),
        customerId: userId,
        phone: user.phone,
        returnUrl: null,
      });
      order.paymentSessionId = created.paymentSessionId;
      await this.orders.save(order);
    } catch (e) {
      this.log.error(
        `upgrade failed for order ${cashfreeOrderId}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
      order.status = 'failed';
      order.failureReason =
        e instanceof Error ? e.message : 'CASHFREE_UNAVAILABLE';
      await this.orders.save(order);
      throw this.refuse('CHECKOUT_UNAVAILABLE', CHECKOUT_UNAVAILABLE);
    }

    return this.toView(order);
  }

  /**
   * Start a purchase. Takes no money — it creates the order the gateway will collect against.
   *
   * The price comes from the matrix, never from the request. A body that could name its own amount
   * would name ₹1.
   */
  async checkout({
    userId,
    tier,
    duration,
    idempotencyKey,
    now,
    couponCode,
  }: {
    userId: number;
    tier: Exclude<Tier, 'FREE'>;
    duration: Duration;
    idempotencyKey: string | null;
    now: Date;
    couponCode?: string | null;
  }): Promise<CheckoutView> {
    if (idempotencyKey) {
      // docs/09: a retried POST must not create a second order, and must not re-charge.
      const replay = await this.orders.findOne({ where: { idempotencyKey } });
      if (replay) return this.toView(replay);
    }

    const listPaise = PRICES[tier]?.[duration];
    if (listPaise === undefined) {
      throw this.refuse('UNKNOWN_PRICE', UNKNOWN_PRICE);
    }

    // D-236: the offer, applied server-side against the recomputed list price — the body still
    // never carries an amount. percentOff is capped at 90 on creation, so this cannot reach 0.
    let amountPaise = BigInt(listPaise);
    let discountPaise = 0n;
    let appliedCoupon: string | null = null;
    if (couponCode) {
      const offer = await this.coupons_.discountFor(
        couponCode,
        amountPaise,
        now,
      );
      if (offer === null) throw this.refuse('COUPON_INVALID', COUPON_INVALID);
      discountPaise = offer.discountPaise;
      amountPaise -= discountPaise;
      appliedCoupon = offer.code;
    }

    await this.refuseIfAlreadySubscribed(userId, now);

    const user = await this.users.findOne({ where: { id: userId } });
    // Cashfree requires a contactable customer, and an email signup has no number on the row.
    if (!user?.phone) {
      throw this.refuse('PHONE_REQUIRED', PHONE_REQUIRED);
    }

    const cashfreeOrderId = `eatzify_${randomUUID()}`;

    // Written BEFORE the gateway call. An order the gateway knows about and we do not is a payment
    // we cannot honour; the reverse is only a row nobody pays.
    const order = await this.orders.save(
      this.orders.create({
        userId,
        cashfreeOrderId,
        tier,
        duration,
        amountPaise: String(amountPaise),
        couponCode: appliedCoupon,
        discountPaise: String(discountPaise),
        status: 'created',
        idempotencyKey,
      }),
    );

    try {
      const created = await this.cashfree.createOrder({
        orderId: cashfreeOrderId,
        amountPaise,
        customerId: userId,
        phone: user.phone,
        returnUrl: null,
      });

      order.paymentSessionId = created.paymentSessionId;
      await this.orders.save(order);
    } catch (e) {
      // The gateway's words go to the log; the user gets approved copy (rule 7).
      this.log.error(
        `checkout failed for order ${cashfreeOrderId}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
      order.status = 'failed';
      order.failureReason =
        e instanceof Error ? e.message : 'CASHFREE_UNAVAILABLE';
      await this.orders.save(order);
      throw this.refuse('CHECKOUT_UNAVAILABLE', CHECKOUT_UNAVAILABLE);
    }

    return this.toView(order);
  }

  /**
   * A payment succeeded. The only path that grants a subscription.
   *
   * Idempotent, because a gateway retries: Cashfree will send the same success more than once when
   * a response is slow, and the second delivery must extend nobody's plan a second time.
   */
  async markPaid(cashfreeOrderId: string, now: Date): Promise<void> {
    const order = await this.orders.findOne({ where: { cashfreeOrderId } });

    // An unknown order id is not an error worth answering differently — a webhook endpoint that
    // distinguishes "no such order" from "already paid" tells a prober which ids are real.
    if (!order || order.status === 'paid') return;

    order.status = 'paid';
    order.paidAt = now;
    await this.orders.save(order);

    // D-236: a use is spent only here, where the payment is known to be real — an abandoned
    // checkout never burns one.
    if (order.couponCode) await this.coupons_.redeem(order.couponCode);

    const renewal = await this.activate(order, now);

    /**
     * The partner's commission, written here and nowhere else.
     *
     * A verified webhook is the only place a payment is known to be real (D-194), so it is also the
     * only honest place to credit somebody for it. Earning nothing is the normal case: most buyers
     * arrived on their own and `accrueFor` returns null for them.
     *
     * A failure here must not fail the payment. The customer has paid and their plan is already
     * active; a missing ledger row is a reconciliation job, while a thrown error would make
     * Cashfree retry a webhook that already did its work.
     */
    try {
      await this.commission.accrueFor({
        clientUserId: order.userId,
        paymentOrderId: order.id,
        tier: order.tier,
        grossPaise: BigInt(order.amountPaise),
        isRenewal: renewal,
        now,
      });
    } catch (e) {
      this.log.error(
        `commission not accrued for order ${cashfreeOrderId}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
    }
  }

  async markFailed(
    cashfreeOrderId: string,
    reason: string,
    now: Date,
  ): Promise<void> {
    const order = await this.orders.findOne({ where: { cashfreeOrderId } });
    // Never downgrade a paid order. A failure arriving after a success is a retry of an earlier
    // attempt, not a reversal — reversals are refunds and have their own path (docs/11 §9).
    if (!order || order.status !== 'created') return;

    order.status = 'failed';
    order.failureReason = reason;
    await this.orders.save(order);
    void now;
  }

  /// Dev-only: drives [markPaid] without a signature, so the whole activation path is exercisable
  /// before credentials exist. The controller — not this method — is what refuses it outside stub
  /// mode, because a service that could be called in production is one that will be.
  async simulatePaid(
    userId: number,
    cashfreeOrderId: string,
    now: Date,
  ): Promise<void> {
    const order = await this.orders.findOne({
      where: { cashfreeOrderId, userId },
    });
    if (!order) return;

    await this.markPaid(cashfreeOrderId, now);
  }

  /**
   * Put the tier on the subscription row.
   *
   * A period is EXTENDED rather than replaced when one is still running: someone who renews early
   * keeps the days they already paid for, which is the difference between a renewal and a reset.
   */
  private async activate(
    order: PaymentOrderEntity,
    now: Date,
  ): Promise<boolean> {
    const existing = await this.subscriptions.findOne({
      where: { userId: order.userId, status: In([...LIVE_STATUSES]) },
      order: { startsAt: 'DESC' },
    });

    // docs/12 §2 pays a different rate on a renewal. Anyone who has held a paid tier before is
    // renewing, whether or not the old period had already lapsed — the first-purchase rate is for
    // the sale that brought them in, and it is paid once.
    const isRenewal = existing !== null && existing.tier !== 'FREE';

    /**
     * docs/11 §7: an upgrade CLOSES the period it replaces and opens a new one — "never mutate the
     * old row". The credit for the days left has already come off what was charged, so the new
     * period starts today rather than carrying the old end date forward.
     */
    if (order.kind === 'upgrade' && existing) {
      existing.status = 'cancelled';
      existing.cancelledAt = now;
      existing.currentPeriodEnd = new Date(now);
      await this.subscriptions.save(existing);

      await this.subscriptions.save(
        this.subscriptions.create({
          userId: order.userId,
          tier: order.tier,
          status: 'active',
          startsAt: new Date(now),
          currentPeriodEnd: periodEnd(new Date(now), order.duration),
          paidPaise: String(order.amountPaise),
          priceKey: priceKeyFor(order.tier as Tier, order.duration),
          requiresAfa: requiresAfa(Number(order.amountPaise)),
          autoRenew: true,
          cancelledAt: null,
          trialEndsAt: null,
          provider: 'cashfree',
          providerRef: order.cashfreeOrderId,
        }),
      );

      return isRenewal;
    }

    const from =
      existing?.currentPeriodEnd && existing.currentPeriodEnd > now
        ? new Date(existing.currentPeriodEnd)
        : new Date(now);

    const endsAt = new Date(from);
    endsAt.setMonth(endsAt.getMonth() + MONTHS[order.duration as Duration]);

    await this.subscriptions.save({
      ...(existing ?? {}),
      userId: order.userId,
      tier: order.tier,
      status: 'active',
      // The period this payment bought, and what it cost: docs/11 §7 prorates an upgrade from
      // both, and neither can be recovered from an end date alone.
      startsAt:
        existing?.startsAt && from > now ? existing.startsAt : new Date(now),
      currentPeriodEnd: endsAt,
      paidPaise: String(order.amountPaise),
      priceKey: priceKeyFor(order.tier as Tier, order.duration),
      // docs/11 §8: computed from the price, never sent by the client.
      requiresAfa: requiresAfa(Number(order.amountPaise)),
      // A paid period renews unless the person says otherwise, and a purchase after a cancel is
      // them changing their mind back.
      autoRenew: true,
      cancelledAt: null,
      trialEndsAt: null,
      provider: 'cashfree',
      providerRef: order.cashfreeOrderId,
    });

    return isRenewal;
  }

  /// A second full-price purchase on top of a running plan. Moving UP mid-term is the upgrade path
  /// (docs/11 §7), which quotes the credit first; this is what stops a plain double charge.
  private async refuseIfAlreadySubscribed(
    userId: number,
    now: Date,
  ): Promise<void> {
    const existing = await this.subscriptions.findOne({
      where: { userId, status: In([...LIVE_STATUSES]) },
      order: { startsAt: 'DESC' },
    });

    const live =
      existing &&
      existing.tier !== 'FREE' &&
      (existing.currentPeriodEnd === null || existing.currentPeriodEnd > now);

    if (live) throw this.refuse('ALREADY_SUBSCRIBED', ALREADY_SUBSCRIBED);
  }

  private toView(order: PaymentOrderEntity): CheckoutView {
    return {
      order_id: order.cashfreeOrderId,
      amount_paise: String(order.amountPaise),
      tier: order.tier,
      duration: order.duration,
      payment_session_id: order.paymentSessionId,
      mode: this.cashfree.mode,
    };
  }

  private refuse(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }
}

export { CashfreeMode };
