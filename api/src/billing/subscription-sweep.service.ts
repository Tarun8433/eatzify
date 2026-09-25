import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { SubscriptionEntity } from './entities/subscription.entity';
import { NotificationsService } from '../notifications/notifications.service';
import {
  LIVE_STATUSES,
  TRIAL_REMINDER_HOURS,
  priceOf,
} from './subscription-rules';
import type { Tier } from './tiers';

/// docs/11 §5. A failed renewal is retried for three days, then the plan sits in grace for a week
/// before it expires — nobody loses access on the day a card is declined.
export const PAST_DUE_DAYS = 3;
export const GRACE_DAYS = 7;

/// docs/11 §8's own schedule, in days before the period ends.
export const RENEWAL_NOTICE_DAYS = [7, 3, 0] as const;

const MS_PER_DAY = 86_400_000;

export type SweepReport = {
  checked: number;
  notices: number;
  moved: number;
};

/**
 * The daily pass over every live subscription (docs/11 §5 and §8).
 *
 * It does two things and nothing else: it tells people what is about to happen to their plan, and
 * it moves a plan along when the clock says so. It takes no money — a renewal charge belongs to the
 * gateway's mandate, and this runs whether or not one exists.
 *
 * Safe to run twice: every notice is keyed (`dedupeKey`), and every move is decided from dates
 * rather than from what the last run did.
 */
@Injectable()
export class SubscriptionSweepService {
  private readonly log = new Logger(SubscriptionSweepService.name);

  constructor(
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly notifications: NotificationsService,
  ) {}

  async run(now: Date): Promise<SweepReport> {
    const live = await this.subscriptions.find({
      where: { status: In([...LIVE_STATUSES]) },
    });

    const report: SweepReport = { checked: live.length, notices: 0, moved: 0 };

    for (const row of live) {
      try {
        const step =
          row.status === 'trialing'
            ? await this.trialing(row, now)
            : await this.paid(row, now);
        report.notices += step.notices;
        report.moved += step.moved;
      } catch (e) {
        // One bad row must not stop the sweep. No ids beyond the subscription's own (rule 5).
        this.log.error(
          `sweep failed for subscription ${row.id}: ${e instanceof Error ? e.message : 'unknown'}`,
        );
      }
    }

    return report;
  }

  /// docs/11 §6: the reminder 48 h before a trial converts is mandatory — "silent conversion after
  /// a free trial is the top driver of chargebacks and Play policy complaints".
  private async trialing(
    row: SubscriptionEntity,
    now: Date,
  ): Promise<{ notices: number; moved: number }> {
    const ends = row.trialEndsAt ?? row.currentPeriodEnd;
    if (!ends) return { notices: 0, moved: 0 };

    const hoursLeft = (ends.getTime() - now.getTime()) / 3_600_000;

    if (hoursLeft > 0) {
      if (hoursLeft > TRIAL_REMINDER_HOURS) return { notices: 0, moved: 0 };
      const sent = await this.notify(row, {
        kind: 'trial_ending',
        title: 'Your free trial ends soon',
        body: row.autoRenew
          ? `Your ${row.tier} plan starts on ${this.day(ends)} at ${this.amount(row)}. Cancel before then and you will not be charged.`
          : `Your ${row.tier} trial ends on ${this.day(ends)}. Nothing will be charged.`,
        dedupeKey: `trial_ending:${row.id}`,
      });
      return { notices: sent, moved: 0 };
    }

    // The trial is over. Converting needs a payment, which this service never takes: a plan that
    // should convert waits in past_due until one arrives, and one that was cancelled simply ends.
    row.status = row.autoRenew ? 'past_due' : 'expired';
    await this.subscriptions.save(row);

    const sent = await this.notify(row, {
      kind: row.autoRenew ? 'trial_needs_payment' : 'trial_ended',
      title: row.autoRenew ? 'Your trial has ended' : 'Your trial has ended',
      body: row.autoRenew
        ? `Choose a plan to keep your ${row.tier} features. Nothing has been charged.`
        : 'Thanks for trying it. Your free account carries on as before.',
      dedupeKey: `trial_over:${row.id}`,
    });

    return { notices: sent, moved: 1 };
  }

  private async paid(
    row: SubscriptionEntity,
    now: Date,
  ): Promise<{ notices: number; moved: number }> {
    const ends = row.currentPeriodEnd;
    if (!ends) return { notices: 0, moved: 0 };

    const daysLeft = Math.ceil((ends.getTime() - now.getTime()) / MS_PER_DAY);

    // Still running: the T-7 / T-3 / T-0 notices, but only for a plan that will actually renew.
    if (daysLeft > 0) {
      if (!row.autoRenew) return { notices: 0, moved: 0 };
      const due = RENEWAL_NOTICE_DAYS.find((d) => d > 0 && daysLeft === d);
      if (due === undefined) return { notices: 0, moved: 0 };

      const sent = await this.notify(row, {
        kind: `renewal_t${due}`,
        title: `Your ${row.tier} plan renews on ${this.day(ends)}`,
        body: row.requiresAfa
          ? `${this.amount(row)} is due on ${this.day(ends)}. Your bank will ask you to approve it — we will send you the link.`
          : `${this.amount(row)} will be charged on ${this.day(ends)}.`,
        dedupeKey: `renewal_t${due}:${row.id}`,
      });
      return { notices: sent, moved: 0 };
    }

    const daysOver = Math.floor((now.getTime() - ends.getTime()) / MS_PER_DAY);

    if (!row.autoRenew) {
      row.status = 'expired';
      await this.subscriptions.save(row);
      const sent = await this.notify(row, {
        kind: 'subscription_expired',
        title: 'Your plan has ended',
        body: 'Everything you logged is still here. Pick a plan whenever you want it back.',
        dedupeKey: `expired:${row.id}`,
      });
      return { notices: sent, moved: 1 };
    }

    // docs/11 §5: retries for three days, then a week of grace, then it ends.
    if (daysOver >= PAST_DUE_DAYS + GRACE_DAYS) {
      row.status = 'expired';
      await this.subscriptions.save(row);
      const sent = await this.notify(row, {
        kind: 'subscription_expired',
        title: 'Your plan has ended',
        body: 'Everything you logged is still here. Pick a plan whenever you want it back.',
        dedupeKey: `expired:${row.id}`,
      });
      return { notices: sent, moved: 1 };
    }

    if (daysOver >= PAST_DUE_DAYS) {
      const moved = row.status === 'grace' ? 0 : 1;
      row.status = 'grace';
      await this.subscriptions.save(row);
      const sent = await this.notify(row, {
        kind: 'payment_grace',
        title: 'We could not take your payment',
        body: `Your ${row.tier} plan stays on until ${this.day(new Date(ends.getTime() + (PAST_DUE_DAYS + GRACE_DAYS) * MS_PER_DAY))}. Update your payment method to keep it.`,
        dedupeKey: `grace:${row.id}`,
      });
      return { notices: sent, moved };
    }

    const moved = row.status === 'past_due' ? 0 : 1;
    row.status = 'past_due';
    await this.subscriptions.save(row);

    // docs/11 §8: day 1 and day 3 of past_due.
    const notice =
      daysOver >= 1 ? `past_due_d${daysOver >= PAST_DUE_DAYS ? 3 : 1}` : null;
    const sent =
      notice === null
        ? 0
        : await this.notify(row, {
            kind: notice,
            title: 'Your payment did not go through',
            body: `We will try again for the next ${PAST_DUE_DAYS} days. Your ${row.tier} plan is still on.`,
            dedupeKey: `${notice}:${row.id}`,
          });

    return { notices: sent, moved };
  }

  private async notify(
    row: SubscriptionEntity,
    message: { kind: string; title: string; body: string; dedupeKey: string },
  ): Promise<number> {
    const sent = await this.notifications.notify({
      userId: row.userId,
      contentClass: 'service',
      data: { tier: row.tier, subscription_id: row.id },
      // docs/11 §8's notices are the ones people complain about missing, so they go to the inbox
      // AND to an email when the account has one.
      alsoEmail: true,
      ...message,
    });
    return sent ? 1 : 0;
  }

  /// "24 September 2026" — docs/11 §8 wants the exact date, not "soon".
  private day(date: Date): string {
    return date.toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'long',
      year: 'numeric',
      timeZone: 'Asia/Kolkata',
    });
  }

  /// "₹2,799" — the exact amount, from the cell the period was bought at.
  private amount(row: SubscriptionEntity): string {
    const [tier, duration] = (row.priceKey ?? '').split(':');
    const paise = priceOf(tier as Tier, duration) ?? Number(row.paidPaise ?? 0);
    return `₹${Math.round(paise / 100).toLocaleString('en-IN')}`;
  }
}
