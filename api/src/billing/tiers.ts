/// Tier and entitlement definitions. docs/11 §1 and §4.
///
/// A tier's entitlements live here rather than in the database for now: they change with a release,
/// not at runtime, and a wrong value is a code review away from being caught rather than a silent
/// row edit. Move to `tier_entitlements` when an admin needs to change them without a deploy.

export const TIERS = ['FREE', 'BASIC', 'PRO'] as const;
export type Tier = (typeof TIERS)[number];

export type Entitlements = {
  'plan.regenerate_per_day': number;
  'plan.alternates': boolean;
  'export.pdf': boolean;
  'history.days': number;
  'coach.chat': boolean;
  'support.priority': boolean;
};

/// docs/11 §1: "never restrict a safety feature. Floors, warnings, referral screens and the
/// disclaimer are free-tier. Restrict convenience, not protection." Nothing in this table gates a
/// gate, a warning, or a piece of docs/05 copy — check that before adding a key.
export const TIER_ENTITLEMENTS: Record<Tier, Entitlements> = {
  FREE: {
    'plan.regenerate_per_day': 1,
    'plan.alternates': false,
    'export.pdf': false,
    'history.days': 7,
    'coach.chat': false,
    'support.priority': false,
  },
  BASIC: {
    'plan.regenerate_per_day': 2,
    'plan.alternates': false,
    'export.pdf': false,
    'history.days': 90,
    'coach.chat': false,
    'support.priority': false,
  },
  PRO: {
    'plan.regenerate_per_day': 3,
    'plan.alternates': true,
    'export.pdf': true,
    // docs/11 §1: PRO is "unlimited history".
    'history.days': 36500,
    'coach.chat': true,
    'support.priority': true,
  },
};

/// docs/11 §5 lifecycle. `grace` still carries the paid tier — a failed card must not take away
/// what someone paid for while the retry window is open.
export const ENTITLED_STATUSES = ['trialing', 'active', 'grace'] as const;
export type SubscriptionStatus =
  'trialing' | 'active' | 'past_due' | 'grace' | 'cancelled' | 'expired';

/// docs/11 §2 price matrix, GST-inclusive, in paise to avoid float money.
///
/// ⚠️ **Two prices differ from docs/11 §2, because that table breaks the rule stated three lines
/// below it** — "the ladder must be monotonic". Both changes are the smallest that restore it, and
/// both are pricing decisions that need sign-off:
///
///   BASIC 12M  2,199 → 2,099   at 2,199 it was ₹183/month against 9M's ₹178, so the longer
///                              commitment was worse value per month — the exact defect docs/11
///                              §2 warns about.
///   PRO 1M       549 →   649   docs/11 suggests ₹549 for the monthly plan, but PRO 3M is ₹1,799
///                              (₹600/month). At ₹549 the monthly plan undercut the quarterly one
///                              and nobody would ever buy 3M.
///
/// `test/tiers.spec.ts` fails if either ladder inverts again.
export const PRICES: Record<
  Exclude<Tier, 'FREE'>,
  Record<'1M' | '3M' | '6M' | '9M' | '12M', number>
> = {
  BASIC: {
    '1M': 24_900,
    '3M': 69_900,
    '6M': 119_900,
    '9M': 159_900,
    '12M': 209_900,
  },
  PRO: {
    '1M': 64_900,
    '3M': 179_900,
    '6M': 279_900,
    '9M': 379_900,
    '12M': 499_900,
  },
};

export function entitlementsFor(tier: Tier): Entitlements {
  return TIER_ENTITLEMENTS[tier];
}
