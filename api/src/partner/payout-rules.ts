import type { CommissionEntryEntity } from './entities/commission-entry.entity';
import type { PartnerKycEntity } from './entities/payout.entity';

/// docs/12 §5 and §7, as pure functions so every branch is table-tested without a database.

/// docs/12 §5: "Minimum: ₹1,000. Below threshold rolls forward." In paise (api rule 3).
export const PAYOUT_MINIMUM_PAISE = 100_000n;

/// docs/12 §7: "Bank change freezes payouts for 7 days + re-verification".
export const BANK_CHANGE_FREEZE_DAYS = 7;

const DAY_MS = 24 * 60 * 60 * 1000;
const BPS = 10_000n;

export type PayoutBlock =
  'below_minimum' | 'kyc_missing' | 'kyc_unverified' | 'bank_recently_changed';

export type PayoutDecision =
  | { ok: false; reason: PayoutBlock }
  | { ok: true; grossPaise: bigint; tdsPaise: bigint; netPaise: bigint };

/**
 * Whether a ledger row goes into the next payout.
 *
 * Past its refund hold and not yet settled. A reversed original is included WITH its reversal
 * (they share a hold date), so the pair nets to zero rather than the reversal alone docking the
 * partner for money they were never paid.
 */
export function isSettleable(
  entry: Pick<CommissionEntryEntity, 'status' | 'holdUntil' | 'payoutId'>,
  now: Date,
): boolean {
  if (entry.payoutId) return false;
  if (entry.status === 'paid') return false;
  return entry.holdUntil === null || entry.holdUntil <= now;
}

export function tdsOf(grossPaise: bigint, rateBps: number): bigint {
  // Rounded down: the partner is never over-deducted on a rounding edge.
  return (grossPaise * BigInt(rateBps)) / BPS;
}

/// What one partner's settleable balance becomes this run, or why it waits.
export function payoutDecision(input: {
  balancePaise: bigint;
  kyc: Pick<PartnerKycEntity, 'status' | 'bankChangedAt'> | null;
  tdsRateBps: number;
  now: Date;
}): PayoutDecision {
  const { balancePaise, kyc, tdsRateBps, now } = input;
  // A clawback bigger than the month's earnings is a negative balance: it waits for earnings too.
  if (balancePaise < PAYOUT_MINIMUM_PAISE) {
    return { ok: false, reason: 'below_minimum' };
  }
  if (!kyc) return { ok: false, reason: 'kyc_missing' };
  if (kyc.status !== 'verified') return { ok: false, reason: 'kyc_unverified' };
  if (
    now.getTime() - kyc.bankChangedAt.getTime() <
    BANK_CHANGE_FREEZE_DAYS * DAY_MS
  ) {
    return { ok: false, reason: 'bank_recently_changed' };
  }

  // ponytail: a flat rate on each payout. The 194H annual threshold, and what happens when a
  // partner crosses it mid-year, is the CA's call (docs/12 §5) — add it here once they have said.
  const tdsPaise = tdsOf(balancePaise, tdsRateBps);
  return {
    ok: true,
    grossPaise: balancePaise,
    tdsPaise,
    netPaise: balancePaise - tdsPaise,
  };
}

/// The month before [now], `YYYY-MM`, in UTC — what the run on the 1st pays for.
export function previousPeriod(now: Date): string {
  const at = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  return at.toISOString().slice(0, 7);
}
