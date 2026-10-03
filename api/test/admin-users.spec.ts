import { ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminUsersService, maskEmail } from '../src/admin/admin-users.service';
import { AdminStaffService } from '../src/admin/admin-staff.service';
import { PermissionsGuard, Permit } from '../src/admin/permissions.guard';
import {
  PERMISSIONS,
  STAFF_ROLES,
  can,
  permissionsFor,
} from '../src/admin/permissions';
import { RoleEnum } from '../src/roles/roles.enum';
import { StatusEnum } from '../src/statuses/statuses.enum';
import { UserAccessService } from '../src/users/user-access.service';

/// Admin panel plan, Phase A: who may do what, and what blocking a person does.

const NOW = new Date('2026-10-03T10:00:00Z');
const ADMIN = { userId: 1, roleId: RoleEnum.admin, ip: '10.0.0.1' };

describe('permission map', () => {
  it('should give every staff role the panel and nobody else', () => {
    expect([...STAFF_ROLES].sort((a, b) => a - b)).toEqual([
      RoleEnum.admin,
      RoleEnum.support,
      RoleEnum.super_admin,
      RoleEnum.finance,
      RoleEnum.content,
    ]);
    for (const role of STAFF_ROLES)
      expect(can(role, 'panel.access')).toBe(true);
    for (const role of [
      RoleEnum.user,
      RoleEnum.coach_l3,
      RoleEnum.partner_org,
    ]) {
      expect(permissionsFor(role)).toEqual([]);
    }
  });

  it('should keep staff management to the super admin', () => {
    expect(can(RoleEnum.super_admin, 'staff.manage')).toBe(true);
    for (const role of STAFF_ROLES.filter((r) => r !== RoleEnum.super_admin)) {
      expect(can(role, 'staff.manage')).toBe(false);
    }
    expect(permissionsFor(RoleEnum.super_admin)).toEqual([...PERMISSIONS]);
  });

  it.each([
    [RoleEnum.finance, 'refunds.manage', true],
    [RoleEnum.finance, 'users.reveal', false],
    [RoleEnum.finance, 'content.manage', false],
    [RoleEnum.content, 'content.manage', true],
    [RoleEnum.content, 'users.read', false],
    [RoleEnum.content, 'payments.read', false],
    [RoleEnum.support, 'users.reveal', true],
    [RoleEnum.support, 'payments.read', false],
    [RoleEnum.support, 'settings.manage', false],
  ] as const)(
    'should answer role %i / %s with %s',
    (role, permission, allowed) => {
      expect(can(role, permission)).toBe(allowed);
    },
  );
});

describe('PermissionsGuard', () => {
  class Routes {
    @Permit('payments.read')
    payments() {}
    open() {}
  }
  const guard = new PermissionsGuard(new Reflector());
  const context = (handler: () => void, roleId: number) =>
    ({
      getHandler: () => handler,
      getClass: () => Routes,
      switchToHttp: () => ({
        getRequest: () => ({ user: { role: { id: roleId } } }),
      }),
    }) as never;

  it('should let a role through when it carries the permission', () => {
    expect(
      guard.canActivate(context(Routes.prototype.payments, RoleEnum.finance)),
    ).toBe(true);
  });

  it('should refuse a role without it, with the error envelope', () => {
    expect(() =>
      guard.canActivate(context(Routes.prototype.payments, RoleEnum.content)),
    ).toThrow(ForbiddenException);
  });

  it('should refuse a route that never said what it needs', () => {
    expect(() =>
      guard.canActivate(context(Routes.prototype.open, RoleEnum.super_admin)),
    ).toThrow(ForbiddenException);
  });
});

type UserRow = {
  id: number;
  email: string | null;
  phone: string | null;
  firstName: string | null;
  lastName: string | null;
  role: { id: number; name: string };
  status: { id: number };
  createdAt: Date;
  lastLoginAt: Date | null;
  isDemo: boolean;
  provider: string;
};
type Block = {
  id: number;
  userId: number;
  reason: string;
  note: string | null;
  blockedBy: number;
  blockedAt: Date;
  until: Date | null;
  liftedAt: Date | null;
  liftedBy: number | null;
};

/// In-memory tables with only the calls these services make.
function harness() {
  const users: UserRow[] = [
    person(1, RoleEnum.admin),
    person(5, RoleEnum.user),
    person(6, RoleEnum.support),
  ];
  const blocks: Block[] = [];
  const sessionsEnded: number[] = [];
  const audits: Record<string, unknown>[] = [];
  const sent: string[] = [];

  const qb = (
    onSet: (
      set: Record<string, unknown>,
      where: Record<string, number>,
    ) => void,
  ) => {
    let set: Record<string, unknown> = {};
    let where: Record<string, number> = {};
    const b = {
      update: () => b,
      delete: () => b,
      set: (s: Record<string, unknown>) => ((set = s), b),
      where: (_sql: string, params: Record<string, number>) => (
        (where = params),
        b
      ),
      execute: () => (onSet(set, where), Promise.resolve()),
    };
    return b;
  };

  const userRepo = {
    findOne: ({ where }: { where: { id: number } }) =>
      Promise.resolve(users.find((u) => u.id === where.id) ?? null),
    update: ({ id }: { id: number }, patch: Partial<UserRow>) => {
      Object.assign(
        users.find((u) => u.id === id)!,
        patch,
      );
      return Promise.resolve();
    },
    softDelete: ({ id }: { id: number }) => {
      users.splice(
        users.findIndex((u) => u.id === id),
        1,
      );
      return Promise.resolve();
    },
    createQueryBuilder: () =>
      qb((set, where) => {
        const u = users.find((x) => x.id === where.id);
        if (!u) return;
        if (where.blocked !== undefined && u.status.id !== where.blocked)
          return;
        u.status = set.status as { id: number };
      }),
  };
  const blockRepo = {
    findOne: ({ where }: { where: { userId: number } }) =>
      Promise.resolve(
        blocks.find((b) => b.userId === where.userId && !b.liftedAt) ?? null,
      ),
    find: ({ where }: { where: { userId: number } }) =>
      Promise.resolve(blocks.filter((b) => b.userId === where.userId)),
    create: (b: Partial<Block>) => b,
    save: (b: Block) => (
      blocks.push({
        ...b,
        id: blocks.length + 1,
        liftedAt: null,
        liftedBy: null,
      }),
      Promise.resolve(b)
    ),
    update: ({ id }: { id: number }, patch: Partial<Block>) => {
      Object.assign(
        blocks.find((b) => b.id === id)!,
        patch,
      );
      return Promise.resolve();
    },
  };
  const access = new UserAccessService(blockRepo as never, userRepo as never);
  const empty = {
    find: () => Promise.resolve([]),
    findOne: () => Promise.resolve(null),
  };
  const sessionRepo = {
    ...empty,
    createQueryBuilder: () =>
      qb((_s, where) => sessionsEnded.push(where.userId)),
  };
  const services = {
    forgotPassword: (email: string) => (
      sent.push(`reset:${email}`),
      Promise.resolve()
    ),
    issue: (id: number) => (sent.push(`code:${id}`), Promise.resolve()),
  };
  const service = new AdminUsersService(
    userRepo as never,
    blockRepo as never,
    sessionRepo as never,
    empty as never,
    empty as never,
    empty as never,
    access,
    {
      record: (row: Record<string, unknown>) => (
        audits.push(row),
        Promise.resolve()
      ),
    } as never,
    { get: () => services } as never,
  );
  return { service, access, users, blocks, sessionsEnded, audits, sent };
}

function person(id: number, role: RoleEnum): UserRow {
  return {
    id,
    email: `person${id}@example.com`,
    phone: '+919800000000',
    firstName: 'Test',
    lastName: `Person${id}`,
    role: { id: role, name: String(role) },
    status: { id: StatusEnum.active },
    createdAt: NOW,
    lastLoginAt: null,
    isDemo: false,
    provider: 'email',
  };
}

describe('AdminUsersService', () => {
  it('should mask contact details in every row', async () => {
    const { service } = harness();
    const user = await service.detail(5);
    expect(user.email_masked).toBe('p…@example.com');
    expect(user.phone_masked).toBe('+919…0000');
    expect(JSON.stringify(user)).not.toContain('person5@');
    expect(maskEmail('x')).toBe('••••');
  });

  it('should reveal contact details only with an audited reason', async () => {
    const { service, audits } = harness();
    const revealed = await service.reveal(5, 'support_ticket', ADMIN);
    expect(revealed.email).toBe('person5@example.com');
    expect(audits).toEqual([
      expect.objectContaining({
        action: 'read_pii',
        subjectUserId: 5,
        reason: 'support_ticket',
        meta: { fields: ['email', 'phone'] },
      }),
    ]);
  });

  it('should block: status, sessions ended, audited with the expiry', async () => {
    const { service, users, sessionsEnded, audits } = harness();
    await service.block(
      5,
      { reason: 'spam', duration: '7d', note: 'link spam' },
      ADMIN,
      NOW,
    );

    expect(users.find((u) => u.id === 5)!.status.id).toBe(StatusEnum.blocked);
    expect(sessionsEnded).toEqual([5]);
    expect(audits[0]).toMatchObject({
      action: 'user_block',
      meta: {
        before: { state: 'active' },
        after: { state: 'blocked', until: '2026-10-10T10:00:00.000Z' },
        block_reason: 'spam',
      },
    });
  });

  it('should refuse a second block, yourself, or a staff account', async () => {
    const { service } = harness();
    await service.block(
      5,
      { reason: 'spam', duration: 'permanent' },
      ADMIN,
      NOW,
    );
    await expect(
      service.block(5, { reason: 'spam', duration: '24h' }, ADMIN, NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'ALREADY_BLOCKED' } },
    });
    await expect(
      service.block(1, { reason: 'spam', duration: '24h' }, ADMIN, NOW),
    ).rejects.toMatchObject({ response: { error: { code: 'SELF_ACTION' } } });
    await expect(
      service.block(6, { reason: 'spam', duration: '24h' }, ADMIN, NOW),
    ).rejects.toMatchObject({ response: { error: { code: 'STAFF_ACCOUNT' } } });
  });

  it('should unblock and keep the history', async () => {
    const { service, users, blocks, audits } = harness();
    await service.block(
      5,
      { reason: 'abuse', duration: 'permanent' },
      ADMIN,
      NOW,
    );
    await service.unblock(5, ADMIN, NOW);

    expect(users.find((u) => u.id === 5)!.status.id).toBe(StatusEnum.active);
    expect(blocks).toHaveLength(1);
    expect(blocks[0]).toMatchObject({ liftedBy: 1 });
    expect(audits.map((a) => a.action)).toEqual(['user_block', 'user_unblock']);
  });

  it('should record which names changed, never the names', async () => {
    const { service, audits } = harness();
    await service.update(5, { first_name: 'Renamed' }, ADMIN);
    expect(audits[0]).toMatchObject({
      action: 'user_update',
      meta: { fields: ['firstName'] },
    });
    expect(JSON.stringify(audits[0])).not.toContain('Renamed');
  });

  it('should send a reset link, and a code only to an unconfirmed account', async () => {
    const { service, users, sent } = harness();
    await service.sendPasswordReset(5, ADMIN);
    await expect(service.resendVerification(5, ADMIN)).rejects.toMatchObject({
      response: { error: { code: 'ALREADY_VERIFIED' } },
    });
    users.find((u) => u.id === 5)!.status = { id: StatusEnum.inactive };
    await service.resendVerification(5, ADMIN);
    expect(sent).toEqual(['reset:person5@example.com', 'code:5']);
  });
});

describe('UserAccessService', () => {
  it('should refuse a blocked account and lift an expired block by itself', async () => {
    const { service, access, users } = harness();
    await service.block(5, { reason: 'fraud', duration: '24h' }, ADMIN, NOW);

    await expect(access.refuseIfBlocked(5, NOW)).rejects.toMatchObject({
      response: { error: { code: 'ACCOUNT_BLOCKED' } },
    });
    const dayLater = new Date(NOW.getTime() + 86_400_001);
    await expect(access.refuseIfBlocked(5, dayLater)).resolves.toBeUndefined();
    expect(users.find((u) => u.id === 5)!.status.id).toBe(StatusEnum.active);
  });
});

describe('AdminStaffService', () => {
  it('should not let anyone change their own role', async () => {
    const service = new AdminStaffService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );
    await expect(
      service.setRole(1, RoleEnum.user, {
        userId: 1,
        roleId: RoleEnum.super_admin,
      }),
    ).rejects.toMatchObject({ response: { error: { code: 'SELF_ACTION' } } });
  });
});
