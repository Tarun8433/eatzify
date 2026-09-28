import { CommissionService } from '../src/partner/commission.service';
import type { CommissionEntryEntity } from '../src/partner/entities/commission-entry.entity';

/**
 * docs/12 §2 and §3. Two rules decide everything here.
 *
 * **Commission is on NET revenue**, not gross — paying on gross pays a partner a share of the
 * government's GST. And **a reversal is an insert**, never an edit, so a period total is a plain
 * SUM and a refund cannot quietly rewrite a statement already sent.
 */

const NOW = new Date('2026-09-15T10:00:00Z');

function serviceWith({
  attribution = { userId: 9, partnerUserId: 2 } as {
    userId: number;
    partnerUserId: number;
  } | null,
  rate = { rateBps: 3000, renewalMonthsCap: null } as {
    rateBps: number;
    renewalMonthsCap: number | null;
  } | null,
  existing = [] as Partial<CommissionEntryEntity>[],
} = {}) {
  const written: Partial<CommissionEntryEntity>[] = [...existing];
  const updates: { id: string; patch: Record<string, unknown> }[] = [];

  const service = new CommissionService(
    {
      create: (row: Partial<CommissionEntryEntity>) => row,
      save: (row: Partial<CommissionEntryEntity>) => {
        written.push({ ...row, id: `e${written.length + 1}` });
        return Promise.resolve({ ...row, id: `e${written.length}` });
      },
      find: ({ where }: { where: { periodMonth: string } }) =>
        Promise.resolve(
          written.filter((e) => e.periodMonth === where.periodMonth),
        ),
      findOne: ({ where }: { where: { id: string } }) =>
        Promise.resolve(written.find((e) => e.id === where.id) ?? null),
      update: (id: string, patch: Record<string, unknown>) => {
        updates.push({ id, patch });
        const row = written.find((e) => e.id === id);
        if (row) Object.assign(row, patch);
        return Promise.resolve({ affected: 1 });
      },
    } as never,
    { findOne: () => Promise.resolve(rate) } as never,
    { findOne: () => Promise.resolve(attribution) } as never,
  );

  return { service, written, updates };
}

const SALE = {
  clientUserId: 9,
  paymentOrderId: 'order-1',
  tier: 'PRO' as const,
  grossPaise: 499_900n,
  isRenewal: false,
  now: NOW,
};

describe('net revenue', () => {
  /// docs/11 §2 prices are GST-INCLUSIVE, so net is gross divided by 1.18. Taking 18 % off the
  /// gross instead would understate net by about 2.7 % and underpay every partner, every month.
  it('should divide out the inclusive GST rather than subtracting it', () => {
    const net = CommissionService.netOf(499_900n);

    // ₹4,999 inclusive is ₹4,236.44 of revenue. Subtracting 18 % would have given ₹4,099.18.
    expect(net).toBe(423_644n);
    expect(net).not.toBe(499_900n - (499_900n * 18n) / 100n);
  });

  /// docs/12 §3: "Commission is on net revenue (gross − GST − store fee), never on gross."
  it('should take the store fee off before the tax', () => {
    const withStore = CommissionService.netOf(499_900n, 74_985n);

    expect(withStore).toBeLessThan(CommissionService.netOf(499_900n));
  });

  /// Rule 3. Every figure is a bigint from end to end; nothing here can produce a fraction of a
  /// paisa that later rounds in somebody's favour.
  it('should stay an integer at every step', () => {
    expect(typeof CommissionService.netOf(1n)).toBe('bigint');
    expect(CommissionService.netOf(1n)).toBe(0n);
  });
});

describe('writing an entry', () => {
  it('should pay the rate on net, not on gross', async () => {
    const { service, written } = serviceWith();

    await service.accrueFor(SALE);

    // 30 % of ₹4,236.44 is ₹1,270.93.
    expect(written[0]?.amountPaise).toBe('127093');
    expect(written[0]?.netPaise).toBe('423644');
    expect(written[0]?.grossPaise).toBe('499900');
  });

  /// The rate a historical entry was written at has to survive a rate change, or last year's
  /// earnings silently restate themselves (docs/12 §2).
  it('should store the rate and its version on the entry', async () => {
    const { service, written } = serviceWith();

    await service.accrueFor(SALE);

    expect(written[0]?.rateBps).toBe(3000);
    expect(written[0]?.rateVersion).toBe('v1');
  });

  /// Most buyers arrived on their own. Earning nobody anything is the ordinary case, not an error.
  it('should write nothing when the buyer was never referred', async () => {
    const { service, written } = serviceWith({ attribution: null });

    expect(await service.accrueFor(SALE)).toBeNull();
    expect(written).toEqual([]);
  });

  /// A wrong rate is money out of the wrong pocket. A missing one earns nothing and says so in a
  /// log, rather than guessing a percentage.
  it('should write nothing when no rate is configured for the tier', async () => {
    const { service, written } = serviceWith({ rate: null });

    expect(await service.accrueFor(SALE)).toBeNull();
    expect(written).toEqual([]);
  });

  /// docs/12 §4 holds an entry through the refund window before it can be paid.
  it('should hold the entry for the refund window', async () => {
    const { service, written } = serviceWith();

    await service.accrueFor(SALE);

    expect(written[0]?.status).toBe('accrued');
    expect(written[0]?.holdUntil?.toISOString()).toBe(
      '2026-09-22T10:00:00.000Z',
    );
  });
});

describe('reversing an entry after a refund', () => {
  /// A FUNCTION, not a constant. The fake's `update` mutates the row in place, so a shared object
  /// would carry one test's reversal into the next — the ordering dependency `.claude/rules` bans.
  const original = (): Partial<CommissionEntryEntity> => ({
    id: 'e1',
    partnerUserId: 2,
    clientUserId: 9,
    paymentOrderId: 'order-1',
    kind: 'first_purchase',
    rateVersion: 'v1',
    rateBps: 3000,
    grossPaise: '499900',
    netPaise: '423644',
    amountPaise: '127093',
    status: 'accrued',
    periodMonth: '2026-08',
  });

  /// docs/12 §3: "offsetting entry, never a delete". The original keeps its amount so the history
  /// of how a total was reached survives the refund.
  it('should insert a negative entry rather than editing the original', async () => {
    const { service, written } = serviceWith({ existing: [original()] });

    await service.reverse('e1', NOW);

    expect(written).toHaveLength(2);
    expect(written[1]?.amountPaise).toBe('-127093');
    expect(written[1]?.reversesId).toBe('e1');
    expect(written[0]?.amountPaise).toBe('127093');
  });

  it('should mark the original reversed', async () => {
    const { service, updates } = serviceWith({ existing: [original()] });

    await service.reverse('e1', NOW);

    expect(updates[0]).toEqual({ id: 'e1', patch: { status: 'reversed' } });
  });

  /// A refund in October is October's cost. Restating September would rewrite a statement the
  /// partner has already been sent.
  it('should book the reversal in the month it happened', async () => {
    const { service, written } = serviceWith({ existing: [original()] });

    await service.reverse('e1', NOW);

    expect(written[1]?.periodMonth).toBe('2026-09');
    expect(written[0]?.periodMonth).toBe('2026-08');
  });

  it('should refuse to reverse the same entry twice', async () => {
    const { service, written } = serviceWith({
      existing: [{ ...original(), status: 'reversed' }],
    });

    await service.reverse('e1', NOW);

    expect(written).toHaveLength(1);
  });
});

describe('a month of earnings', () => {
  const entry = (
    over: Partial<CommissionEntryEntity>,
  ): Partial<CommissionEntryEntity> => ({
    id: `x${Math.random()}`,
    partnerUserId: 2,
    kind: 'first_purchase',
    amountPaise: '100000',
    periodMonth: '2026-09',
    createdAt: new Date('2026-09-03T00:00:00Z'),
    ...over,
  });

  it('should total the month and split it by kind', async () => {
    const { service } = serviceWith({
      existing: [
        entry({}),
        entry({ kind: 'renewal', amountPaise: '40000' }),
        entry({ kind: 'bonus', amountPaise: '25000' }),
      ],
    });

    const view = await service.earnings(2, '2026-09', NOW);

    expect(view.total_paise).toBe('165000');
    expect(view.breakdown.client_payments_paise).toBe('140000');
    expect(view.breakdown.bonus_paise).toBe('25000');
  });

  /// A reversal is part of the month's total and shows in "other", so a month that went down shows
  /// why rather than simply being smaller.
  it('should let a reversal pull the month down', async () => {
    const { service } = serviceWith({
      existing: [
        entry({}),
        entry({ kind: 'reversal', amountPaise: '-100000' }),
      ],
    });

    const view = await service.earnings(2, '2026-09', NOW);

    expect(view.total_paise).toBe('0');
    expect(view.breakdown.other_paise).toBe('-100000');
  });

  /// A first month is not a flat month. docs/21 makes null-not-zero the rule for the client
  /// dashboard and the same reasoning holds here.
  it('should report no change rather than zero when there is no previous month', async () => {
    const { service } = serviceWith({ existing: [entry({})] });

    expect((await service.earnings(2, '2026-09', NOW)).pct_change).toBeNull();
  });

  /// A quiet week is a flat line, not a gap in the chart.
  it('should give one sparkline point per day of the month, zero-filled', async () => {
    const { service } = serviceWith({ existing: [entry({})] });

    const view = await service.earnings(2, '2026-09', NOW);

    expect(view.sparkline).toHaveLength(30);
    expect(view.sparkline[2]).toEqual({ date: '2026-09-03', paise: '100000' });
    expect(view.sparkline[0]).toEqual({ date: '2026-09-01', paise: '0' });
  });
});

describe('when an accrued entry becomes payable', () => {
  const held = (holdUntil: Date | null, status = 'accrued') =>
    ({ status, holdUntil }) as CommissionEntryEntity;

  it('should hold it until the refund window closes', () => {
    expect(
      CommissionService.isPayable(held(new Date('2026-09-22T00:00:00Z')), NOW),
    ).toBe(false);
  });

  it('should release it once the window has passed', () => {
    expect(
      CommissionService.isPayable(held(new Date('2026-09-01T00:00:00Z')), NOW),
    ).toBe(true);
  });

  /// Derived on read, not swept by a job. There is no scheduler, and a status that needs a cron to
  /// be true is a status that is wrong every time the cron fails.
  it('should not need a sweep to have run', () => {
    expect(CommissionService.isPayable(held(null), NOW)).toBe(true);
  });

  it('should never call a reversed entry payable', () => {
    expect(CommissionService.isPayable(held(null, 'reversed'), NOW)).toBe(
      false,
    );
  });
});
