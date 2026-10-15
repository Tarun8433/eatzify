import { RoleEnum } from '../roles/roles.enum';

/// D-269. Who gets the switch between "My tracking" and "My clients" when no override says
/// otherwise: partners an admin has verified, or anyone who accepted the partner agreement.
export const DASHBOARD_SWITCH_AUDIENCES = ['verified', 'agreement'] as const;
export type DashboardSwitchAudience =
  (typeof DASHBOARD_SWITCH_AUDIENCES)[number];

export const DASHBOARD_SWITCH_AUDIENCE_KEY = 'dashboard_switch.audience';
export const DEFAULT_DASHBOARD_SWITCH_AUDIENCE: DashboardSwitchAudience =
  'verified';

const VERIFIED: ReadonlySet<number> = new Set([
  RoleEnum.coach_l2,
  RoleEnum.coach_l3,
]);
const AGREED: ReadonlySet<number> = new Set([
  RoleEnum.coach_l1,
  RoleEnum.coach_l2,
  RoleEnum.coach_l3,
]);

/// An admin's override for this person wins either way; without one, the app-wide audience decides.
export function canSwitchDashboard(
  roleId: number | null | undefined,
  audience: DashboardSwitchAudience,
  override: boolean | null,
): boolean {
  if (override !== null) return override;
  if (roleId === null || roleId === undefined) return false;
  return (audience === 'verified' ? VERIFIED : AGREED).has(roleId);
}

export function isDashboardSwitchAudience(
  value: unknown,
): value is DashboardSwitchAudience {
  return DASHBOARD_SWITCH_AUDIENCES.includes(value as DashboardSwitchAudience);
}
