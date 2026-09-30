import {
  ConflictException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  In,
  IsNull,
  LessThanOrEqual,
  Repository,
  type EntityManager,
} from 'typeorm';
import { CommissionEntryEntity } from './entities/commission-entry.entity';
import {
  PartnerKycEntity,
  PayoutEntity,
  TdsRateEntity,
} from './entities/payout.entity';
import { isSettleable, payoutDecision, type PayoutBlock } from './payout-rules';

/// Admin-facing refusals. Server-held copy, like every other `user_message` (rule 7).
const TDS_RATE_MISSING =
  'No TDS rate is set. Add the rate your CA confirmed before running payouts.';
const PAYOUT_NOT_PENDING = 'This payout is not waiting for approval.';
const PAYOUT_NOT_FOUND = 'That payout does not exist.';

export type PayoutRunReport = {
  period: string;
  prepared: number;
  skipped: Partial<Record<PayoutBlock | 'already_prepared', number>>;
};

export type ReconciliationReport = {
  ok: boolean;
  entriesPaise: string;
  payoutsPaise: string;
};

export type PayoutView = {
  id: string;
  period: string;
  gross_paise: string;
  tds_paise: string;
  net_paise: string;
  status: string;
  utr: string | null;
  paid_at: string | null;
};

/**
 * docs/12 §4–§5: turning the ledger into money a person actually receives.
 *
 * The server prepares and records; it never moves money. A payout sits at `pending_approval` until
 * a human who has sent the transfer from the accounting system marks it paid with the UTR.
 */
@Injectable()
export class PayoutService {
  private readonly log = new Logger(PayoutService.name);

  constructor(
    @InjectRepository(PayoutEntity)
    private readonly payouts: Repository<PayoutEntity>,
    @InjectRepository(CommissionEntryEntity)
    private readonly entries: Repository<CommissionEntryEntity>,
    @InjectRepository(PartnerKycEntity)
    private readonly kyc: Repository<PartnerKycEntity>,
    @InjectRepository(TdsRateEntity)
    private readonly tdsRates: Repository<TdsRateEntity>,
  ) {}

  /**
   * The monthly run: every partner's settleable balance up to [period] becomes a payout awaiting
   * approval, or waits (below ₹1,000, KYC, a fresh bank change). Safe to run twice.
   */
  async prepare(period: string, now: Date): Promise<PayoutRunReport> {
    const rate = await this.tdsRates.findOne({
      where: { effectiveFrom: LessThanOrEqual(now) },
      order: { effectiveFrom: 'DESC' },
    });
    if (!rate) {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: { code: 'TDS_RATE_MISSING', user_message: TDS_RATE_MISSING },
      });
    }

    const candidates = await this.entries.find({
      where: {
        payoutId: IsNull(),
        periodMonth: LessThanOrEqual(period),
        status: In(['accrued', 'payable', 'reversed']),
      },
    });
    // ponytail: grouped in memory; page by partner once the ledger outgrows one query.
    const byPartner = new Map<number, CommissionEntryEntity[]>();
    for (const e of candidates.filter((c) => isSettleable(c, now))) {
      byPartner.set(e.partnerUserId, [
        ...(byPartner.get(e.partnerUserId) ?? []),
        e,
      ]);
    }

    const report: PayoutRunReport = { period, prepared: 0, skipped: {} };
    const skip = (why: keyof PayoutRunReport['skipped']) => {
      report.skipped[why] = (report.skipped[why] ?? 0) + 1;
    };

    for (const [partnerUserId, rows] of byPartner) {
      const balancePaise = rows.reduce((t, e) => t + BigInt(e.amountPaise), 0n);
      const decision = payoutDecision({
        balancePaise,
        kyc: await this.kyc.findOne({ where: { partnerUserId } }),
        tdsRateBps: rate.rateBps,
        now,
      });
      if (!decision.ok) {
        skip(decision.reason);
        continue;
      }
      const made = await this.createPayout(
        partnerUserId,
        period,
        rate.rateBps,
        decision,
        rows,
      );
      if (made) report.prepared++;
      else skip('already_prepared');
    }
    return report;
  }

  /// A human sent the money; [utr] is the bank's reference for it.
  async markPaid(
    id: string,
    utr: string,
    adminUserId: number,
    now: Date,
  ): Promise<PayoutEntity> {
    return this.payouts.manager.transaction(async (m) => {
      const payout = await this.pending(m, id);
      await m
        .getRepository(CommissionEntryEntity)
        .update(
          { payoutId: id, status: In(['accrued', 'payable']) },
          { status: 'paid' },
        );
      return m.getRepository(PayoutEntity).save({
        ...payout,
        status: 'paid',
        utr,
        approvedBy: adminUserId,
        paidAt: now,
      });
    });
  }

  /// Not sent after all: the rows go back to the ledger and join the next run.
  async cancel(id: string): Promise<PayoutEntity> {
    return this.payouts.manager.transaction(async (m) => {
      const payout = await this.pending(m, id);
      await m
        .getRepository(CommissionEntryEntity)
        .update({ payoutId: id }, { payoutId: null });
      return m
        .getRepository(PayoutEntity)
        .save({ ...payout, status: 'cancelled' });
    });
  }

  /**
   * docs/12 §4's nightly invariant: what the ledger says was paid equals what payouts say was paid.
   * Keyed on the payout each row belongs to rather than the row's status, because a paid row that
   * is later refunded becomes `reversed` and would otherwise drop out of the sum.
   */
  async reconcile(): Promise<ReconciliationReport> {
    const [entries] = (await this.entries.query(
      `SELECT COALESCE(SUM(e."amountPaise"), 0)::text AS total
         FROM "commission_entry" e JOIN "payout" p ON p."id" = e."payoutId"
        WHERE p."status" = 'paid'`,
    )) as { total: string }[];
    const [payouts] = (await this.payouts.query(
      `SELECT COALESCE(SUM("grossPaise"), 0)::text AS total FROM "payout" WHERE "status" = 'paid'`,
    )) as { total: string }[];

    const report = {
      ok: entries.total === payouts.total,
      entriesPaise: entries.total,
      payoutsPaise: payouts.total,
    };
    if (!report.ok) {
      // docs/12 §4: "If it ever fails, page someone." Error level reaches Sentry. Totals only.
      this.log.error(
        `commission ledger does not reconcile: entries ${report.entriesPaise} vs payouts ${report.payoutsPaise}`,
      );
    }
    return report;
  }

  async listForPartner(partnerUserId: number): Promise<PayoutView[]> {
    const rows = await this.payouts.find({
      where: { partnerUserId, status: In(['pending_approval', 'paid']) },
      order: { createdAt: 'DESC' },
    });
    return rows.map(payoutView);
  }

  async listByStatus(
    status: PayoutEntity['status'],
  ): Promise<(PayoutView & { partner_user_id: number })[]> {
    const rows = await this.payouts.find({
      where: { status },
      order: { createdAt: 'ASC' },
    });
    return rows.map((p) => ({
      ...payoutView(p),
      partner_user_id: p.partnerUserId,
    }));
  }

  /**
   * docs/12 §5: "Every payout generates a downloadable statement listing each commission entry,
   * the TDS deducted, and the UTR." CSV. Each line is a date, kind and amount — never the client
   * (docs/12 §8 keeps a partner's view aggregate).
   */
  async statementCsv(partnerUserId: number, payoutId: string): Promise<string> {
    const payout = await this.payouts.findOne({
      where: { id: payoutId, partnerUserId },
    });
    if (!payout) throw notFound();
    const rows = await this.entries.find({
      where: { payoutId },
      order: { createdAt: 'ASC' },
    });

    const rupees = (paise: string | bigint) => {
      const p = BigInt(paise);
      const sign = p < 0n ? '-' : '';
      const abs = p < 0n ? -p : p;
      return `${sign}${abs / 100n}.${String(abs % 100n).padStart(2, '0')}`;
    };
    return [
      'date,period,kind,amount_inr',
      ...rows.map(
        (e) =>
          `${e.createdAt.toISOString().slice(0, 10)},${e.periodMonth},${e.kind},${rupees(e.amountPaise)}`,
      ),
      '',
      `gross_inr,${rupees(payout.grossPaise)}`,
      `tds_rate_bps,${payout.tdsRateBps}`,
      `tds_inr,${rupees(payout.tdsPaise)}`,
      `net_inr,${rupees(payout.netPaise)}`,
      `status,${payout.status}`,
      `utr,${payout.utr ?? ''}`,
      '',
    ].join('\n');
  }

  /// What this partner would be paid if a run happened now: settled rows, no month cap. Used to
  /// ask for KYC only once there is money waiting (D-255).
  async settleableBalance(partnerUserId: number, now: Date): Promise<bigint> {
    const rows = await this.entries.find({
      where: {
        partnerUserId,
        payoutId: IsNull(),
        status: In(['accrued', 'payable', 'reversed']),
      },
    });
    return rows
      .filter((e) => isSettleable(e, now))
      .reduce((t, e) => t + BigInt(e.amountPaise), 0n);
  }

  /// The CA-confirmed 194H rate from a date on. Added, never edited, so old payouts stay
  /// reproducible.
  addTdsRate(input: {
    rateBps: number;
    effectiveFrom: Date;
    note: string | null;
  }): Promise<TdsRateEntity> {
    return this.tdsRates.save(input);
  }

  listTdsRates(): Promise<TdsRateEntity[]> {
    return this.tdsRates.find({ order: { effectiveFrom: 'DESC' } });
  }

  /// Null when this partner already has a live payout for [period] (the unique index refused).
  private async createPayout(
    partnerUserId: number,
    period: string,
    tdsRateBps: number,
    amounts: { grossPaise: bigint; tdsPaise: bigint; netPaise: bigint },
    rows: CommissionEntryEntity[],
  ): Promise<PayoutEntity | null> {
    try {
      return await this.payouts.manager.transaction(async (m) => {
        const payout = await m.getRepository(PayoutEntity).save({
          partnerUserId,
          periodMonth: period,
          grossPaise: amounts.grossPaise.toString(),
          tdsRateBps,
          tdsPaise: amounts.tdsPaise.toString(),
          netPaise: amounts.netPaise.toString(),
          status: 'pending_approval' as const,
          utr: null,
          approvedBy: null,
          paidAt: null,
        });
        await m
          .getRepository(CommissionEntryEntity)
          .update(
            { id: In(rows.map((r) => r.id)), payoutId: IsNull() },
            { payoutId: payout.id },
          );
        return payout;
      });
    } catch (e) {
      if ((e as { code?: string }).code === '23505') return null;
      throw e;
    }
  }

  private async pending(m: EntityManager, id: string): Promise<PayoutEntity> {
    const payout = await m
      .getRepository(PayoutEntity)
      .findOne({ where: { id } });
    if (!payout) throw notFound();
    if (payout.status !== 'pending_approval') {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: { code: 'PAYOUT_NOT_PENDING', user_message: PAYOUT_NOT_PENDING },
      });
    }
    return payout;
  }
}

function notFound(): NotFoundException {
  return new NotFoundException({
    status: HttpStatus.NOT_FOUND,
    error: { code: 'PAYOUT_NOT_FOUND', user_message: PAYOUT_NOT_FOUND },
  });
}

export function payoutView(p: PayoutEntity): PayoutView {
  return {
    id: p.id,
    period: p.periodMonth,
    gross_paise: String(p.grossPaise),
    tds_paise: String(p.tdsPaise),
    net_paise: String(p.netPaise),
    status: p.status,
    utr: p.utr,
    paid_at: p.paidAt?.toISOString() ?? null,
  };
}
