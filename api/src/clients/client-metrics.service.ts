import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { diaryDateFor } from '../plans/diary-date';

/// docs/12 §9: "clients at risk (no log ≥3 days)". The number that decides the at-risk list, and
/// the only threshold in this file.
export const AT_RISK_AFTER_DAYS = 3;

/// The window adherence is measured over. Four weeks: long enough that one bad week does not read
/// as a collapse, short enough that a month-old improvement is not still propping the figure up.
export const ADHERENCE_WINDOW_DAYS = 28;

/**
 * How a client is doing, for the people allowed to ask.
 *
 * `null` where the answer is unknown, never `0` — a client who has never logged has no adherence
 * figure, and printing 0 % would be a judgement rather than a measurement.
 */
export type ClientMetrics = {
  /**
   * What they actually ate against what the plan asked for, averaged over the days they logged.
   *
   * **This, not [adherencePct], is what a nutritionist reads.** Logging frequency says somebody
   * opened the app; this says whether the food matched the plan. A person can log a pizza every
   * day and score 100 % on the first number.
   *
   * Null when there is no plan, or nothing logged. Averaged over LOGGED days rather than all
   * days — otherwise a missed day drags the average down and reads as under-eating.
   */
  avgKcal: number | null;
  avgProteinG: number | null;
  targetKcal: number | null;
  targetProteinG: number | null;
  /// Days with at least one food log in the window, over the window length. docs/02 FR-4.2: "a
  /// count not a shame badge".
  adherencePct: number | null;
  daysLogged: number;
  windowDays: number;
  /// Consecutive diary days ending today. Zero means the run is broken, which is a fact; the UI
  /// decides whether a zero is worth showing.
  streakDays: number;
  /// The last diary date carrying a log, or null for a client who has never logged.
  lastLoggedDate: string | null;
  /// Whole days between [lastLoggedDate] and today. Null when they have never logged, which is a
  /// different state from "logged a long time ago" and must not collapse into a large number.
  daysSinceLastLog: number | null;
};

/// The diary dates of the last [days] days, today first.
function recentDiaryDates(now: Date, days: number): string[] {
  const out: string[] = [];

  for (let back = 0; back < days; back += 1) {
    const instant = new Date(now);
    instant.setUTCDate(instant.getUTCDate() - back);
    out.push(diaryDateFor(instant));
  }

  return out;
}

/**
 * Adherence, streak and last-logged, for many clients in one query.
 *
 * **Extracted from the admin dashboard, where it was written first.** Two copies of "how well is
 * this person doing" would eventually disagree, and the coach-facing copy is the one a coach makes
 * decisions from. One implementation, two callers.
 *
 * Two things were fixed in the move:
 *
 * - The window now uses `diaryDateFor()`, the 04:00 IST boundary (`api/CLAUDE.md` rule 4). The
 *   admin version bucketed by calendar UTC, so a 1 a.m. log counted against the wrong day and
 *   every streak crossing midnight IST was understated.
 * - One query for a whole roster instead of one per row. A coach with forty clients was forty
 *   round trips, and the roster is the screen that opens first.
 */
@Injectable()
export class ClientMetricsService {
  constructor(
    @InjectRepository(FoodLogEntity)
    private readonly logs: Repository<FoodLogEntity>,
  ) {}

  /**
   * Metrics for every id given, in one pass.
   *
   * Ids with no logs are present in the result with a null adherence rather than missing from it —
   * a caller iterating its roster must not have to guess whether an absent key means "no logs" or
   * "not asked for".
   */
  async forUsers(
    userIds: readonly number[],
    now: Date,
  ): Promise<Map<number, ClientMetrics>> {
    const out = new Map<number, ClientMetrics>();
    for (const id of userIds) out.set(id, empty());

    if (userIds.length === 0) return out;

    const window = recentDiaryDates(now, ADHERENCE_WINDOW_DAYS);
    const oldest = window[window.length - 1];

    // One row per (user, day) rather than per log: a client who logged six meals on Tuesday logged
    // on ONE day, and adherence counts days.
    const rows = await this.logs
      .createQueryBuilder('log')
      .select('log.userId', 'userId')
      .addSelect('log.diaryDate', 'diaryDate')
      .where('log.userId IN (:...userIds)', { userIds: [...userIds] })
      .andWhere('log.diaryDate >= :oldest', { oldest })
      .groupBy('log.userId')
      .addGroupBy('log.diaryDate')
      .getRawMany<{ userId: number; diaryDate: string }>();

    const daysByUser = new Map<number, Set<string>>();
    for (const row of rows) {
      const id = Number(row.userId);
      const days = daysByUser.get(id) ?? new Set<string>();
      days.add(row.diaryDate);
      daysByUser.set(id, days);
    }

    // The last log can predate the window, so it is asked for separately rather than inferred from
    // a set that starts 28 days ago. "Never logged" and "last logged in March" are different
    // answers and the roster shows them differently.
    const lastByUser = await this.lastLoggedFor(userIds);
    const nutrition = await this.nutritionFor(userIds, oldest ?? '');

    for (const id of userIds) {
      const days = daysByUser.get(id) ?? new Set<string>();
      const lastLoggedDate = lastByUser.get(id) ?? null;

      out.set(id, {
        ...(nutrition.get(id) ?? noNutrition()),
        adherencePct:
          days.size === 0
            ? null
            : Math.round((days.size / ADHERENCE_WINDOW_DAYS) * 100),
        daysLogged: days.size,
        windowDays: ADHERENCE_WINDOW_DAYS,
        streakDays: streakFrom(days, window),
        lastLoggedDate,
        daysSinceLastLog: daysSince(lastLoggedDate, window[0] ?? null),
      });
    }

    return out;
  }

  /// docs/12 §9's at-risk rule, applied to metrics already fetched. A client who has NEVER logged
  /// is at risk too — the coach needs to know about the person who signed up and never started
  /// just as much as the one who stopped.
  static isAtRisk(metrics: ClientMetrics): boolean {
    const since = metrics.daysSinceLastLog;
    return since === null || since >= AT_RISK_AFTER_DAYS;
  }

  /**
   * Average intake against the plan, per client, in two queries.
   *
   * Averaged over days that HAVE a log: a day with nothing logged is a day with no information,
   * not a day of zero calories, and folding it in would make every irregular logger look like they
   * are starving.
   */
  private async nutritionFor(
    userIds: readonly number[],
    oldest: string,
  ): Promise<Map<number, Nutrition>> {
    const [eaten, plans] = await Promise.all([
      this.logs
        .createQueryBuilder('log')
        .select('log.userId', 'userId')
        .addSelect('log.diaryDate', 'diaryDate')
        .addSelect('SUM(log.kcal)', 'kcal')
        .addSelect('SUM(log.proteinG)', 'proteinG')
        .where('log.userId IN (:...userIds)', { userIds: [...userIds] })
        .andWhere('log.diaryDate >= :oldest', { oldest })
        .groupBy('log.userId')
        .addGroupBy('log.diaryDate')
        .getRawMany<{
          userId: number;
          diaryDate: string;
          kcal: string;
          proteinG: string;
        }>(),
      this.logs.manager.query<
        { userId: number; targets: Record<string, number> | null }[]
      >(
        `SELECT DISTINCT ON ("userId") "userId", "targets"
         FROM "plan" WHERE "userId" = ANY($1::int[])
         ORDER BY "userId", "planDate" DESC`,
        [[...userIds]],
      ),
    ]);

    const targetOf = new Map(plans.map((p) => [Number(p.userId), p.targets]));
    const totals = new Map<
      number,
      { days: number; kcal: number; protein: number }
    >();

    for (const row of eaten) {
      const id = Number(row.userId);
      const held = totals.get(id) ?? { days: 0, kcal: 0, protein: 0 };
      held.days += 1;
      held.kcal += Number(row.kcal);
      held.protein += Number(row.proteinG);
      totals.set(id, held);
    }

    const out = new Map<number, Nutrition>();

    for (const id of userIds) {
      const eatenBy = totals.get(id);
      const targets = targetOf.get(id) ?? null;

      out.set(id, {
        avgKcal: eatenBy ? Math.round(eatenBy.kcal / eatenBy.days) : null,
        avgProteinG: eatenBy
          ? Math.round(eatenBy.protein / eatenBy.days)
          : null,
        // A plan with no targets fired a blocking gate (docs/04 §2), so there is nothing to
        // compare against and nothing is shown rather than a comparison against zero.
        targetKcal: targets?.kcal ?? null,
        targetProteinG: targets?.protein_g ?? null,
      });
    }

    return out;
  }

  private async lastLoggedFor(
    userIds: readonly number[],
  ): Promise<Map<number, string>> {
    const rows = await this.logs
      .createQueryBuilder('log')
      .select('log.userId', 'userId')
      .addSelect('MAX(log.diaryDate)', 'lastDate')
      .where('log.userId IN (:...userIds)', { userIds: [...userIds] })
      .groupBy('log.userId')
      .getRawMany<{ userId: number; lastDate: string }>();

    return new Map(rows.map((r) => [Number(r.userId), r.lastDate]));
  }
}

type Nutrition = Pick<
  ClientMetrics,
  'avgKcal' | 'avgProteinG' | 'targetKcal' | 'targetProteinG'
>;

function noNutrition(): Nutrition {
  return {
    avgKcal: null,
    avgProteinG: null,
    targetKcal: null,
    targetProteinG: null,
  };
}

function empty(): ClientMetrics {
  return {
    ...noNutrition(),
    adherencePct: null,
    daysLogged: 0,
    windowDays: ADHERENCE_WINDOW_DAYS,
    streakDays: 0,
    lastLoggedDate: null,
    daysSinceLastLog: null,
  };
}

/**
 * Consecutive diary days, breaking at the first gap — a run with a hole in it is two runs.
 *
 * **Today does not have to be logged yet.** At nine in the morning nobody has eaten a recorded
 * meal, so counting from today would show every client a zero until lunch and then restore the
 * number. docs/05 §6 forbids framing that implies failure, and a streak that collapses every
 * morning is exactly that. So the run is allowed to end yesterday: it is intact until a whole day
 * passes unlogged, which is what a person means when they say they have kept it up.
 */
function streakFrom(logged: Set<string>, window: readonly string[]): number {
  const start = logged.has(window[0] ?? '') ? 0 : 1;
  let streak = 0;

  for (const date of window.slice(start)) {
    if (!logged.has(date)) break;
    streak += 1;
  }

  return streak;
}

/// Whole diary days between two dates. Both are plain `YYYY-MM-DD` already resolved through
/// `diaryDateFor`, so this is calendar subtraction on values that already carry the 04:00 rule —
/// not a second place where the boundary is decided.
function daysSince(last: string | null, today: string | null): number | null {
  if (last === null || today === null) return null;

  const from = Date.parse(`${last}T00:00:00Z`);
  const to = Date.parse(`${today}T00:00:00Z`);
  if (Number.isNaN(from) || Number.isNaN(to)) return null;

  return Math.max(0, Math.round((to - from) / 86_400_000));
}
