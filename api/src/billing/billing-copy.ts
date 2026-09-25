/// User-facing copy for checkout.
///
/// CLAUDE.md rule 7: `user_message` is the only string the app renders. Payment messages say what
/// happened and what to do next, and never name a gateway error or an internal id — a person who
/// has just failed to pay needs an instruction, not a diagnosis.

export const UNKNOWN_PRICE =
  'That plan is not available. Please pick one from the list and try again.';

export const PHONE_REQUIRED =
  'We need a mobile number on your account before you can pay. Sign in with your number to add one.';

export const CHECKOUT_UNAVAILABLE =
  'Payments are temporarily unavailable. Nothing has been charged — please try again shortly.';

/// A second purchase on top of a live plan. Upgrading has its own path (docs/11 §7), so this is
/// only ever reached by buying the same or a cheaper tier while one is running.
export const ALREADY_SUBSCRIBED =
  'You already have an active plan. To move to a bigger plan, use Upgrade — you will only pay the difference.';

/// docs/11 §6: one trial per number, for life.
export const TRIAL_ALREADY_USED =
  'Your free trial has already been used. You can pick a plan whenever you are ready.';

export const TRIAL_NEEDS_PLAN = 'Please choose the plan you would like to try.';

/// docs/11 §7: "downgrades take effect at period end, never immediately (no refunds)".
export const NOT_AN_UPGRADE =
  'That plan is not bigger than your current one. It will start when your current plan ends.';

/// Nothing to change, cancel or upgrade.
export const NO_ACTIVE_PLAN = 'You do not have an active plan right now.';

/// docs/11 §9: seven days, and only for what we billed ourselves.
export const REFUND_WINDOW_CLOSED =
  'This payment is past the 7-day refund window. Please contact support if something went wrong.';

export const REFUND_NOT_AVAILABLE =
  'We could not find a payment to refund. Please contact support.';

/// Shown when a stub build is asked to take real money. Never reachable in production, where the
/// mode is refused at boot.
export const STUB_MODE =
  'This build cannot take payments. Nothing has been charged.';

/// D-236. One message for every way a code can fail — which check failed is not checkout copy.
export const COUPON_INVALID =
  "That offer code isn't valid, has expired, or has been fully used.";
