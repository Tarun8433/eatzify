import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import {
  BillingController,
  StoreAttemptDto,
} from '../src/billing/billing.controller';
import {
  MAX_ATTEMPTS_PER_HOUR,
  StoreAttemptsService,
  type StoreAttemptInput,
} from '../src/billing/store/store-attempts.service';
import { AdminPaymentsService } from '../src/admin/admin-payments.service';
import { AdminPaymentsController } from '../src/admin/admin-payments.controller';
import { RoleEnum } from '../src/roles/roles.enum';

/// D-266: every store purchase attempt the app saw end is kept for support, so a failed Play
/// attempt (which never reaches the server otherwise) shows on the admin Payments page.

const NOW = new Date('2026-10-14T10:00:00Z');

const GOOD = {
  provider: 'play',
  product_id: 'eatzify_basic',
  base_plan_id: '249basic',
  outcome: 'failed',
  reason: 'storeFailed',
  store_code: 'BillingResponse.developerError',
};

/// The same options as the global ValidationPipe (`validation-options.ts`).
const errorsFor = (body: Record<string, unknown>) =>
  validate(plainToInstance(StoreAttemptDto, body), {
    whitelist: true,
    forbidNonWhitelisted: true,
  });

function attemptsRepo(recent: number) {
  const saved: Record<string, unknown>[] = [];
  const repo = {
    count: jest.fn(() => Promise.resolve(recent)),
    create: (row: Record<string, unknown>) => row,
    save: (row: Record<string, unknown>) => {
      saved.push(row);
      return Promise.resolve(row);
    },
  };
  return { repo, saved };
}

const input = (storeCode: string | null): StoreAttemptInput => ({
  provider: 'play',
  productId: 'eatzify_basic',
  basePlanId: '249basic',
  offerId: null,
  outcome: 'failed',
  reason: 'storeFailed',
  storeCode,
});

describe('POST /billing/store/attempts body', () => {
  it('should accept a Play failure with its code when the body is well formed', async () => {
    expect(await errorsFor(GOOD)).toHaveLength(0);
  });

  it.each([
    ['provider', { provider: 'cashfree' }],
    ['outcome', { outcome: 'charged' }],
    ['reason', { reason: 'BillingResponse.developerError' }],
  ])('should refuse the body when %s is not one of ours', async (_f, bad) => {
    expect(await errorsFor({ ...GOOD, ...bad })).not.toHaveLength(0);
  });

  it('should refuse the body when it names a user id', async () => {
    expect(await errorsFor({ ...GOOD, user_id: 99 })).not.toHaveLength(0);
  });

  it('should refuse the body when the product id is missing', async () => {
    const { product_id: _drop, ...rest } = GOOD;
    void _drop;
    expect(await errorsFor(rest)).not.toHaveLength(0);
  });
});

describe('StoreAttemptsService.record', () => {
  it('should keep the store code when it is shaped like a Play code', async () => {
    const { repo, saved } = attemptsRepo(0);
    const service = new StoreAttemptsService(repo as never);

    await service.record(7, input('BillingResponse.developerError'), NOW);

    expect(saved[0]).toMatchObject({
      userId: 7,
      storeCode: 'BillingResponse.developerError',
    });
  });

  it.each([
    ['spaces', 'Play said no to asha@example.com'],
    ['too long', 'x'.repeat(81)],
    ['empty', ''],
  ])('should store a null code when the code has %s', async (_w, code) => {
    const { repo, saved } = attemptsRepo(0);
    const service = new StoreAttemptsService(repo as never);

    await service.record(7, input(code), NOW);

    expect(saved).toHaveLength(1);
    expect(saved[0].storeCode).toBeNull();
  });

  it('should store nothing when the user already sent the hourly limit', async () => {
    const { repo, saved } = attemptsRepo(MAX_ATTEMPTS_PER_HOUR);
    const service = new StoreAttemptsService(repo as never);

    expect(await service.record(7, input(null), NOW)).toBe(false);
    expect(saved).toHaveLength(0);
  });

  it('should still store when the user is one under the hourly limit', async () => {
    const { repo, saved } = attemptsRepo(MAX_ATTEMPTS_PER_HOUR - 1);
    const service = new StoreAttemptsService(repo as never);

    expect(await service.record(7, input(null), NOW)).toBe(true);
    expect(saved).toHaveLength(1);
    // The window is the caller's own last hour.
    const where = (repo.count.mock.calls[0] as unknown[])[0] as {
      where: { userId: number; createdAt: { value: Date } };
    };
    expect(where.where.userId).toBe(7);
    expect(where.where.createdAt.value).toEqual(
      new Date(NOW.getTime() - 3_600_000),
    );
  });
});

describe('BillingController.storeAttempt', () => {
  it('should record the attempt for the signed-in user when the body is valid', async () => {
    const recorded: [number, StoreAttemptInput][] = [];
    const controller = new BillingController(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {
        record: (userId: number, i: StoreAttemptInput) => {
          recorded.push([userId, i]);
          return Promise.resolve(true);
        },
      } as never,
    );

    await controller.storeAttempt(
      { user: { id: 42 } } as never,
      plainToInstance(StoreAttemptDto, GOOD),
    );

    expect(recorded).toEqual([
      [
        42,
        {
          provider: 'play',
          productId: 'eatzify_basic',
          basePlanId: '249basic',
          offerId: null,
          outcome: 'failed',
          reason: 'storeFailed',
          storeCode: 'BillingResponse.developerError',
        },
      ],
    ]);
  });
});

/// A query builder that answers with [result] whatever it is asked, and records its joins.
function builder(result: unknown, joins: string[] = []) {
  const q: Record<string, unknown> = {};
  for (const m of [
    'select',
    'addSelect',
    'where',
    'andWhere',
    'groupBy',
    'orderBy',
    'limit',
    'take',
  ]) {
    q[m] = () => q;
  }
  q.innerJoin = (_e: unknown, _a: string, on: string) => {
    joins.push(on);
    return q;
  };
  q.getMany = () => Promise.resolve(result);
  q.getRawMany = () => Promise.resolve(Array.isArray(result) ? result : []);
  q.getRawOne = () => Promise.resolve(Array.isArray(result) ? null : result);
  q.getCount = () => Promise.resolve(0);
  return q;
}

const ATTEMPTS = [
  {
    id: 'a1',
    userId: 5,
    provider: 'play',
    productId: 'eatzify_basic',
    basePlanId: '249basic',
    offerId: null,
    outcome: 'failed',
    reason: 'storeFailed',
    storeCode: 'BillingResponse.developerError',
    createdAt: new Date('2026-10-14T09:00:00Z'),
  },
  {
    id: 'a2',
    userId: 5,
    provider: 'app_store',
    productId: 'eatzify.pro.monthly',
    basePlanId: null,
    offerId: null,
    outcome: 'cancelled',
    reason: null,
    storeCode: null,
    createdAt: new Date('2026-10-14T08:00:00Z'),
  },
];

function adminService(attempts: unknown, joins: string[] = []) {
  const users = {
    find: () =>
      Promise.resolve([
        {
          id: 5,
          firstName: 'Test',
          lastName: 'User',
          email: 'test.user@example.com',
          phone: '+910000000000',
        },
      ]),
  };
  return new AdminPaymentsService(
    { createQueryBuilder: () => builder([]) } as never,
    users as never,
    { count: () => Promise.resolve(0) } as never,
    { createQueryBuilder: () => builder([]) } as never,
    {} as never,
    {} as never,
    { createQueryBuilder: () => builder(attempts, joins) } as never,
  );
}

describe('GET /admin/payments/store-attempts', () => {
  it('should label the plan from Play ids when they map, else show the ids', async () => {
    const page = await adminService(ATTEMPTS).storeAttempts({});

    expect(page.rows.map((r) => r.plan)).toEqual([
      'BASIC 1M',
      'eatzify.pro.monthly',
    ]);
    expect(page.rows[0]).toMatchObject({
      id: 'a1',
      user_id: 5,
      user_name: 'Test User',
      provider: 'play',
      outcome: 'failed',
      reason: 'storeFailed',
      store_code: 'BillingResponse.developerError',
      created_at: '2026-10-14T09:00:00.000Z',
    });
    expect(page.next_cursor).toBeNull();
  });

  it('should hand back a cursor when there is another page', async () => {
    const page = await adminService(ATTEMPTS).storeAttempts({ limit: 1 });

    expect(page.rows).toHaveLength(1);
    expect(page.next_cursor).toBe('2026-10-14T09:00:00.000Z');
  });

  it.each([
    ['finance', RoleEnum.finance, false],
    ['support', RoleEnum.support, true],
  ])(
    'should give the full contact only to a role allowed it when the role is %s',
    async (_name, role, full) => {
      const controller = new AdminPaymentsController(
        adminService(ATTEMPTS),
        {} as never,
        {} as never,
        {} as never,
        {} as never,
      );

      const page = await controller.storeAttempts({}, {
        user: { role: { id: role } },
      } as never);

      const row = page.rows[0];
      expect(row.email_masked).not.toBeNull();
      expect(row.phone_masked).not.toBeNull();
      if (full) {
        expect(row.email).toBe('test.user@example.com');
        expect(row.phone).toBe('+910000000000');
      } else {
        expect(row).not.toHaveProperty('email');
        expect(row).not.toHaveProperty('phone');
      }
    },
  );
});

describe('payments summary store attempts', () => {
  it("should count today's attempts and failures without demo users", async () => {
    const joins: string[] = [];
    const summary = await adminService(
      { total: '5', failed: '2' },
      joins,
    ).summary(NOW);

    expect(summary.store_attempts_today).toEqual({ total: 5, failed: 2 });
    expect(joins.some((j) => j.includes('"isDemo" = false'))).toBe(true);
  });

  it('should answer zero when there were no attempts today', async () => {
    const summary = await adminService(null).summary(NOW);

    expect(summary.store_attempts_today).toEqual({ total: 0, failed: 0 });
  });
});
