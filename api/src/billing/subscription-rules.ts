import { createHash } from 'crypto';
import { PRICES, type Tier } from './tiers';

/// docs/08 §6: the statuses a subscription that is still running can be in. The partial unique
/// index uses the same list, and anything outside it is history.
export const LIVE_STATUSES = [
  'trialing',
  'active',
  'past_due',
  'grace',
] as const;
export type LiveStatus = (typeof LIVE_STATUSES)[number];

/// docs/11 §8 / doc 00 §6. Above this, the RBI 2026 e-mandate framework requires additional factor
/// authentication on EVERY debit, so the renewal has to be assisted rather than silent.
export const AFA_THRESHOLD_PAISE = 1_500_000;

/// docs/11 §6.
export const TRIAL_DAYS = 7;

/// docs/11 §6: the reminder before a trial converts. Not optional — silent conversion is the top
/// driver of chargebacks and Play complaints.
export const TRIAL_REMINDER_HOURS = 48;

export const MONTHS_PER_DURATION: Record<string, number> = {
  '1M': 1,
  '3M': 3,
  '6M': 6,
  '9M': 9,
  '12M': 12,
};

const MS_PER_DAY = 86_400_000;

export function requiresAfa(amountPaise: number | bigint): boolean {
  return Number(amountPaise) > AFA_THRESHOLD_PAISE;
}

/// `PRO:3M` — what a period was bought at, in one string.
export function priceKeyFor(tier: Tier, duration: string): string {
  return `${tier}:${duration}`;
}

export function priceOf(tier: Tier, duration: string): number | undefined {
  return PRICES[tier as Exclude<Tier, 'FREE'>]?.[
    duration as keyof (typeof PRICES)['PRO']
  ];
}

export function periodEnd(from: Date, duration: string): Date {
  const end = new Date(from);
  end.setMonth(end.getMonth() + (MONTHS_PER_DURATION[duration] ?? 0));
  return end;
}

export function trialEnd(from: Date): Date {
  return new Date(from.getTime() + TRIAL_DAYS * MS_PER_DAY);
}

/// docs/11 §6 keys a trial on the phone, "not device — devices are shared". Hashed, because the
/// only question is "has this number had one", and the number itself is not needed to answer it.
export function phoneHash(phoneE164: string, pepper: string): string {
  return createHash('sha256').update(`${pepper}:${phoneE164}`).digest('hex');
}

export type Proration = {
  remaining_days: number;
  total_days: number;
  unused_paise: number;
  credit_paise: number;
  amount_due_paise: number;
};

/**
 * docs/11 §7's arithmetic, exactly as the doc writes it:
 *
 * ```
 * remaining_days   = ceil(ends_at - now)
 * total_days       = ends_at - starts_at
 * unused_paise     = floor(paid_paise × remaining_days / total_days)
 * credit_paise     = min(unused_paise, new_price_paise)      -- never a cash refund
 * amount_due_paise = new_price_paise - credit_paise
 * ```
 *
 * The credit is capped at the new price on purpose: an upgrade never pays money back, it only ever
 * reduces what is owed. A period that has already ended, or one nobody paid for (a trial), credits
 * nothing — and the screen shows this arithmetic, because opaque proration generates tickets.
 */
export function prorate({
  paidPaise,
  startsAt,
  endsAt,
  now,
  newPricePaise,
}: {
  paidPaise: number;
  startsAt: Date;
  endsAt: Date | null;
  now: Date;
  newPricePaise: number;
}): Proration {
  const totalMs = endsAt ? endsAt.getTime() - startsAt.getTime() : 0;
  const remainingMs = endsAt ? endsAt.getTime() - now.getTime() : 0;

  const totalDays = Math.max(0, Math.round(totalMs / MS_PER_DAY));
  const remainingDays = Math.max(0, Math.ceil(remainingMs / MS_PER_DAY));

  const unused =
    totalDays > 0 && paidPaise > 0
      ? Math.floor((paidPaise * Math.min(remainingDays, totalDays)) / totalDays)
      : 0;
  const credit = Math.min(unused, newPricePaise);

  return {
    remaining_days: remainingDays,
    total_days: totalDays,
    unused_paise: unused,
    credit_paise: credit,
    amount_due_paise: newPricePaise - credit,
  };
}

/// docs/11 §7: "downgrades take effect at period end, never immediately (no refunds)". Rank by
/// what a tier costs for the same duration, so the comparison follows the price matrix rather than
/// a list someone has to remember to re-order.
export function isUpgrade(from: Tier, to: Tier): boolean {
  return rankOf(to) > rankOf(from);
}

function rankOf(tier: Tier): number {
  return tier === 'FREE' ? 0 : (priceOf(tier, '1M') ?? 0);
}
