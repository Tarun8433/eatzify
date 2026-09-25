import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { randomUUID } from 'node:crypto';
import { PaymentOrderEntity } from './entities/payment-order.entity';
import { SubscriptionEntity } from './entities/subscription.entity';
import { CashfreeClient } from './cashfree.client';
import { CommissionService } from '../partner/commission.service';
import { NotificationsService } from '../notifications/notifications.service';
import { REFUND_NOT_AVAILABLE, REFUND_WINDOW_CLOSED } from './billing-copy';

/// docs/11 §9: "Web/Razorpay purchases: 7-day refund, self-serve". Play purchases go through
/// Google's own process, which is why this only ever touches orders we billed ourselves.
export const REFUND_DAYS = 7;

const MS_PER_DAY = 86_400_000;

export type RefundView = {
  order_id: string;
  refunded_paise: string;
  /// What the refund did to the plan: it ends now, because it was not paid for after all.
  tier_after: string;
};

/**
 * A refund, end to end (docs/11 §9).
 *
 * Four things happen together and in this order: the gateway gives the money back, the order is
 * marked, the plan the order paid for ends, and the partner's commission is reversed (docs/12 §3 —
 * "offsetting entry, never a delete").
 *
 * The gateway call comes FIRST on purpose. A refund we recorded but never made is money we owe
 * somebody with nothing to show it; the other way round is a row a reconciliation job can fix.
 */
@Injectable()
export class RefundService {
  constructor(
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly cashfree: CashfreeClient,
    private readonly commission: CommissionService,
    private readonly notifications: NotificationsService,
  ) {}

  async refund(
    userId: number,
    cashfreeOrderId: string,
    reason: string | null,
    now: Date,
  ): Promise<RefundView> {
    const order = await this.orders.findOne({
      where: { cashfreeOrderId, userId },
    });

    // An order that was never paid, or already refunded, has nothing to give back.
    if (!order || order.status !== 'paid' || !order.paidAt) {
      throw this.refuse('REFUND_NOT_AVAILABLE', REFUND_NOT_AVAILABLE);
    }

    const days = (now.getTime() - order.paidAt.getTime()) / MS_PER_DAY;
    if (days > REFUND_DAYS) {
      throw this.refuse('REFUND_WINDOW_CLOSED', REFUND_WINDOW_CLOSED);
    }

    await this.cashfree.refund({
      orderId: order.cashfreeOrderId,
      refundId: `refund_${randomUUID()}`,
      amountPaise: BigInt(order.amountPaise),
    });

    order.status = 'refunded';
    order.refundedAt = now;
    await this.orders.save(order);

    // The period this order bought ends now — a refunded plan is not a plan somebody holds.
    const granted = await this.subscriptions.findOne({
      where: { userId, providerRef: order.cashfreeOrderId },
    });
    if (granted) {
      granted.status = 'cancelled';
      granted.cancelledAt = now;
      granted.currentPeriodEnd = now;
      granted.autoRenew = false;
      await this.subscriptions.save(granted);
    }

    await this.commission.reverseForOrder(order.id, now);

    await this.notifications.notify({
      userId,
      kind: 'refund_processed',
      contentClass: 'service',
      title: 'Your refund is on its way',
      body: `₹${Math.round(Number(order.amountPaise) / 100).toLocaleString('en-IN')} is going back to the way you paid. Banks usually take 5 to 7 working days.`,
      data: { order_id: order.cashfreeOrderId, reason },
      dedupeKey: `refund:${order.id}`,
      alsoEmail: true,
    });

    return {
      order_id: order.cashfreeOrderId,
      refunded_paise: String(order.amountPaise),
      tier_after: 'FREE',
    };
  }

  private refuse(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }
}
