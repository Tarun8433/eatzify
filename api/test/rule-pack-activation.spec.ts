import { type Repository } from 'typeorm';
import { RulePacksService } from '../src/admin/rule-packs.service';
import { RulePackActivationEntity } from '../src/admin/entities/rule-pack-activation.entity';
import { AdminTotpEntity } from '../src/admin/entities/admin-totp.entity';
import { TotpService } from '../src/admin/totp.service';
import { EngineService } from '../src/modules/engine';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { RoleEnum } from '../src/roles/roles.enum';
import { newSecret, totpCode } from '../src/admin/totp';

/// docs/09 §9: `POST /admin/rule-packs/activate { version }` — super_admin only, requires
/// `reviewed_by` — and D-229's second factor in front of it.

const NOW = new Date('2026-09-18T10:00:00Z');
const SUPER_ADMIN = 1;
const ADMIN = 2;
const CLIENT = 7;

type Activation = Partial<RulePackActivationEntity>;

function engineWith(active = '1.0.0', available = ['1.0.0', '1.1.0']) {
  let current = active;
  return {
    get version() {
      return current;
    },
    get availableVersions() {
      return available;
    },
    activate(version: string) {
      if (!available.includes(version)) throw new Error('not loaded');
      current = version;
    },
  } as unknown as EngineService;
}

function serviceWith({
  rows = [],
  engine = engineWith(),
  users = [
    { id: SUPER_ADMIN, role: { id: RoleEnum.super_admin } },
    { id: ADMIN, role: { id: RoleEnum.admin } },
    { id: CLIENT, role: { id: RoleEnum.user } },
  ],
}: {
  rows?: Activation[];
  engine?: EngineService;
  users?: { id: number; role: { id: number } }[];
} = {}) {
  const activations = {
    create: (row: Activation) => row,
    save: (row: Activation) => {
      const saved = { id: `a${rows.length + 1}`, createdAt: NOW, ...row };
      rows.unshift(saved);
      return Promise.resolve(saved);
    },
    find: ({ take }: { take?: number } = {}) =>
      Promise.resolve(rows.slice(0, take ?? rows.length)),
  } as unknown as Repository<RulePackActivationEntity>;

  const userRepo = {
    findOne: ({ where }: { where: { id: number } }) =>
      Promise.resolve(users.find((u) => u.id === where.id) ?? null),
  } as unknown as Repository<UserEntity>;

  return {
    service: new RulePacksService(activations, userRepo, engine),
    rows,
    engine,
  };
}

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as { getResponse(): { error?: { code: string } } }
    ).getResponse();
    return body.error?.code ?? 'NO_CODE';
  }
  throw new Error('expected the call to be refused');
}

describe('activating a rule pack (docs/09 §9)', () => {
  it('should switch what new plans are generated against, and record both people', async () => {
    const { service, rows, engine } = serviceWith();

    const state = await service.activate({
      version: '1.1.0',
      actorUserId: SUPER_ADMIN,
      reviewedByUserId: ADMIN,
      note: 'protein floor re-checked against ICMR 2020',
    });

    expect(engine.version).toBe('1.1.0');
    expect(state.active).toBe('1.1.0');
    expect(rows[0]).toMatchObject({
      version: '1.1.0',
      activatedByUserId: SUPER_ADMIN,
      reviewedByUserId: ADMIN,
    });
  });

  /// api rule 1: constants live in the YAML packs. Activation picks one; it cannot invent one.
  it('should refuse a version that is not on this server', async () => {
    const { service, rows, engine } = serviceWith();

    expect(
      await refusedCode(
        service.activate({
          version: '9.9.9',
          actorUserId: SUPER_ADMIN,
          reviewedByUserId: ADMIN,
        }),
      ),
    ).toBe('RULE_PACK_UNKNOWN');
    expect(engine.version).toBe('1.0.0');
    expect(rows).toEqual([]);
  });

  it('should refuse to let one person do it alone', async () => {
    const { service, rows } = serviceWith();

    expect(
      await refusedCode(
        service.activate({
          version: '1.1.0',
          actorUserId: SUPER_ADMIN,
          reviewedByUserId: SUPER_ADMIN,
        }),
      ),
    ).toBe('REVIEWER_REQUIRED');
    expect(rows).toEqual([]);
  });

  it('should refuse a reviewer who is not an admin', async () => {
    const { service } = serviceWith();

    expect(
      await refusedCode(
        service.activate({
          version: '1.1.0',
          actorUserId: SUPER_ADMIN,
          reviewedByUserId: CLIENT,
        }),
      ),
    ).toBe('REVIEWER_NOT_ALLOWED');
  });

  it('should keep the history, newest first', async () => {
    const { service } = serviceWith();

    await service.activate({
      version: '1.1.0',
      actorUserId: SUPER_ADMIN,
      reviewedByUserId: ADMIN,
    });
    await service.activate({
      version: '1.0.0',
      actorUserId: SUPER_ADMIN,
      reviewedByUserId: ADMIN,
      note: 'rolled back',
    });

    const state = await service.state();
    expect(state.active).toBe('1.0.0');
    expect(state.history.map((h) => h.version)).toEqual(['1.0.0', '1.1.0']);
    expect(state.history[0].note).toBe('rolled back');
  });
});

describe('what is live after a restart', () => {
  it('should follow the database, not the environment variable', async () => {
    const { service, engine } = serviceWith({
      rows: [{ version: '1.1.0', createdAt: NOW }],
    });

    await service.onModuleInit();

    expect(engine.version).toBe('1.1.0');
  });

  /// A pack that has not been deployed to this machine must not take the API down.
  it('should keep serving the pack it has when the activated one is missing', async () => {
    const { service, engine } = serviceWith({
      rows: [{ version: '2.0.0', createdAt: NOW }],
    });

    await expect(service.onModuleInit()).resolves.toBeUndefined();
    expect(engine.version).toBe('1.0.0');
  });
});

describe('the second factor (D-229)', () => {
  function totpWith(rows: Partial<AdminTotpEntity>[] = []) {
    const totp = {
      create: (row: Partial<AdminTotpEntity>) => row,
      save: (row: Partial<AdminTotpEntity>) => {
        const at = rows.findIndex((r) => r.userId === row.userId);
        if (at >= 0) rows[at] = { ...rows[at], ...row };
        else rows.push(row);
        return Promise.resolve(row);
      },
      findOne: ({ where }: { where: { userId: number } }) =>
        Promise.resolve(rows.find((r) => r.userId === where.userId) ?? null),
    } as unknown as Repository<AdminTotpEntity>;

    return { service: new TotpService(totp), rows };
  }

  const secret = newSecret();

  it('should refuse a dangerous action when nobody has enrolled', async () => {
    const { service } = totpWith();

    expect(await refusedCode(service.require(SUPER_ADMIN, '123456', NOW))).toBe(
      'TOTP_REQUIRED',
    );
  });

  it('should refuse a dangerous action when the code is wrong', async () => {
    const { service } = totpWith([
      { userId: SUPER_ADMIN, secret, confirmedAt: NOW },
    ]);

    expect(await refusedCode(service.require(SUPER_ADMIN, '000000', NOW))).toBe(
      'TOTP_INVALID',
    );
  });

  it('should accept the code from the enrolled app', async () => {
    const { service } = totpWith([
      { userId: SUPER_ADMIN, secret, confirmedAt: NOW },
    ]);

    await expect(
      service.require(SUPER_ADMIN, totpCode(secret, NOW), NOW),
    ).resolves.toBeUndefined();
  });

  /// A code read over somebody's shoulder is good for ninety seconds. Once is enough.
  it('should refuse the same code twice', async () => {
    const { service } = totpWith([
      { userId: SUPER_ADMIN, secret, confirmedAt: NOW },
    ]);
    const code = totpCode(secret, NOW);

    await service.require(SUPER_ADMIN, code, NOW);

    expect(await refusedCode(service.require(SUPER_ADMIN, code, NOW))).toBe(
      'TOTP_REUSED',
    );
  });

  it('should hand out a secret once and take a code back to confirm it', async () => {
    const { service, rows } = totpWith();

    const enrolment = await service.enroll(SUPER_ADMIN, 'admin 1');
    expect(enrolment.otpauth_uri).toContain(enrolment.secret);
    expect(await service.status(SUPER_ADMIN)).toEqual({ enrolled: false });

    await service.confirm(SUPER_ADMIN, totpCode(enrolment.secret, NOW), NOW);

    expect(await service.status(SUPER_ADMIN)).toEqual({ enrolled: true });
    expect(rows[0].confirmedAt).toEqual(NOW);
  });

  it('should refuse to hand out a second secret once one is confirmed', async () => {
    const { service } = totpWith([
      { userId: SUPER_ADMIN, secret, confirmedAt: NOW },
    ]);

    expect(await refusedCode(service.enroll(SUPER_ADMIN, 'admin 1'))).toBe(
      'TOTP_ALREADY_ENROLLED',
    );
  });
});
