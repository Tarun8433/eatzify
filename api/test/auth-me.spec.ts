import { MeService } from '../src/auth/me.service';

/// docs/09 §3: `GET /auth/me → { user, roles, entitlements, active_plan_summary }`.
///
/// The boilerplate's `/auth/me` returned the bare user row, so the app had no single call that
/// answered "who is this, what may they use, and do they already have a plan" — it needed three
/// round trips on every cold start, and the entitlements one gates every premium surface.
function serviceWith({
  user = { id: 7, role: { id: 2, name: 'user' } } as Record<
    string,
    unknown
  > | null,
  plan = null as Record<string, unknown> | null,
} = {}) {
  return new MeService(
    { findById: () => Promise.resolve(user) } as never,
    {
      entitlements: () =>
        Promise.resolve({
          tier: 'PRO',
          status: 'active',
          current_period_end: '2026-12-01T00:00:00.000Z',
          entitlements: { 'export.pdf': true },
        }),
    } as never,
    { latest: () => Promise.resolve(plan) } as never,
  );
}

const PLAN = {
  plan: {
    id: 'plan-1',
    valid_from: '2026-09-01',
    targets: { kcal: 1859 },
    meal_targets: [{ slot: 'breakfast' }],
    meals: [{ name: 'poha' }],
  },
  rule_pack_version: '1.0.0',
  warnings: [],
  trace_available: true,
};

describe('GET /auth/me', () => {
  it('should answer the four keys docs/09 §3 names when the user exists', async () => {
    const view = await serviceWith({ plan: PLAN }).of(7);

    expect(Object.keys(view).sort()).toEqual([
      'active_plan_summary',
      'entitlements',
      'roles',
      'user',
    ]);
  });

  it('should carry the tier and entitlements when billing resolved them', async () => {
    const view = await serviceWith().of(7);

    expect(view.entitlements.tier).toBe('PRO');
    expect(view.entitlements.entitlements['export.pdf']).toBe(true);
  });

  /// The spec says `roles`, plural, and the row carries one. An array is the shape a caller can
  /// keep working against when a user gains a second role; a bare string would have to change.
  it('should name the role as a list when the row carries one', async () => {
    const view = await serviceWith().of(7);

    expect(view.roles).toEqual(['user']);
  });

  /// A SUMMARY. The full plan is `GET /plans/current`, and it carries every meal and every item —
  /// sending it from the call that runs on every cold start would make the app pay for a whole
  /// day's food to learn whether a plan exists.
  it('should summarise the active plan without its meals when a plan exists', async () => {
    const view = await serviceWith({ plan: PLAN }).of(7);

    expect(view.active_plan_summary).toEqual({
      id: 'plan-1',
      valid_from: '2026-09-01',
      targets: { kcal: 1859 },
      rule_pack_version: '1.0.0',
    });
  });

  it('should report null when no plan exists', async () => {
    const view = await serviceWith({ plan: null }).of(7);

    expect(view.active_plan_summary).toBeNull();
  });

  /// A JWT outlives the row it names: a deleted account still presents a valid token until it
  /// expires. 404 is the honest answer, not an aggregate built around a missing user.
  it('should refuse when the token names a user who no longer exists', async () => {
    await expect(serviceWith({ user: null }).of(7)).rejects.toThrow();
  });
});
