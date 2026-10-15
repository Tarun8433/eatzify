import { NotFoundException } from '@nestjs/common';
import { canSwitchDashboard } from '../src/dashboard-switch/dashboard-switch';
import { DashboardSwitchService } from '../src/dashboard-switch/dashboard-switch.service';
import { RoleEnum } from '../src/roles/roles.enum';

/// D-269: who may switch between "My tracking" and "My clients".
describe('canSwitchDashboard', () => {
  it('should allow only verified partners when the audience is "verified"', () => {
    expect(canSwitchDashboard(RoleEnum.coach_l2, 'verified', null)).toBe(true);
    expect(canSwitchDashboard(RoleEnum.coach_l3, 'verified', null)).toBe(true);
    expect(canSwitchDashboard(RoleEnum.coach_l1, 'verified', null)).toBe(false);
    expect(canSwitchDashboard(RoleEnum.user, 'verified', null)).toBe(false);
  });

  it('should add agreement-only partners when the audience is "agreement"', () => {
    expect(canSwitchDashboard(RoleEnum.coach_l1, 'agreement', null)).toBe(true);
    expect(canSwitchDashboard(RoleEnum.coach_l3, 'agreement', null)).toBe(true);
    expect(canSwitchDashboard(RoleEnum.user, 'agreement', null)).toBe(false);
  });

  it("should let an admin's override win either way", () => {
    expect(canSwitchDashboard(RoleEnum.user, 'verified', true)).toBe(true);
    expect(canSwitchDashboard(RoleEnum.coach_l3, 'agreement', false)).toBe(
      false,
    );
  });

  it('should refuse an account with no role', () => {
    expect(canSwitchDashboard(null, 'agreement', null)).toBe(false);
  });
});

describe('DashboardSwitchService', () => {
  function serviceWith({
    setting = undefined as unknown,
    override = null as boolean | null,
    user = { id: 9, role: { id: RoleEnum.coach_l2 } } as Record<
      string,
      unknown
    > | null,
  } = {}) {
    const saved: unknown[] = [];
    const deleted: unknown[] = [];
    const service = new DashboardSwitchService(
      {
        findOneBy: () =>
          Promise.resolve(setting === undefined ? null : { value: setting }),
        save: (row: unknown) => {
          saved.push(row);
          return Promise.resolve(row);
        },
      } as never,
      {
        findOneBy: () =>
          Promise.resolve(override === null ? null : { allowed: override }),
        save: (row: unknown) => {
          saved.push(row);
          return Promise.resolve(row);
        },
        delete: (where: unknown) => {
          deleted.push(where);
          return Promise.resolve();
        },
      } as never,
      { findOne: () => Promise.resolve(user) } as never,
    );
    return { service, saved, deleted };
  }

  it('should default to verified partners when the setting is missing or unreadable', async () => {
    expect(await serviceWith().service.audience()).toBe('verified');
    expect(await serviceWith({ setting: 'everyone' }).service.audience()).toBe(
      'verified',
    );
    expect(await serviceWith({ setting: 'agreement' }).service.audience()).toBe(
      'agreement',
    );
  });

  it('should answer /auth/me from the audience and the override', async () => {
    const { service } = serviceWith({ setting: 'agreement' });
    expect(await service.allowedFor(9, RoleEnum.coach_l1)).toBe(true);
    expect(
      await serviceWith({ override: false }).service.allowedFor(
        9,
        RoleEnum.coach_l3,
      ),
    ).toBe(false);
  });

  it("should show the admin the person's override and what it gives them", async () => {
    expect(await serviceWith({ override: false }).service.viewFor(9)).toEqual({
      user_id: 9,
      override: false,
      audience: 'verified',
      allowed: false,
    });
  });

  it('should answer 404 for an id that is no account', async () => {
    await expect(
      serviceWith({ user: null }).service.viewFor(404),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('should remove the override when told to follow the app setting', async () => {
    const { service, saved, deleted } = serviceWith();
    await service.setOverride(9, null, 1);
    expect(deleted).toEqual([{ userId: 9 }]);
    expect(saved).toEqual([]);

    await service.setOverride(9, true, 1);
    expect(saved).toEqual([{ userId: 9, allowed: true, updatedByUserId: 1 }]);
  });
});
