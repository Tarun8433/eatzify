/// D-269: who may switch between "My tracking" and "My clients" in the app.

export type DashboardSwitchAudience = 'verified' | 'agreement';

export const AUDIENCE_LABEL: Record<DashboardSwitchAudience, string> = {
  verified: 'Verified partners only',
  agreement: 'Anyone who accepted the partner agreement',
};

/// One person's override: null follows the app-wide setting.
export type OverrideChoice = 'follow' | 'allow' | 'deny';

export interface UserDashboardSwitch {
  user_id: number;
  override: boolean | null;
  audience: DashboardSwitchAudience;
  allowed: boolean;
}

export const CHOICE_LABEL: Record<OverrideChoice, string> = {
  follow: 'Follow app setting',
  allow: 'Always allow',
  deny: 'Never allow',
};

export function choiceOf(override: boolean | null): OverrideChoice {
  if (override === null) return 'follow';
  return override ? 'allow' : 'deny';
}

/// What the person gets, and why, in one line.
export function switchSummary(view: UserDashboardSwitch): string {
  const gets = view.allowed ? 'Can switch dashboards' : 'Cannot switch dashboards';
  if (view.override !== null) return `${gets} — set for this person.`;
  return `${gets} — follows the app setting (${AUDIENCE_LABEL[view.audience].toLowerCase()}).`;
}
