/**
 * docs/10 §1. The eight roles the access matrix is written against.
 *
 * **A role does not grant access to a client — the consent grant does** (docs/10 §1). The role
 * only CAPS what a grant may contain: a `coach_l3` without a grant sees nothing at all. Anything
 * that reads this enum to decide whether a coach may see a person is reading the wrong thing.
 *
 * 1 and 2 are the boilerplate's own ids and keep their values; a user row already points at them.
 */
export enum RoleEnum {
  admin = 1,
  user = 2,

  /// Referrer with a commercial contract and no coaching relationship. Sees a masked name and
  /// aggregates, never a phone, never a condition.
  coach_l1 = 3,

  /// Verified coach, guidance only. Deliberately does NOT reach medical conditions: a verified
  /// coach with no coaching relationship has no purpose for a diabetes diagnosis (docs/10 §2).
  coach_l2 = 4,

  /// Active coaching relationship. The only role a `health_conditions` grant may be given to.
  coach_l3 = 5,

  /// Gym owner who onboards coaches. Aggregate only, never client-level (docs/10 §5.6).
  partner_org = 6,

  /// Support staff. Access is ticket-scoped, time-boxed to 72 h and audited — never standing.
  support = 7,

  /// Everything, audited, TOTP 2FA mandatory, no shared accounts (docs/10 §4).
  super_admin = 8,
}

/// The roles that may hold a consent grant over a client. `coach_l1` is a referrer, so it is
/// absent: there is no coaching relationship for a grant to attach to.
export const COACH_ROLES = [RoleEnum.coach_l2, RoleEnum.coach_l3] as const;
