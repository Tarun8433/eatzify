import { COACH_ROLES, RoleEnum } from '../src/roles/roles.enum';

/// docs/10 §1. A role id is a foreign key on `user`, so these numbers are data, not labels — and
/// the boilerplate shipped with two of them already pointing at live rows.

describe('RoleEnum', () => {
  /// `user.roleId` references these. Renumbering 1 or 2 would silently re-role every account that
  /// already exists, which is the worst kind of migration: it type-checks.
  it('should keep the boilerplate ids when new roles are added', () => {
    expect(RoleEnum.admin).toBe(1);
    expect(RoleEnum.user).toBe(2);
  });

  it('should give every docs/10 §1 role a distinct id', () => {
    const ids = Object.values(RoleEnum).filter(
      (v): v is number => typeof v === 'number',
    );

    expect(ids).toHaveLength(8);
    expect(new Set(ids).size).toBe(8);
  });

  /// docs/10 §1: "the level does not grant access. The consent grant does." `coach_l1` is a
  /// referrer with a commercial contract and no coaching relationship, so there is nothing for a
  /// grant to attach to — listing it here would let a referrer be handed a client's conditions.
  it('should exclude the referrer from the roles a grant may attach to', () => {
    expect(COACH_ROLES).not.toContain(RoleEnum.coach_l1);
    expect(COACH_ROLES).toContain(RoleEnum.coach_l2);
    expect(COACH_ROLES).toContain(RoleEnum.coach_l3);
  });

  /// docs/10 §5.3 and the §2 matrix: only a coach_l3 with an active grant reaches conditions.
  it('should not treat a verified coach as a coaching relationship', () => {
    expect(COACH_ROLES).toHaveLength(2);
    expect(RoleEnum.coach_l2).not.toBe(RoleEnum.coach_l3);
  });
});
