import {
  ConflictException,
  HttpStatus,
  Injectable,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { SubscriptionEntity } from '../entities/subscription.entity';
import { LIVE_STATUSES, priceKeyFor } from '../subscription-rules';
import { PURCHASE_OTHER_ACCOUNT } from '../billing-copy';
import type { StoreGrant } from './store-rules';

/// Puts a verified store purchase on the subscription row (payments plan, Phase 4). Shared by
/// Google Play and the App Store; the caller has already checked the purchase with the store.
///
/// Idempotent: the row is found by the store's own id, so the same purchase verified twice, or a
/// notification arriving after the app's own call, updates one row rather than adding another.
@Injectable()
export class StoreGrantService {
  private readonly log = new Logger(StoreGrantService.name);

  constructor(
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
  ) {}

  /**
   * [userId] is who is asking — the app, after a purchase. Null is a store notification, which
   * only ever updates a purchase some account has already claimed.
   *
   * Returns the row, or null when a notification names a purchase nobody has claimed yet (the
   * app's own call will claim it).
   */
  async apply(
    userId: number | null,
    grant: StoreGrant,
    now: Date,
  ): Promise<SubscriptionEntity | null> {
    const claimed = await this.findClaimed(grant);
    if (claimed && userId !== null && claimed.userId !== userId) {
      // A token or transaction id replayed from someone else's phone.
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: {
          code: 'PURCHASE_OTHER_ACCOUNT',
          user_message: PURCHASE_OTHER_ACCOUNT,
        },
      });
    }

    const owner = claimed?.userId ?? userId;
    if (owner === null) return null;

    if (!claimed) await this.closeOtherLivePlan(owner, grant, now);

    const cancelled = grant.status === 'active' && !grant.autoRenew;
    return this.subscriptions.save({
      ...(claimed ?? {
        userId: owner,
        startsAt: new Date(now),
        requiresAfa: false,
        trialEndsAt: null,
      }),
      tier: grant.tier,
      status: grant.status,
      currentPeriodEnd: grant.expiresAt,
      autoRenew: grant.autoRenew,
      cancelledAt: cancelled ? (claimed?.cancelledAt ?? new Date(now)) : null,
      priceKey: priceKeyFor(grant.tier, grant.duration),
      // The store holds the money; there is no paise figure of ours to prorate from.
      paidPaise: null,
      provider: grant.provider,
      // A Play upgrade or re-subscribe issues a new token; the row follows the newest.
      providerRef: grant.ref,
    });
  }

  private async findClaimed(
    grant: StoreGrant,
  ): Promise<SubscriptionEntity | null> {
    const refs = [grant.ref, grant.linkedRef].filter((r): r is string => !!r);
    return this.subscriptions.findOne({
      where: { provider: grant.provider, providerRef: In(refs) },
      order: { createdAt: 'DESC' },
    });
  }

  /// One live plan per person (docs/08 §6). The store has taken the money, so the new purchase
  /// wins: whatever was running (a trial, a Cashfree period) closes today. The paywall does not
  /// offer a store purchase over a running plan, so reaching this with a paid one is logged.
  private async closeOtherLivePlan(
    userId: number,
    grant: StoreGrant,
    now: Date,
  ): Promise<void> {
    const live = await this.subscriptions.findOne({
      where: { userId, status: In([...LIVE_STATUSES]) },
      order: { startsAt: 'DESC' },
    });
    if (!live) return;
    if (live.tier !== 'FREE' && live.provider && live.provider !== 'trial') {
      this.log.warn(
        `user ${userId}: ${grant.provider} purchase replaced a live ${live.provider} plan`,
      );
    }
    await this.subscriptions.save({
      ...live,
      status: 'cancelled',
      cancelledAt: live.cancelledAt ?? new Date(now),
      currentPeriodEnd: new Date(now),
    });
  }
}
