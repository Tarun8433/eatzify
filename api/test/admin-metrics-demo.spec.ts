import { type Repository, type SelectQueryBuilder } from 'typeorm';
import { AdminMetricsService } from '../src/admin/admin-metrics.service';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { CoachApplicationEntity } from '../src/coach/entities/coach-application.entity';
import { CoachInviteEntity } from '../src/coach/entities/coach-invite.entity';
import { CoachGrantEntity } from '../src/coach/entities/coach-grant.entity';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { RoleEnum } from '../src/roles/roles.enum';

/// docs/08 §10 and `.claude/rules/database.md`: metrics exclude `is_demo` (D-230).
///
/// The point of this file is not the arithmetic — it is that the seeded accounts never reach the
/// numbers. A dashboard reading ₹1,24,560 against four real users is the failure doc 08 named.

const DEMO_IDS = [101, 102];

/// Records what each query was told to leave out, and answers with whatever the test seeded.
function queryFake(rows: Record<string, unknown>[], excluded: string[]) {
  const query: Record<string, unknown> = {
    select: () => query,
    addSelect: () => query,
    where: () => query,
    andWhere: (clause: string) => {
      excluded.push(clause);
      return query;
    },
    groupBy: () => query,
    clone: () => query,
    getRawMany: () => Promise.resolve(rows),
    getRawOne: () => Promise.resolve(rows[0] ?? null),
  };
  return query as unknown as SelectQueryBuilder<object>;
}

function repoFake(rows: Record<string, unknown>[], excluded: string[]) {
  return {
    createQueryBuilder: () => queryFake(rows, excluded),
    find: () => Promise.resolve(rows),
  } as unknown as Repository<object>;
}

describe('the admin overview (docs/09 §9)', () => {
  it('should leave demo accounts out of every count', async () => {
    const excluded: string[] = [];

    const users = {
      createQueryBuilder: () =>
        queryFake([{ roleId: RoleEnum.user, count: '4' }], excluded),
      // The demo lookup itself.
      find: () => Promise.resolve(DEMO_IDS.map((id) => ({ id }))),
    } as unknown as Repository<UserEntity>;

    const service = new AdminMetricsService(
      users,
      repoFake([], excluded) as Repository<CoachApplicationEntity>,
      repoFake([], excluded) as Repository<CoachInviteEntity>,
      repoFake([], excluded) as Repository<CoachGrantEntity>,
      repoFake([], excluded) as Repository<SubscriptionEntity>,
      // D-236: revenue is not under test here; the stubs only satisfy the constructor.
      {} as never,
      { list: () => Promise.resolve([]) } as never,
    );

    const overview = await service.overview();

    expect(overview.users.total).toBe(4);
    // Applications, invites, grants and subscriptions each drop the demo rows — the grant query
    // checks both ends of the relationship, so it contributes two clauses.
    expect(excluded.filter((c) => c.includes('NOT IN')).length).toBeGreaterThan(
      5,
    );
    expect(excluded).toContain('t.userId NOT IN (:...demo0)');
    expect(excluded).toContain('g.clientUserId NOT IN (:...demo0)');
    expect(excluded).toContain('g.coachUserId NOT IN (:...demo1)');
  });

  /// A production box has no demo accounts. It must not pay for the rule.
  it('should add no clause at all when nothing is demo data', async () => {
    const excluded: string[] = [];

    const users = {
      createQueryBuilder: () =>
        queryFake([{ roleId: RoleEnum.user, count: '4' }], excluded),
      find: () => Promise.resolve([]),
    } as unknown as Repository<UserEntity>;

    const service = new AdminMetricsService(
      users,
      repoFake([], excluded) as Repository<CoachApplicationEntity>,
      repoFake([], excluded) as Repository<CoachInviteEntity>,
      repoFake([], excluded) as Repository<CoachGrantEntity>,
      repoFake([], excluded) as Repository<SubscriptionEntity>,
      // D-236: revenue is not under test here; the stubs only satisfy the constructor.
      {} as never,
      { list: () => Promise.resolve([]) } as never,
    );

    await service.overview();

    expect(excluded.filter((c) => c.includes('NOT IN'))).toEqual([]);
  });
});
