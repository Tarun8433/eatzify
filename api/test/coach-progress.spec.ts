import { NotFoundException } from '@nestjs/common';
import { CoachProgressService } from '../src/coach/coach-progress.service';
import { RoleEnum } from '../src/roles/roles.enum';
import type { GrantScope } from '../src/coach/entities/coach-grant.entity';

/**
 * docs/10 §3's `progress` scope, in full: "weight series, adherence %, steps, streaks".
 *
 * Two gates on every read, and neither alone is enough — docs/10 §1: "the level does not grant
 * access. The consent grant does. The level caps what a grant may contain."
 */

const NOW = new Date('2026-09-16T10:00:00Z');

function serviceWith({
  scopes = ['basic', 'progress'] as GrantScope[],
  role = RoleEnum.coach_l2 as RoleEnum,
  rows = [
    {
      userId: 6,
      kind: 'weight',
      value: '72.0',
      diaryDate: '2026-09-10',
      isSuspect: false,
    },
    {
      userId: 6,
      kind: 'weight',
      value: '71.4',
      diaryDate: '2026-09-14',
      isSuspect: false,
    },
    {
      userId: 6,
      kind: 'steps',
      value: '8200',
      diaryDate: '2026-09-14',
      isSuspect: false,
    },
  ],
} = {}) {
  const audited: { resource: string; subjectUserId?: number | null }[] = [];
  const diaryReads: { userId: number; date?: string }[] = [];

  const service = new CoachProgressService(
    { find: () => Promise.resolve(rows) } as never,
    { findOne: () => Promise.resolve({ id: 25, role: { id: role } }) } as never,
    { scopesFor: () => Promise.resolve(scopes) } as never,
    {
      forUsers: (ids: readonly number[]) =>
        Promise.resolve(
          new Map(
            ids.map((id) => [
              id,
              {
                avgKcal: 1740,
                avgProteinG: 96,
                targetKcal: 1859,
                targetProteinG: 125,
                adherencePct: 64,
                daysLogged: 18,
                windowDays: 28,
                streakDays: 4,
                lastLoggedDate: '2026-09-15',
                daysSinceLastLog: 1,
              },
            ]),
          ),
        ),
    } as never,
    {
      day: (userId: number, date?: string) => {
        diaryReads.push({ userId, date });
        return Promise.resolve({ diary_date: date, entries: [] });
      },
    } as never,
    {
      record: (entry: { resource: string; subjectUserId?: number | null }) => {
        audited.push(entry);
        return Promise.resolve();
      },
    } as never,
  );

  return { service, audited, diaryReads };
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

describe('what a coach may read of a client logs', () => {
  it('should return every kind the client has recorded', async () => {
    const { service } = serviceWith();

    const view = await service.progress(25, 6, NOW);

    expect(view.series.weight).toHaveLength(2);
    expect(view.series.steps).toHaveLength(1);
  });

  /// An absent kind is absent, not an empty array. An empty chart draws a flat line, which is a
  /// claim about somebody who simply never recorded it.
  it('should omit a kind the client never logged', async () => {
    const { service } = serviceWith();

    const view = await service.progress(25, 6, NOW);

    expect('water' in view.series).toBe(false);
  });

  /// The same rule the client's own Progress tab follows. A mistyped 7 kg is not a data point, and
  /// a coach acting on one would be acting on a typo.
  it('should keep a suspect reading out of the chart', async () => {
    const { service } = serviceWith({
      rows: [
        {
          userId: 6,
          kind: 'weight',
          value: '72.0',
          diaryDate: '2026-09-10',
          isSuspect: false,
        },
        {
          userId: 6,
          kind: 'weight',
          value: '7.0',
          diaryDate: '2026-09-12',
          isSuspect: true,
        },
      ],
    });

    const view = await service.progress(25, 6, NOW);

    expect(view.series.weight).toHaveLength(1);
  });

  /// Null, not zero. Somebody who has never logged has no adherence figure, and 0 % would be a
  /// verdict rather than a measurement (docs/02 FR-4.2).
  it('should carry the adherence figure and the streak', async () => {
    const { service } = serviceWith();

    const view = await service.progress(25, 6, NOW);

    expect(view.adherence_pct).toBe(64);
    expect(view.streak_days).toBe(4);
    expect(view.last_logged_date).toBe('2026-09-15');
  });
});

describe('the two gates', () => {
  /// The grant has to carry the scope. A client who shared only the basics shared no series.
  it('should refuse a client who granted only the basics', async () => {
    const { service } = serviceWith({ scopes: ['basic'] });

    expect(await notFound(service.progress(25, 6, NOW))).toBe(
      'CLIENT_NOT_FOUND',
    );
  });

  /// And the level has to reach it. docs/10 §2 puts weight history at ❌ for coach_l1, so an
  /// affiliate reads none of this however the grant was written.
  it('should refuse an affiliate even with the scope granted', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    expect(await notFound(service.progress(25, 6, NOW))).toBe(
      'CLIENT_NOT_FOUND',
    );
  });

  /// 404 rather than 403 throughout: "you lack the level" confirms the person exists and is
  /// somebody's client, which this id space must not answer.
  it('should answer not-found rather than forbidden', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    await expect(service.progress(25, 6, NOW)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('the food diary', () => {
  /// docs/10 §2: food logs are `📊 adherence %` for coach_l2 and `✅` for coach_l3. A verified
  /// coach with no coaching relationship has no purpose a meal-by-meal diary serves.
  it('should give the diary to a coaching partner', async () => {
    const { service, diaryReads } = serviceWith({ role: RoleEnum.coach_l3 });

    await service.diary(25, 6, '2026-09-15', NOW);

    expect(diaryReads).toEqual([{ userId: 6, date: '2026-09-15' }]);
  });

  /// D-204 moved this line. A nutritionist who cannot see what somebody ate cannot do the job,
  /// and a verified coach the client granted `progress` to is exactly who that job belongs to.
  it('should give the diary to a verified coach too', async () => {
    const { service, diaryReads } = serviceWith({ role: RoleEnum.coach_l2 });

    await service.diary(25, 6, '2026-09-15', NOW);

    expect(diaryReads).toHaveLength(1);
  });

  /// The consent grant still decides. An affiliate reaches nothing, and neither does a coach whose
  /// client shared only the basics.
  it('should refuse the diary without the progress grant', async () => {
    const { service, diaryReads } = serviceWith({ scopes: ['basic'] });

    expect(await notFound(service.diary(25, 6, '2026-09-15', NOW))).toBe(
      'CLIENT_NOT_FOUND',
    );
    expect(diaryReads).toEqual([]);
  });

  it('should refuse the diary to an affiliate', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    expect(await notFound(service.diary(25, 6, '2026-09-15', NOW))).toBe(
      'CLIENT_NOT_FOUND',
    );
  });

  /**
   * The bug this closed: the controller passed `date ?? ''`, and `LogsService.day` defaults with
   * `??` — which does not catch an empty string. `''` reached Postgres as a `date` and took the
   * whole request down, so the screen read "Something went wrong" on its very first load.
   */
  it('should read today when no date is given, never an empty string', async () => {
    const { service, diaryReads } = serviceWith();

    await service.diary(25, 6, undefined, NOW);

    expect(diaryReads[0]?.date).toBeUndefined();
  });

  it('should treat an empty date as today rather than passing it on', async () => {
    const { service, diaryReads } = serviceWith();

    await service.diary(25, 6, '', NOW);

    expect(diaryReads[0]?.date).toBeUndefined();
  });

  /// The average intake beside the target is what makes the diary readable — a day of 2,400 kcal
  /// means nothing until you know the plan asked for 1,859.
  it('should carry the average intake and the plan target together', async () => {
    const { service } = serviceWith();

    const view = await service.progress(25, 6, NOW);

    expect(view.avg_kcal).toBe(1740);
    expect(view.target_kcal).toBe(1859);
    expect(view.avg_protein_g).toBe(96);
    expect(view.target_protein_g).toBe(125);
  });
});

describe('the audit trail (docs/10 §6)', () => {
  /// Unlike the roster, this read IS about one person, so the row names them — the answer to "who
  /// looked at my data" has to be findable.
  it('should name the client the read was about', async () => {
    const { service, audited } = serviceWith();

    await service.progress(25, 6, NOW);

    expect(audited).toEqual([
      expect.objectContaining({
        resource: 'coach/clients/6/progress',
        subjectUserId: 6,
      }),
    ]);
  });

  it('should record nothing when the read was refused', async () => {
    const { service, audited } = serviceWith({ scopes: ['basic'] });

    await notFound(service.progress(25, 6, NOW));

    expect(audited).toEqual([]);
  });
});
