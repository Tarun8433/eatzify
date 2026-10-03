import { RoleEnum } from '../roles/roles.enum';

/// Admin panel plan, Phase A: what each staff role may do. One table, read by `PermissionsGuard`
/// on every admin route and sent to the dashboard (`GET /admin/me`) so the sidebar shows only
/// what the person can open. The server is what enforces it; the sidebar only follows.
export const PERMISSIONS = [
  /// Signing in to the dashboard at all. Every staff role has it.
  'panel.access',
  /// Lists, profiles (masked), support tickets, client diaries (each read still audited).
  'users.read',
  /// Block, unblock, edit, password reset, resend verification.
  'users.manage',
  /// See a full phone number or email — audited, with a reason (docs/13 §4).
  'users.reveal',
  /// Coach applications and partner KYC review.
  'verification.manage',
  'payments.read',
  'refunds.manage',
  /// Partner commission payouts and their reconciliation.
  'payouts.manage',
  'notify.send',
  /// Offers, announcements, foods, exercises.
  'content.manage',
  'reports.read',
  /// Staff roles. Super admin only.
  'staff.manage',
  /// Scan policy, rule packs, prices, TDS rates.
  'settings.manage',
  'audit.read',
] as const;

export type Permission = (typeof PERMISSIONS)[number];

const ALL: readonly Permission[] = PERMISSIONS;

/// docs/10 §4 and the admin plan's five roles. Absent from this map means no admin access at all.
export const ROLE_PERMISSIONS: Partial<
  Record<RoleEnum, readonly Permission[]>
> = {
  [RoleEnum.super_admin]: ALL,
  // Everything a super admin has except changing who is staff.
  [RoleEnum.admin]: ALL.filter((p) => p !== 'staff.manage'),
  [RoleEnum.support]: [
    'panel.access',
    'users.read',
    'users.manage',
    'users.reveal',
    'notify.send',
    'audit.read',
  ],
  [RoleEnum.finance]: [
    'panel.access',
    'users.read',
    'payments.read',
    'refunds.manage',
    'payouts.manage',
    'reports.read',
  ],
  [RoleEnum.content]: ['panel.access', 'content.manage', 'notify.send'],
};

/// The roles that may sign in to the dashboard.
export const STAFF_ROLES = Object.keys(ROLE_PERMISSIONS).map(
  Number,
) as RoleEnum[];

export function permissionsFor(
  roleId: number | string | undefined,
): Permission[] {
  return [...(ROLE_PERMISSIONS[Number(roleId) as RoleEnum] ?? [])];
}

export function can(
  roleId: number | string | undefined,
  permission: Permission,
): boolean {
  return permissionsFor(roleId).includes(permission);
}
