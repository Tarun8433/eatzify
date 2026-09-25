import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  AttributionEntity,
  CommissionEntryEntity,
  CommissionRateEntity,
} from './entities/commission-entry.entity';

/**
 * GST, inclusive in every listed price (docs/11 §2, docs/12 §1).
 *
 * In basis points so the arithmetic stays integer. Net revenue is gross divided by 1.18, because
 * the price the customer paid already contains the tax — taking 18 % OFF the gross would understate
 * net and underpay every partner.
 */
const GST_BPS = 1800;

/// docs/12 §4: an entry is held through the refund window before it can be paid.
const REFUND_WINDOW_DAYS = 7;

/// Which rate table entries are written against today. Bumped, never edited.
const RATE_VERSION = 'v1';

export type EarningsView = {
  period: string;
  total_paise: string;
  breakdown: {
    client_payments_paise: string;
    bonus_paise: string;
    other_paise: string;
  };
  /// One point per day of the period, zero-filled. A missing day is ₹0 earned, and dropping it
  /// would draw a line that skips over the quiet weeks.
  sparkline: { date: string; paise: string }[];
  /// Null, never zero, when there is no previous period to compare against. A first month is not
  /// a flat month.
  pct_change: number | null;
};

/**
 * What a partner earned, and the ledger behind it.
 *
 * Two rules from docs/12 shape everything here. **Commission is on NET revenue** — gross minus GST
 * minus any store fee — because paying on gross pays a share of the government's money. And **a
 * reversal is an insert**, never an edit, so a period total is a plain SUM and the history of how
 * it got there survives a refund.
 */
@Injectable()
export class CommissionService {
  private readonly log = new Logger(CommissionService.name);

  constructor(
    @InjectRepository(CommissionEntryEntity)
    private readonly entries: Repository<CommissionEntryEntity>,
    @InjectRepository(CommissionRateEntity)
    private readonly rates: Repository<CommissionRateEntity>,
    @InjectRepository(AttributionEntity)
    private readonly attributions: Repository<AttributionEntity>,
  ) {}

  /**
   * Gross paise to net paise.
   *
   * The price is GST-inclusive, so net is `gross × 10000 / (10000 + GST_BPS)`. Integer division
   * throughout — `api/CLAUDE.md` rule 3 has no room for a float anywhere near money, and rounding
   * down means the platform never over-pays on a rounding edge.
   */
  static netOf(grossPaise: bigint, storeFeePaise = 0n): bigint {
    const afterStore = grossPaise - storeFeePaise;
    return (afterStore * 10_000n) / BigInt(10_000 + GST_BPS);
  }

  /**
   * Write the entry for a paid order, if the buyer was referred by anyone.
   *
   * Called from the payment webhook, which is the only place a payment is known to be real
   * (D-194). Silent and idempotent: a buyer with no attribution earns nobody anything, and Cashfree
   * retrying a webhook must not pay twice — the unique index on `paymentOrderId` is what enforces
   * the second part, not a check that could race.
   */
  async accrueFor({
    clientUserId,
    paymentOrderId,
    tier,
    grossPaise,
    isRenewal,
    now,
  }: {
    clientUserId: number;
    paymentOrderId: string;
    tier: string;
    grossPaise: bigint;
    isRenewal: boolean;
    now: Date;
  }): Promise<CommissionEntryEntity | null> {
    const attribution = await this.attributions.findOne({
      where: { userId: clientUserId },
    });
    if (!attribution) return null;

    const kind = isRenewal ? 'renewal' : 'first_purchase';
    const rate = await this.rates.findOne({
      where: { version: RATE_VERSION, tier, kind },
    });

    // A tier with no rate row earns nothing rather than a guessed percentage. A wrong rate is
    // money out of the wrong pocket, and a missing one is visible in a log.
    if (!rate) {
      this.log.warn(
        `no ${RATE_VERSION} commission rate for ${tier}/${kind}; order ${paymentOrderId} accrued nothing`,
      );
      return null;
    }

    const netPaise = CommissionService.netOf(grossPaise);
    const amountPaise = (netPaise * BigInt(rate.rateBps)) / 10_000n;

    const holdUntil = new Date(now);
    holdUntil.setDate(holdUntil.getDate() + REFUND_WINDOW_DAYS);

    try {
      return await this.entries.save(
        this.entries.create({
          partnerUserId: attribution.partnerUserId,
          clientUserId,
          paymentOrderId,
          kind,
          rateVersion: RATE_VERSION,
          rateBps: rate.rateBps,
          grossPaise: grossPaise.toString(),
          netPaise: netPaise.toString(),
          amountPaise: amountPaise.toString(),
          status: 'accrued',
          periodMonth: monthOf(now),
          holdUntil,
        }),
      );
    } catch {
      // The unique index refused it: this order already earned somebody a commission, which is a
      // retried webhook and not an error worth failing the payment over.
      return null;
    }
  }

  /// Every entry a refunded order earned, reversed (docs/12 §3). Nothing to reverse is the normal
  /// case: most buyers arrived on their own.
  async reverseForOrder(paymentOrderId: string, now: Date): Promise<void> {
    const earned = await this.entries.find({
      where: { paymentOrderId, status: 'payable' },
    });
    for (const entry of earned) {
      if (entry.kind === 'reversal') continue;
      await this.reverse(entry.id, now);
    }
  }

  /**
   * Reverse an entry after a refund (docs/12 §3).
   *
   * An offsetting row, not a delete and not an edit. The original keeps its amount and gains a
   * `reversed` status; the new row carries the negative. A ledger where a number can change is one
   * nobody can reconcile against a bank statement.
   */
  async reverse(entryId: string, now: Date): Promise<void> {
    const original = await this.entries.findOne({ where: { id: entryId } });
    if (!original || original.status === 'reversed') return;

    await this.entries.save(
      this.entries.create({
        partnerUserId: original.partnerUserId,
        clientUserId: original.clientUserId,
        paymentOrderId: original.paymentOrderId,
        kind: 'reversal',
        rateVersion: original.rateVersion,
        rateBps: original.rateBps,
        grossPaise: original.grossPaise,
        netPaise: original.netPaise,
        amountPaise: (-BigInt(original.amountPaise)).toString(),
        status: 'payable',
        // The month the REVERSAL happened, not the month of the sale. A refund in October is
        // October's cost; restating September would rewrite a statement already sent.
        periodMonth: monthOf(now),
        reversesId: original.id,
      }),
    );

    await this.entries.update(entryId, { status: 'reversed' });
  }

  /**
   * One month's earnings, aggregate only.
   *
   * docs/12 §8 keeps a partner's view aggregate: a per-client line would tell an affiliate exactly
   * what one person paid, which is neither their business nor something the client agreed to.
   */
  async earnings(
    partnerUserId: number,
    period: string,
    now: Date,
  ): Promise<EarningsView> {
    const [rows, previous] = await Promise.all([
      this.entries.find({ where: { partnerUserId, periodMonth: period } }),
      this.entries.find({
        where: { partnerUserId, periodMonth: previousMonth(period) },
      }),
    ]);

    const sum = (of: readonly CommissionEntryEntity[]) =>
      of.reduce((total, e) => total + BigInt(e.amountPaise), 0n);

    const total = sum(rows);
    const prior = sum(previous);

    const clientPayments = sum(
      rows.filter((e) => e.kind === 'first_purchase' || e.kind === 'renewal'),
    );
    const bonus = sum(rows.filter((e) => e.kind === 'bonus'));

    return {
      period,
      total_paise: total.toString(),
      breakdown: {
        client_payments_paise: clientPayments.toString(),
        bonus_paise: bonus.toString(),
        // Everything else, reversals included — a refunded month should show why it is down.
        other_paise: (total - clientPayments - bonus).toString(),
      },
      sparkline: dailySeries(rows, period),
      pct_change: prior === 0n ? null : percentChange(prior, total),
    };
  }

  /// docs/12 §4: accrued becomes payable once the refund window closes. Derived on read rather than
  /// swept by a job, because there is no scheduler — and a status that needs a cron to be true is
  /// a status that is wrong every time the cron fails.
  static isPayable(entry: CommissionEntryEntity, now: Date): boolean {
    if (entry.status === 'payable' || entry.status === 'paid') return true;
    if (entry.status !== 'accrued') return false;

    return entry.holdUntil === null || entry.holdUntil <= now;
  }
}

function monthOf(at: Date): string {
  return at.toISOString().slice(0, 7);
}

function previousMonth(period: string): string {
  const [year = 0, month = 1] = period.split('-').map(Number);
  const at = new Date(Date.UTC(year, month - 2, 1));
  return monthOf(at);
}

/// Integer percent, computed in paise so no float touches money on the way to a display string.
function percentChange(from: bigint, to: bigint): number {
  return Number(((to - from) * 100n) / (from < 0n ? -from : from));
}

/// One point per day of the month, zero-filled. A quiet week is a flat line, not a gap.
function dailySeries(
  rows: readonly CommissionEntryEntity[],
  period: string,
): { date: string; paise: string }[] {
  const [year = 0, month = 1] = period.split('-').map(Number);
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate();

  const byDay = new Map<string, bigint>();
  for (const entry of rows) {
    const day = entry.createdAt.toISOString().slice(0, 10);
    byDay.set(day, (byDay.get(day) ?? 0n) + BigInt(entry.amountPaise));
  }

  return Array.from({ length: days }, (_, i) => {
    const date = `${period}-${String(i + 1).padStart(2, '0')}`;
    return { date, paise: (byDay.get(date) ?? 0n).toString() };
  });
}
