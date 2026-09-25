import { ConfigService } from '@nestjs/config';
import { type Repository } from 'typeorm';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { TrialGrantEntity } from '../src/billing/entities/trial-grant.entity';
import { SubscriptionService } from '../src/billing/subscription.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { TRIAL_DAYS } from '../src/billing/subscription-rules';

/// docs/11 §5–§7. The trial, the cancel and the upgrade quote, over in-memory rows.

type Sub = Partial<SubscriptionEntity>;

const NOW = new Date('2026-09-18T10:00:00Z');

function repos(subs: Sub[] = [], grants: Partial<TrialGrantEntity>[] = []) {
  const matches = (
    row: Record<string, unknown>,
    where: Record<string, unknown>,
  ) =>
    Object.entries(where).every(([key, want]) => {
      const have = row[key];
      // The only FindOperator these tests use is In(LIVE_STATUSES).
      if (want && typeof want === 'object' && '_value' in (want as object)) {
        return ((want as { _value: unknown[] })._value ?? []).includes(have);
      }
      return have === want;
    });

  const subscriptions = {
    rows: subs,
    create: (row: Sub) => row,
    save: (row: Sub) => {
      const at = subs.findIndex((r) => r === row || (r.id && r.id === row.id));
      const saved = { id: row.id ?? `s${subs.length + 1}`, ...row };
      if (at >= 0) subs[at] = saved;
      else subs.push(saved);
      return Promise.resolve(saved);
    },
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(subs.find((r) => matches(r as never, where)) ?? null),
  };

  const trials = {
    rows: grants,
    create: (row: Partial<TrialGrantEntity>) => row,
    save: (row: Partial<TrialGrantEntity>) => {
      grants.push(row);
      return Promise.resolve(row);
    },
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(grants.find((r) => matches(r as never, where)) ?? null),
  };

  return { subscriptions, trials };
}

function serviceWith(
  store: ReturnType<typeof repos>,
  sent: { kind: string; dedupeKey?: string }[] = [],
  phone: string | null = '+919000000702',
) {
  const users = {
    findOne: () =>
      Promise.resolve(phone ? { id: 1, phone } : { id: 1, phone: null }),
  } as unknown as Repository<UserEntity>;

  const notifications = {
    notify: (input: { kind: string; dedupeKey?: string }) => {
      sent.push(input);
      return Promise.resolve(null);
    },
  } as unknown as NotificationsService;

  const config = {
    get: () => 'test-pepper',
  } as unknown as ConfigService;

  return new SubscriptionService(
    store.subscriptions as unknown as Repository<SubscriptionEntity>,
    store.trials as unknown as Repository<TrialGrantEntity>,
    users,
    notifications,
    config as never,
  );
}

const paidPro: Sub = {
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
};

describe('the free week (docs/11 §6)', () => {
  it('should run for seven days and convert unless cancelled', async () => {
    const store = repos();
    const state = await serviceWith(store).startTrial(1, 'PRO', NOW);

    expect(state).toMatchObject({
      tier: 'PRO',
      status: 'trialing',
      auto_renew: true,
    });
    expect(new Date(state.trial_ends_at!).getTime() - NOW.getTime()).toBe(
      TRIAL_DAYS * 86_400_000,
    );
    expect(store.subscriptions.rows[0].paidPaise).toBeNull();
  });

  it('should be offered once per number, for life', async () => {
    const store = repos();
    const service = serviceWith(store);
    await service.startTrial(1, 'PRO', NOW);

    // The trial ran out and the row is history; the same number asks again.
    store.subscriptions.rows[0].status = 'expired';

    await expect(
      service.startTrial(1, 'BASIC', new Date('2026-10-01T00:00:00Z')),
    ).rejects.toMatchObject({
      response: { error: { code: 'TRIAL_ALREADY_USED' } },
    });
    expect(store.trials.rows).toHaveLength(1);
  });

  it('should refuse while a plan is already running', async () => {
    const store = repos([paidPro]);

    await expect(
      serviceWith(store).startTrial(1, 'PRO', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'ALREADY_SUBSCRIBED' } },
    });
  });

  it('should refuse an account with no number to key it on', async () => {
    const store = repos();

    await expect(
      serviceWith(store, [], null).startTrial(1, 'PRO', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'PHONE_REQUIRED' } },
    });
  });

  it('should say it is no longer available once it has been taken', async () => {
    const store = repos();
    const service = serviceWith(store);

    expect((await service.state(1, NOW)).trial_available).toBe(true);
    await service.startTrial(1, 'PRO', NOW);
    expect((await service.state(1, NOW)).trial_available).toBe(false);
  });
});

describe('cancelling (docs/09 §7)', () => {
  it('should stop the renewal and keep the access already paid for', async () => {
    const store = repos([{ ...paidPro }]);
    const sent: { kind: string; dedupeKey?: string }[] = [];

    const state = await serviceWith(store, sent).cancel(
      1,
      'too expensive',
      NOW,
    );

    expect(state).toMatchObject({ tier: 'PRO', auto_renew: false });
    expect(state.ends_at).toBe('2026-12-01T00:00:00.000Z');
    expect(state.cancelled_at).toBe(NOW.toISOString());
    expect(store.subscriptions.rows[0].status).toBe('active');
  });

  it('should leave a message saying what is kept and until when', async () => {
    const store = repos([{ ...paidPro }]);
    const sent: { kind: string; dedupeKey?: string }[] = [];

    await serviceWith(store, sent).cancel(1, null, NOW);

    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      kind: 'subscription_cancelled',
      dedupeKey: 'cancelled:sub-1',
    });
  });

  it('should refuse when there is nothing running', async () => {
    const store = repos();

    await expect(serviceWith(store).cancel(1, null, NOW)).rejects.toMatchObject(
      {
        response: { error: { code: 'NO_ACTIVE_PLAN' } },
      },
    );
  });
});

describe('the upgrade quote (docs/11 §7)', () => {
  it('should credit what is left of the running plan', async () => {
    const store = repos([
      { ...paidPro, tier: 'BASIC', paidPaise: '119900', priceKey: 'BASIC:6M' },
    ]);

    const quote = await serviceWith(store).upgradeQuote(1, 'PRO', '6M', NOW);

    expect(quote.price_paise).toBe(279_900);
    expect(quote.proration.credit_paise).toBeGreaterThan(0);
    expect(quote.proration.amount_due_paise).toBe(
      279_900 - quote.proration.credit_paise,
    );
  });

  it('should refuse a downgrade, which takes effect at period end instead', async () => {
    const store = repos([{ ...paidPro }]);

    await expect(
      serviceWith(store).upgradeQuote(1, 'BASIC', '6M', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'NOT_AN_UPGRADE' } },
    });
  });

  it('should refuse when nothing is running to upgrade from', async () => {
    const store = repos();

    await expect(
      serviceWith(store).upgradeQuote(1, 'PRO', '6M', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'NO_ACTIVE_PLAN' } },
    });
  });
});

describe('what the app is told', () => {
  it('should read FREE, not nothing, when no plan is running', async () => {
    const state = await serviceWith(repos()).state(1, NOW);

    expect(state).toMatchObject({
      tier: 'FREE',
      ends_at: null,
      auto_renew: false,
    });
    expect(state.entitlements).toBeDefined();
  });

  it('should treat a period that has run out as over, whatever the status says', async () => {
    const store = repos([
      { ...paidPro, currentPeriodEnd: new Date('2026-09-01T00:00:00Z') },
    ]);

    expect((await serviceWith(store).state(1, NOW)).tier).toBe('FREE');
  });
});
