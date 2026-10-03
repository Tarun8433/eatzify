import { describe, expect, it } from 'vitest';
import { allowedNav, homeFor } from '../lib/nav';

/// The sidebar follows the API's permissions (D-260). These are the lists `GET /admin/me` returns.
const CONTENT = ['panel.access', 'content.manage', 'notify.send'];
const FINANCE = ['panel.access', 'users.read', 'payments.read', 'refunds.manage', 'payouts.manage', 'reports.read'];

describe('allowedNav', () => {
  it('shows a content editor only foods, messages, the dashboard and security', () => {
    expect(allowedNav(CONTENT).sort()).toEqual(['broadcast', 'dashboard', 'foods', 'security']);
  });

  it('shows finance the revenue screen but not staff, settings or the audit log', () => {
    const nav = allowedNav(FINANCE);
    expect(nav).toContain('metrics');
    expect(nav).toContain('users');
    for (const hidden of ['staff', 'scanning', 'rulepacks', 'audit', 'foods'] as const) {
      expect(nav).not.toContain(hidden);
    }
  });

  it('shows nothing but security to a list with no panel access', () => {
    expect(allowedNav([])).toEqual([]);
    expect(homeFor([])).toBe('security');
  });

  it('opens on the dashboard for any staff role', () => {
    expect(homeFor(CONTENT)).toBe('dashboard');
    expect(homeFor(FINANCE)).toBe('dashboard');
  });
});
