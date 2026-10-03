/// Which sidebar destination needs which API permission (`api/src/admin/permissions.ts`, D-260).
/// The API enforces every one of these; hiding what a role cannot open just spares it a page of
/// "not allowed".
export const NAV_PERMISSION = {
  dashboard: 'panel.access',
  users: 'users.read',
  verification: 'users.read',
  partners: 'verification.manage',
  people: 'users.read',
  search: 'users.read',
  tickets: 'users.read',
  foods: 'content.manage',
  broadcast: 'notify.send',
  metrics: 'payments.read',
  audit: 'audit.read',
  staff: 'staff.manage',
  rulepacks: 'settings.manage',
  scanning: 'settings.manage',
  security: 'panel.access',
} as const;

export type NavKey = keyof typeof NAV_PERMISSION;

export function allowedNav(permissions: readonly string[]): NavKey[] {
  return (Object.keys(NAV_PERMISSION) as NavKey[]).filter((key) =>
    permissions.includes(NAV_PERMISSION[key]),
  );
}

/// The first screen a role lands on.
export function homeFor(permissions: readonly string[]): NavKey {
  return allowedNav(permissions)[0] ?? 'security';
}
