import { NotFoundException } from '@nestjs/common';
import { CoachClientsService } from '../src/coach/coach-clients.service';
import type { GrantScope } from '../src/coach/entities/coach-grant.entity';
import { RoleEnum } from '../src/roles/roles.enum';
import type { ClientMetrics } from '../src/clients/client-metrics.service';

/**
 * The coach's roster, as a whole. The per-field rules live in `client-view.spec.ts` against the
 * serialiser; what is tested here is everything around it — how many queries, how many audit rows,
 * and whether a count can disagree with the list under it.
 */

const NOW = new Date('2026-09-15T00:00:00Z');
const FAR = new Date('2027-01-01T00:00:00Z');

const METRICS: ClientMetrics = {
  avgKcal: 1740,
  avgProteinG: 96,
  targetKcal: 1859,
  targetProteinG: 125,
  adherencePct: 64,
  daysLogged: 18,
  windowDays: 28,
  streakDays: 4,
  lastLoggedDate: '2026-09-14',
  daysSinceLastLog: 1,
};

const ALLOWED_BY_ROLE: Partial<Record<RoleEnum, GrantScope[]>> = {
  [RoleEnum.coach_l1]: [],
  [RoleEnum.coach_l2]: ['basic', 'progress', 'plan_view'],
  [RoleEnum.coach_l3]: [
    'basic',
    'progress',
    'plan_view',
    'plan_edit',
    'chat',
    'health_conditions',
  ],
};

function serviceWith({
  clients = [
    { id: 9, scopes: ['basic', 'progress'] as GrantScope[], daysSince: 1 },
  ],
  role = RoleEnum.coach_l2 as RoleEnum,
  expiresAt = FAR,
  auditedRecently = false,
}: {
  clients?: { id: number; scopes: GrantScope[]; daysSince: number | null }[];
  role?: RoleEnum;
  expiresAt?: Date;
  auditedRecently?: boolean;
} = {}) {
  const audited: { resource: string; meta?: Record<string, unknown> }[] = [];
  const queries: string[] = [];

  const grantRows = clients.map((c) => ({
    coachUserId: 2,
    clientUserId: c.id,
    scopes: c.scopes,
    status: 'active',
    expiresAt,
  }));

  const manager = {
    query: (sql: string) => {
      queries.push(sql);
      if (sql.includes('audit_log')) {
        return Promise.resolve(auditedRecently ? [{ one: 1 }] : []);
      }
      // The pending-invite count.
      return Promise.resolve([{ count: '2' }]);
    },
  };

  const service = new CoachClientsService(
    {
      find: () => Promise.resolve(grantRows),
      findOne: () => Promise.resolve(grantRows[0] ?? null),
      manager,
    } as never,
    {
      find: () =>
        Promise.resolve(
          clients.map((c) => ({
            userId: c.id,
            name: `Client ${c.id}`,
            ageYears: 34,
            heightCm: 165,
            weightKg: '72.0',
            sexAtBirth: 'female',
            goal: 'fat_loss',
          })),
        ),
      findOne: () => Promise.resolve(null),
    } as never,
    {
      find: () =>
        Promise.resolve(
          clients.map((c) => ({
            id: c.id,
            firstName: 'Ritu',
            lastName: `Number${c.id}`,
          })),
        ),
      findOne: () => Promise.resolve({ id: 2, role: { id: role } }),
    } as never,
    {
      find: () =>
        Promise.resolve(
          clients.map((c) => ({
            userId: c.id,
            tier: 'PRO',
            status: 'active',
            currentPeriodEnd: new Date('2026-10-01T00:00:00Z'),
          })),
        ),
    } as never,
    { find: () => Promise.resolve([]) } as never,
    {
      scopesFor: (_coach: number, clientId: number, now: Date) => {
        const row = grantRows.find((g) => g.clientUserId === clientId);
        if (!row || row.expiresAt <= now) return Promise.resolve([]);
        const allowed = ALLOWED_BY_ROLE[role] ?? [];
        return Promise.resolve(row.scopes.filter((s) => allowed.includes(s)));
      },
    } as never,
    {
      forUsers: (ids: readonly number[]) =>
        Promise.resolve(
          new Map(
            ids.map((id) => [
              id,
              {
                ...METRICS,
                daysSinceLastLog:
                  clients.find((c) => c.id === id)?.daysSince ?? null,
              },
            ]),
          ),
        ),
    } as never,
    {
      record: (entry: { resource: string; meta?: Record<string, unknown> }) => {
        audited.push(entry);
        return Promise.resolve();
      },
    } as never,
  );

  return { service, audited, queries };
}

async function notFound(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (e as NotFoundException).getResponse() as {
      error: { code: string };
    };
    return body.error.code;
  }
  throw new Error('expected the read to be refused');
}

describe('the roster', () => {
  it('should list the clients whose grant is still live', async () => {
    const { service } = serviceWith();

    const rows = await service.roster(2, NOW);

    expect(rows).toHaveLength(1);
    expect(rows[0]?.client_user_id).toBe(9);
  });

  /// Expiry binds on READ, before any sweep has run.
  it('should drop a lapsed grant even before the sweep', async () => {
    const { service } = serviceWith({
      expiresAt: new Date('2026-09-01T00:00:00Z'),
    });

    expect(await service.roster(2, NOW)).toEqual([]);
  });

  /// An affiliate reaches no scope at all, so their roster is empty whatever grants exist.
  it('should leave an affiliate with an empty roster', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    expect(await service.roster(2, NOW)).toEqual([]);
  });
});

describe('the audit trail (docs/10 §6)', () => {
  /// One row for the whole read. Forty clients used to mean forty rows every time the screen
  /// opened, and a trail where every entry is noise is one nobody can search.
  it('should write exactly one row however many clients there are', async () => {
    const { service, audited } = serviceWith({
      clients: [1, 2, 3, 4, 5].map((id) => ({
        id,
        scopes: ['basic', 'progress'] as GrantScope[],
        daysSince: 1,
      })),
    });

    await service.roster(2, NOW);

    expect(audited).toHaveLength(1);
    expect(audited[0]?.meta?.client_count).toBe(5);
  });

  /// `subjectUserId` is null on a roster read, so the ids have to be findable another way — docs/13
  /// gives a person the right to ask who looked at their data.
  it('should keep the client ids findable in the row', async () => {
    const { service, audited } = serviceWith();

    await service.roster(2, NOW);

    expect(audited[0]?.meta?.client_user_ids).toEqual([9]);
  });

  /// A read that carried a name and a goal is not a health read.
  it('should write nothing for a roster with no health field', async () => {
    const { service, audited } = serviceWith({
      clients: [{ id: 9, scopes: ['basic'], daysSince: 1 }],
    });

    await service.roster(2, NOW);

    expect(audited).toEqual([]);
  });

  /// A dashboard that polls would otherwise write a row per poll.
  it('should collapse a second read inside the window', async () => {
    const { service, audited } = serviceWith({ auditedRecently: true });

    await service.roster(2, NOW);

    expect(audited).toEqual([]);
  });
});

describe('the dashboard', () => {
  /// A tile and the list under it are built from the same rows, so they cannot disagree.
  it('should count what the at-risk list contains', async () => {
    const { service } = serviceWith({
      clients: [
        { id: 1, scopes: ['basic', 'progress'], daysSince: 0 },
        { id: 2, scopes: ['basic', 'progress'], daysSince: 4 },
        { id: 3, scopes: ['basic', 'progress'], daysSince: null },
      ],
    });

    const view = await service.dashboard(2, NOW);

    expect(view.total_clients).toBe(3);
    expect(view.active_clients).toBe(1);
    expect(view.at_risk_clients).toBe(2);
    expect(view.needs_attention).toHaveLength(2);
  });

  /// docs/12 §9 calls the at-risk list the most valuable widget a coach gets. Longest gap first —
  /// and never sorted by weight lost or streak, which docs/05 §6 bans as ranking people.
  it('should put the longest absence at the top', async () => {
    const { service } = serviceWith({
      clients: [
        { id: 1, scopes: ['basic', 'progress'], daysSince: 4 },
        { id: 2, scopes: ['basic', 'progress'], daysSince: 12 },
      ],
    });

    const view = await service.dashboard(2, NOW);

    expect(view.needs_attention.map((r) => r.client_user_id)).toEqual([2, 1]);
  });
});

describe('opening one client', () => {
  it('should refuse a client this coach has no grant for', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    expect(await notFound(service.client(2, 9, NOW))).toBe('CLIENT_NOT_FOUND');
  });

  it('should audit the read against the person it was about', async () => {
    const { service, audited } = serviceWith();

    await service.client(2, 9, NOW);

    expect(audited[0]?.resource).toBe('coach/clients/9');
  });
});
