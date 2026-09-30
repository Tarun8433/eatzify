import { FindOperator } from 'typeorm';
import { CommissionService } from '../src/partner/commission.service';
import { PayoutService } from '../src/partner/payout.service';
import {
  isSettleable,
  payoutDecision,
  previousPeriod,
  tdsOf,
} from '../src/partner/payout-rules';

/// docs/12 §4–§5, payments plan Phase 6: the ledger becomes a payout a human approves.

const NOW = new Date('2026-10-01T00:30:00Z');
const OLD_BANK = new Date('2026-08-01T00:00:00Z');
const VERIFIED = { status: 'verified' as const, bankChangedAt: OLD_BANK };

describe('payout rules', () => {
  it('should hold back a balance under ₹1,000 so it rolls forward', () => {
    expect(
      payoutDecision({
        balancePaise: 99_999n,
        kyc: VERIFIED,
        tdsRateBps: 200,
        now: NOW,
      }),
    ).toEqual({ ok: false, reason: 'below_minimum' });
  });

  it('should hold back a negative balance (a clawback larger than the month)', () => {
    expect(
      payoutDecision({
        balancePaise: -500n,
        kyc: VERIFIED,
        tdsRateBps: 200,
        now: NOW,
      }),
    ).toEqual({ ok: false, reason: 'below_minimum' });
  });

  it.each([
    [null, 'kyc_missing'],
    [{ status: 'pending' as const, bankChangedAt: OLD_BANK }, 'kyc_unverified'],
    [
      { status: 'rejected' as const, bankChangedAt: OLD_BANK },
      'kyc_unverified',
    ],
    [
      {
        status: 'verified' as const,
        bankChangedAt: new Date('2026-09-28T00:00:00Z'),
      },
      'bank_recently_changed',
    ],
  ])('should block payment without clean KYC (%#)', (kyc, reason) => {
    expect(
      payoutDecision({
        balancePaise: 500_000n,
        kyc,
        tdsRateBps: 200,
        now: NOW,
      }),
    ).toEqual({ ok: false, reason });
  });

  it('should deduct TDS at the configured rate, rounded down', () => {
    expect(
      payoutDecision({
        balancePaise: 123_457n,
        kyc: VERIFIED,
        tdsRateBps: 200,
        now: NOW,
      }),
    ).toEqual({
      ok: true,
      grossPaise: 123_457n,
      tdsPaise: 2_469n,
      netPaise: 120_988n,
    });
    expect(tdsOf(100_000n, 0)).toBe(0n);
  });

  it('should settle rows past their hold that no payout has taken', () => {
    const row = (over: Record<string, unknown>) => ({
      status: 'accrued' as const,
      holdUntil: new Date('2026-09-20T00:00:00Z'),
      payoutId: null,
      ...over,
    });
    expect(isSettleable(row({}), NOW)).toBe(true);
    expect(
      isSettleable(row({ holdUntil: new Date('2026-10-05T00:00:00Z') }), NOW),
    ).toBe(false);
    expect(isSettleable(row({ payoutId: 'p1' }), NOW)).toBe(false);
    expect(isSettleable(row({ status: 'paid' }), NOW)).toBe(false);
    // A reversed original is taken WITH its reversal, so the pair nets to zero.
    expect(isSettleable(row({ status: 'reversed' }), NOW)).toBe(true);
  });

  it('should pay the 1st of the month for the month before', () => {
    expect(previousPeriod(NOW)).toBe('2026-09');
    expect(previousPeriod(new Date('2026-01-01T02:00:00Z'))).toBe('2025-12');
  });
});

type Row = Record<string, unknown> & { id: string };

function matches(row: Row, where: Record<string, unknown>): boolean {
  return Object.entries(where).every(([k, v]) => {
    if (v instanceof FindOperator) {
      const value: unknown = v.value;
      switch (v.type) {
        case 'in':
          return (value as unknown[]).includes(row[k]);
        case 'isNull':
          return row[k] === null || row[k] === undefined;
        case 'lessThanOrEqual':
          return (row[k] as string | Date) <= (value as string | Date);
        case 'not':
          return row[k] !== value;
        default:
          throw new Error(`fake repo: ${v.type}`);
      }
    }
    return row[k] === v;
  });
}

/// An in-memory repository with just what the payout service asks of it.
function repo(
  rows: Row[] = [],
  opts: { unique?: (r: Row, all: Row[]) => boolean } = {},
) {
  let n = 0;
  return {
    rows,
    find: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(rows.filter((r) => matches(r, where))),
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(rows.filter((r) => matches(r, where)).at(-1) ?? null),
    save: (row: Row) => {
      if (opts.unique && !row.id && !opts.unique(row, rows)) {
        return Promise.reject(
          Object.assign(new Error('dup'), { code: '23505' }),
        );
      }
      const saved = { ...row, id: row.id ?? `r${++n}` };
      const at = rows.findIndex((r) => r.id === saved.id);
      if (at >= 0) rows[at] = saved;
      else rows.push(saved);
      return Promise.resolve(saved);
    },
    update: (
      where: Record<string, unknown> | string,
      patch: Record<string, unknown>,
    ) => {
      const w = typeof where === 'string' ? { id: where } : where;
      rows.forEach((r, i) => {
        if (matches(r, w)) rows[i] = { ...r, ...patch };
      });
      return Promise.resolve();
    },
  };
}

function setup(
  entries: Row[],
  opts: { rate?: number | null; kyc?: Row[] } = {},
) {
  const payouts = repo([], {
    // The DB's unique index: one live payout per partner per period.
    unique: (r, all) =>
      !all.some(
        (p) =>
          p.partnerUserId === r.partnerUserId &&
          p.periodMonth === r.periodMonth &&
          p.status !== 'cancelled',
      ),
  });
  const ledger = repo(entries);
  const kyc = repo(opts.kyc ?? [{ id: 'k7', partnerUserId: 7, ...VERIFIED }]);
  const rates = repo(
    opts.rate === null
      ? []
      : [{ id: 't1', rateBps: opts.rate ?? 200, effectiveFrom: OLD_BANK }],
  );
  const manager = {
    transaction: <T>(fn: (m: unknown) => Promise<T>) =>
      fn({
        getRepository: (entity: { name: string }) =>
          entity.name === 'PayoutEntity' ? payouts : ledger,
      }),
  };
  const service = new PayoutService(
    Object.assign(payouts, { manager }) as never,
    ledger as never,
    kyc as never,
    rates as never,
  );
  return { service, payouts, ledger };
}

const entry = (
  id: string,
  amountPaise: string,
  over: Record<string, unknown> = {},
) => ({
  id,
  partnerUserId: 7,
  kind: 'first_purchase',
  amountPaise,
  status: 'accrued',
  periodMonth: '2026-09',
  holdUntil: new Date('2026-09-10T00:00:00Z'),
  payoutId: null,
  createdAt: new Date('2026-09-03T00:00:00Z'),
  ...over,
});

describe('payout run', () => {
  it('should refuse to prepare anything until a TDS rate exists', async () => {
    const { service, payouts } = setup([entry('e1', '200000')], { rate: null });
    await expect(service.prepare('2026-09', NOW)).rejects.toMatchObject({
      status: 409,
    });
    expect(payouts.rows).toHaveLength(0);
  });

  it('should prepare one payout awaiting approval and attach its rows', async () => {
    const { service, payouts, ledger } = setup([
      entry('e1', '150000'),
      entry('e2', '50000', { periodMonth: '2026-08' }),
      // Still inside its refund hold, and next month's: neither is taken.
      entry('e3', '90000', { holdUntil: new Date('2026-10-04T00:00:00Z') }),
      entry('e4', '90000', { periodMonth: '2026-10' }),
    ]);

    const report = await service.prepare('2026-09', NOW);

    expect(report.prepared).toBe(1);
    expect(payouts.rows[0]).toMatchObject({
      partnerUserId: 7,
      periodMonth: '2026-09',
      grossPaise: '200000',
      tdsRateBps: 200,
      tdsPaise: '4000',
      netPaise: '196000',
      status: 'pending_approval',
    });
    const taken = ledger.rows
      .filter((r) => r.payoutId === payouts.rows[0].id)
      .map((r) => r.id);
    expect(taken).toEqual(['e1', 'e2']);
  });

  it('should net a refunded sale to zero rather than dock the partner', async () => {
    const { service, payouts } = setup([
      entry('e1', '150000'),
      entry('e2', '80000', { status: 'reversed' }),
      entry('e3', '-80000', { kind: 'reversal', status: 'payable' }),
    ]);
    await service.prepare('2026-09', NOW);
    expect(payouts.rows[0]).toMatchObject({ grossPaise: '150000' });
  });

  it('should be safe to run twice', async () => {
    const { service, payouts } = setup([entry('e1', '150000')]);
    await service.prepare('2026-09', NOW);
    const again = await service.prepare('2026-09', NOW);
    expect(payouts.rows).toHaveLength(1);
    expect(again.prepared).toBe(0);
  });

  it('should skip a partner with no KYC and report why', async () => {
    const { service, payouts } = setup([entry('e1', '150000')], { kyc: [] });
    const report = await service.prepare('2026-09', NOW);
    expect(report.skipped).toEqual({ kyc_missing: 1 });
    expect(payouts.rows).toHaveLength(0);
  });
});

describe('approving and cancelling', () => {
  it('should mark the payout and its rows paid, keeping a reversed row reversed', async () => {
    const { service, payouts, ledger } = setup([
      entry('e1', '150000'),
      entry('e2', '80000', { status: 'reversed' }),
      entry('e3', '-80000', { kind: 'reversal', status: 'payable' }),
    ]);
    await service.prepare('2026-09', NOW);
    const id = payouts.rows[0].id;

    await service.markPaid(id, 'UTR12345678', 1, NOW);

    expect(payouts.rows[0]).toMatchObject({
      status: 'paid',
      utr: 'UTR12345678',
      approvedBy: 1,
    });
    expect(ledger.rows.map((r) => r.status)).toEqual([
      'paid',
      'reversed',
      'paid',
    ]);
    await expect(
      service.markPaid(id, 'UTR12345678', 1, NOW),
    ).rejects.toMatchObject({
      status: 409,
    });
  });

  it('should return a cancelled payout’s rows to the ledger for the next run', async () => {
    const { service, payouts, ledger } = setup([entry('e1', '150000')]);
    await service.prepare('2026-09', NOW);
    await service.cancel(payouts.rows[0].id);

    expect(ledger.rows[0].payoutId).toBeNull();
    const again = await service.prepare('2026-09', NOW);
    expect(again.prepared).toBe(1);
  });
});

describe('statement', () => {
  it('should list each entry, the TDS and the UTR, and never the client', async () => {
    const { service, payouts } = setup([
      entry('e1', '150000', { clientUserId: 4242 }),
      entry('e2', '-5050', { kind: 'reversal', status: 'payable' }),
    ]);
    await service.prepare('2026-09', NOW);
    await service.markPaid(payouts.rows[0].id, 'UTR12345678', 1, NOW);

    const csv = await service.statementCsv(7, payouts.rows[0].id);

    expect(csv).toContain('2026-09-03,2026-09,first_purchase,1500.00');
    expect(csv).toContain('reversal,-50.50');
    expect(csv).toContain('tds_inr,28.99');
    expect(csv).toContain('utr,UTR12345678');
    expect(csv).not.toContain('4242');
  });

  it('should not show one partner another partner’s statement', async () => {
    const { service, payouts } = setup([entry('e1', '150000')]);
    await service.prepare('2026-09', NOW);
    await expect(
      service.statementCsv(8, payouts.rows[0].id),
    ).rejects.toMatchObject({
      status: 404,
    });
  });
});

describe('refund reversal (regression)', () => {
  /// Entries are stored `accrued` and only derived payable. reverseForOrder used to ask for
  /// `payable` alone, so a refund never reversed a commission at all.
  it('should reverse an accrued entry when its order is refunded', async () => {
    const ledger = repo([
      { ...entry('e1', '150000'), paymentOrderId: 'o1', clientUserId: 2 },
    ]);
    const saved: Row[] = [];
    const entries = {
      ...ledger,
      create: (r: Row) => r,
      save: (r: Row) => {
        saved.push(r);
        return Promise.resolve(r);
      },
    };
    const service = new CommissionService(
      entries as never,
      {} as never,
      {} as never,
    );

    await service.reverseForOrder('o1', NOW);

    expect(saved).toHaveLength(1);
    expect(saved[0]).toMatchObject({
      kind: 'reversal',
      amountPaise: '-150000',
      reversesId: 'e1',
      // Matures with the original, so an unpaid pair settles together.
      holdUntil: new Date('2026-09-10T00:00:00Z'),
    });
    expect(ledger.rows[0].status).toBe('reversed');
  });
});
