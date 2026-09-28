import { type Repository } from 'typeorm';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import {
  GRACE_DAYS,
  PAST_DUE_DAYS,
  SubscriptionSweepService,
} from '../src/billing/subscription-sweep.service';
import { NotificationsService } from '../src/notifications/notifications.service';

/// docs/11 §5 and §8. The daily pass: what it tells people, and when it moves a plan along.

type Sub = Partial<SubscriptionEntity>;
type Sent = { kind: string; title: string; body: string; dedupeKey?: string };

const NOW = new Date('2026-09-18T04:00:00Z');
const DAY = 86_400_000;

function sweepOver(rows: Sub[], already: string[] = []) {
  const sent: Sent[] = [];
  const subscriptions = {
    find: () => Promise.resolve(rows),
    save: (row: Sub) => Promise.resolve(row),
  } as unknown as Repository<SubscriptionEntity>;

  const notifications = {
    notify: (input: Sent) => {
      // The real one answers null when the dedupe key has already been used.
      if (input.dedupeKey && already.includes(input.dedupeKey))
        return Promise.resolve(null);
      sent.push(input);
      return Promise.resolve({ id: 'n1' });
    },
  } as unknown as NotificationsService;

  return {
    sent,
    run: () =>
      new SubscriptionSweepService(subscriptions, notifications).run(NOW),
  };
}

const active = (over: Partial<Sub> = {}): Sub => ({
  id: 'sub-1',
  userId: 1,
  tier: 'PRO',
  status: 'active',
  startsAt: new Date('2026-06-01T00:00:00Z'),
  currentPeriodEnd: new Date('2026-12-01T00:00:00Z'),
  paidPaise: '279900',
  priceKey: 'PRO:6M',
  autoRenew: true,
  requiresAfa: false,
  cancelledAt: null,
  trialEndsAt: null,
  ...over,
});

describe('renewal notices (docs/11 §8)', () => {
  it('should warn a week ahead with the exact amount and date', async () => {
    const sweep = sweepOver([
      active({ currentPeriodEnd: new Date(NOW.getTime() + 7 * DAY) }),
    ]);

    const report = await sweep.run();

    expect(report.notices).toBe(1);
    expect(sweep.sent[0].kind).toBe('renewal_t7');
    expect(sweep.sent[0].body).toContain('₹2,799');
    expect(sweep.sent[0].title).toContain('25 September 2026');
  });

  it('should warn again three days ahead, and on the day', async () => {
    const three = sweepOver([
      active({ currentPeriodEnd: new Date(NOW.getTime() + 3 * DAY) }),
    ]);
    await three.run();
    expect(three.sent[0].kind).toBe('renewal_t3');
  });

  it('should say a big plan needs the bank’s approval, not a silent debit (docs/11 §8)', async () => {
    const sweep = sweepOver([
      active({
        requiresAfa: true,
        currentPeriodEnd: new Date(NOW.getTime() + 7 * DAY),
      }),
    ]);
    await sweep.run();

    expect(sweep.sent[0].body).toContain('approve');
  });

  it('should say nothing to somebody who already cancelled', async () => {
    const sweep = sweepOver([
      active({
        autoRenew: false,
        currentPeriodEnd: new Date(NOW.getTime() + 7 * DAY),
      }),
    ]);

    expect((await sweep.run()).notices).toBe(0);
  });

  it('should be safe to run twice', async () => {
    const sweep = sweepOver(
      [active({ currentPeriodEnd: new Date(NOW.getTime() + 7 * DAY) })],
      ['renewal_t7:sub-1'],
    );

    expect((await sweep.run()).notices).toBe(0);
  });
});

describe('a payment that did not arrive (docs/11 §5)', () => {
  it('should move a lapsed plan to past_due and keep it running', async () => {
    const row = active({ currentPeriodEnd: new Date(NOW.getTime() - 1 * DAY) });
    const sweep = sweepOver([row]);

    const report = await sweep.run();

    expect(row.status).toBe('past_due');
    expect(report.moved).toBe(1);
    expect(sweep.sent[0].kind).toBe('past_due_d1');
  });

  it('should hold it in grace after the retries run out', async () => {
    const row = active({
      status: 'past_due',
      currentPeriodEnd: new Date(NOW.getTime() - PAST_DUE_DAYS * DAY),
    });
    const sweep = sweepOver([row]);
    await sweep.run();

    expect(row.status).toBe('grace');
    expect(sweep.sent[0].kind).toBe('payment_grace');
    // The period ended on the 15th: three days of retries, then the grace week.
    expect(sweep.sent[0].body).toContain('25 September 2026');
  });

  it('should end it only after the grace week', async () => {
    const row = active({
      status: 'grace',
      currentPeriodEnd: new Date(
        NOW.getTime() - (PAST_DUE_DAYS + GRACE_DAYS) * DAY,
      ),
    });
    const sweep = sweepOver([row]);
    await sweep.run();

    expect(row.status).toBe('expired');
    expect(sweep.sent[0].kind).toBe('subscription_expired');
    // docs/11 §5: "Never delete a user's history because they stopped paying".
    expect(sweep.sent[0].body).toContain('still here');
  });

  it('should end a cancelled plan the day its period runs out, with no grace', async () => {
    const row = active({
      autoRenew: false,
      currentPeriodEnd: new Date(NOW.getTime() - 1 * DAY),
    });
    const sweep = sweepOver([row]);
    await sweep.run();

    expect(row.status).toBe('expired');
    expect(sweep.sent[0].kind).toBe('subscription_expired');
  });
});

describe('the trial (docs/11 §6)', () => {
  const trialing = (over: Partial<Sub> = {}): Sub =>
    active({
      status: 'trialing',
      paidPaise: null,
      priceKey: 'PRO:1M',
      trialEndsAt: new Date(NOW.getTime() + 2 * DAY),
      currentPeriodEnd: new Date(NOW.getTime() + 2 * DAY),
      ...over,
    });

  /// "Mandatory reminder 48 h before conversion. This is not optional."
  it('should warn 48 hours before it converts, naming the amount and the date', async () => {
    const sweep = sweepOver([trialing()]);
    await sweep.run();

    expect(sweep.sent[0].kind).toBe('trial_ending');
    expect(sweep.sent[0].body).toContain('₹649');
    expect(sweep.sent[0].body).toContain('20 September 2026');
    expect(sweep.sent[0].body).toContain('Cancel');
  });

  it('should stay quiet while the trial has longer to run', async () => {
    const sweep = sweepOver([
      trialing({ trialEndsAt: new Date(NOW.getTime() + 5 * DAY) }),
    ]);

    expect((await sweep.run()).notices).toBe(0);
  });

  it('should tell somebody who cancelled in the trial that nothing will be charged', async () => {
    const sweep = sweepOver([trialing({ autoRenew: false })]);
    await sweep.run();

    expect(sweep.sent[0].body).toContain('Nothing will be charged');
  });

  /// The sweep never takes money, so a trial that should convert waits for a payment instead of
  /// quietly granting a paid plan nobody paid for.
  it('should park a converting trial in past_due when it ends', async () => {
    const row = trialing({ trialEndsAt: new Date(NOW.getTime() - 1 * DAY) });
    const sweep = sweepOver([row]);
    await sweep.run();

    expect(row.status).toBe('past_due');
    expect(sweep.sent[0].kind).toBe('trial_needs_payment');
    expect(sweep.sent[0].body).toContain('Nothing has been charged');
  });

  it('should simply end a cancelled trial', async () => {
    const row = trialing({
      autoRenew: false,
      trialEndsAt: new Date(NOW.getTime() - 1 * DAY),
    });
    const sweep = sweepOver([row]);
    await sweep.run();

    expect(row.status).toBe('expired');
    expect(sweep.sent[0].kind).toBe('trial_ended');
  });
});

describe('the sweep itself', () => {
  it('should carry on when one row throws', async () => {
    const bad = active({ id: 'bad' });
    const sent: Sent[] = [];
    const subscriptions = {
      find: () =>
        Promise.resolve([
          bad,
          active({ currentPeriodEnd: new Date(NOW.getTime() + 7 * DAY) }),
        ]),
      save: (row: Sub) => {
        if (row.id === 'bad') throw new Error('database said no');
        return Promise.resolve(row);
      },
    } as unknown as Repository<SubscriptionEntity>;
    const notifications = {
      notify: (input: Sent) => {
        sent.push(input);
        return Promise.resolve({ id: 'n1' });
      },
    } as unknown as NotificationsService;

    bad.currentPeriodEnd = new Date(NOW.getTime() - 1 * DAY);
    const report = await new SubscriptionSweepService(
      subscriptions,
      notifications,
    ).run(NOW);

    expect(report.checked).toBe(2);
    expect(sent.map((s) => s.kind)).toContain('renewal_t7');
  });
});
