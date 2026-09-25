import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { SubscriptionEntity } from './entities/subscription.entity';
import { TrialGrantEntity } from './entities/trial-grant.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import type { AllConfigType } from '../config/config.type';
import {
  ALREADY_SUBSCRIBED,
  NO_ACTIVE_PLAN,
  NOT_AN_UPGRADE,
  PHONE_REQUIRED,
  TRIAL_ALREADY_USED,
  UNKNOWN_PRICE,
} from './billing-copy';
import { entitlementsFor, type Entitlements, type Tier } from './tiers';
import {
  LIVE_STATUSES,
  isUpgrade,
  phoneHash,
  priceKeyFor,
  priceOf,
  prorate,
  requiresAfa,
  trialEnd,
  type Proration,
} from './subscription-rules';

export type SubscriptionStateView = {
  tier: Tier;
  status: string;
  /// docs/08 §6 calls it `ends_at`; it is the end of the period the person has paid for or is
  /// trialing, and null only on FREE.
  ends_at: string | null;
  starts_at: string | null;
  auto_renew: boolean;
  /// docs/11 §8: true means the renewal needs the person to authorise it, every time.
  requires_afa: boolean;
  trial_ends_at: string | null;
  cancelled_at: string | null;
  /// Whether this account may still take docs/11 §6's one free week.
  trial_available: boolean;
  entitlements: Entitlements;
};

export type UpgradeQuoteView = {
  tier: Tier;
  duration: string;
  price_paise: number;
  proration: Proration;
};

/// The subscription's own life, away from checkout: the trial that starts it, the cancel that
/// stops it renewing, and the quote for moving up mid-term (docs/11 §5–§7).
@Injectable()
export class SubscriptionService {
  constructor(
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(TrialGrantEntity)
    private readonly trials: Repository<TrialGrantEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly notifications: NotificationsService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  /// The row that is running, or null. A period whose end has passed is not running, whatever the
  /// status column says — the sweep may not have reached it yet (docs/11 §5).
  async live(userId: number, now: Date): Promise<SubscriptionEntity | null> {
    const row = await this.subscriptions.findOne({
      where: { userId, status: In([...LIVE_STATUSES]) },
      order: { startsAt: 'DESC' },
    });
    if (!row) return null;
    if (row.currentPeriodEnd && row.currentPeriodEnd.getTime() <= now.getTime())
      return null;
    return row;
  }

  async state(userId: number, now: Date): Promise<SubscriptionStateView> {
    const row = await this.live(userId, now);
    const tier = (row?.tier ?? 'FREE') as Tier;

    return {
      tier,
      status: row?.status ?? 'active',
      ends_at: row?.currentPeriodEnd?.toISOString() ?? null,
      starts_at: row?.startsAt?.toISOString() ?? null,
      auto_renew: row?.autoRenew ?? false,
      requires_afa: row?.requiresAfa ?? false,
      trial_ends_at: row?.trialEndsAt?.toISOString() ?? null,
      cancelled_at: row?.cancelledAt?.toISOString() ?? null,
      trial_available: await this.trialAvailable(userId),
      entitlements: entitlementsFor(tier),
    };
  }

  /// docs/11 §6. Seven days, one per number for life, and cancelling in the trial keeps access to
  /// its end — so a cancel is a flag, never a deletion.
  async startTrial(
    userId: number,
    tier: Tier,
    now: Date,
  ): Promise<SubscriptionStateView> {
    if (tier === 'FREE' || priceOf(tier, '1M') === undefined) {
      throw this.refuse('UNKNOWN_PRICE', UNKNOWN_PRICE);
    }
    if (await this.live(userId, now)) {
      throw this.refuse('ALREADY_SUBSCRIBED', ALREADY_SUBSCRIBED);
    }

    const hash = await this.hashFor(userId);
    if (await this.trials.findOne({ where: { phoneHash: hash } })) {
      throw this.refuse('TRIAL_ALREADY_USED', TRIAL_ALREADY_USED);
    }

    const ends = trialEnd(now);
    await this.trials.save(
      this.trials.create({ phoneHash: hash, userId, tier }),
    );
    await this.subscriptions.save(
      this.subscriptions.create({
        userId,
        tier,
        status: 'trialing',
        startsAt: now,
        currentPeriodEnd: ends,
        trialEndsAt: ends,
        // docs/11 §6: "converts unless cancelled".
        autoRenew: true,
        paidPaise: null,
        priceKey: priceKeyFor(tier, '1M'),
        provider: null,
        providerRef: null,
      }),
    );

    return this.state(userId, now);
  }

  /// docs/09 §7: cancel "cancels renewal, retains access to ends_at". The status stays as it is —
  /// someone who cancels on day 2 of a month they paid for keeps the other 28 days.
  async cancel(
    userId: number,
    reason: string | null,
    now: Date,
  ): Promise<SubscriptionStateView> {
    const row = await this.live(userId, now);
    if (!row) throw this.refuse('NO_ACTIVE_PLAN', NO_ACTIVE_PLAN);

    row.autoRenew = false;
    row.cancelledAt = now;
    await this.subscriptions.save(row);

    await this.notifications.notify({
      userId,
      kind: 'subscription_cancelled',
      contentClass: 'service',
      title: 'Your plan will not renew',
      body: row.currentPeriodEnd
        ? `You keep everything until ${row.currentPeriodEnd.toISOString().slice(0, 10)}.`
        : 'You keep everything you have now.',
      data: { tier: row.tier, reason },
      dedupeKey: `cancelled:${row.id}`,
      alsoEmail: true,
    });

    return this.state(userId, now);
  }

  /// docs/11 §7's quote, shown before anything is charged: "Show the arithmetic on screen; opaque
  /// proration generates tickets."
  async upgradeQuote(
    userId: number,
    tier: Tier,
    duration: string,
    now: Date,
  ): Promise<UpgradeQuoteView> {
    const price = priceOf(tier, duration);
    if (price === undefined) throw this.refuse('UNKNOWN_PRICE', UNKNOWN_PRICE);

    const row = await this.live(userId, now);
    if (!row) throw this.refuse('NO_ACTIVE_PLAN', NO_ACTIVE_PLAN);
    if (!isUpgrade(row.tier as Tier, tier)) {
      throw this.refuse('NOT_AN_UPGRADE', NOT_AN_UPGRADE);
    }

    return {
      tier,
      duration,
      price_paise: price,
      proration: prorate({
        paidPaise: Number(row.paidPaise ?? 0),
        startsAt: row.startsAt,
        endsAt: row.currentPeriodEnd,
        now,
        newPricePaise: price,
      }),
    };
  }

  /// Whether the free week is still on the table for this account's number.
  async trialAvailable(userId: number): Promise<boolean> {
    const user = await this.users.findOne({ where: { id: userId } });
    if (!user?.phone) return false;
    const hash = phoneHash(user.phone, this.pepper);
    return (await this.trials.findOne({ where: { phoneHash: hash } })) === null;
  }

  /// docs/11 §8's flag, computed from the price rather than stored by the client.
  needsAfa(amountPaise: number): boolean {
    return requiresAfa(amountPaise);
  }

  private async hashFor(userId: number): Promise<string> {
    const user = await this.users.findOne({ where: { id: userId } });
    if (!user?.phone) throw this.refuse('PHONE_REQUIRED', PHONE_REQUIRED);
    return phoneHash(user.phone, this.pepper);
  }

  private get pepper(): string {
    return (
      this.config.get('app.trialPepper', { infer: true }) ?? 'eatzify-trial'
    );
  }

  private refuse(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }
}
