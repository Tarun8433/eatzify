import { Injectable } from '@nestjs/common';
import { diaryDateFor } from '../plans/diary-date';
import type { ExerciseEntity } from './entities/exercise.entity';
import type { GymWorkoutEntity } from './entities/gym-workout.entity';
import { GYM_COPY, gymInvalid } from './gym-copy';
import { bestsOf, sessionsByExercise } from './gym-history';
import {
  GymLibraryService,
  type ExerciseDetailView,
  type ExerciseView,
} from './gym-library.service';
import { GymPlanService, type DaySource } from './gym-plan.service';
import {
  addDays,
  effortSummary,
  heatmap,
  isHard,
  mondayOf,
  muscleLevels,
  rirOf,
  type EffortSummary,
  type HeatCell,
  type MuscleLevel,
} from './gym-stats';
import type { RoutineExercise, WorkoutSet } from './gym-types';
import { GymWorkoutsService } from './gym-workouts.service';
import { musclesOf, type BodyMuscle } from './muscles';
import {
  DEFAULT_MINUTES,
  DEFAULT_REPS,
  DEFAULT_SPEED_KMH,
} from './progression';
import { planEntry, type SessionEntry } from './session-plan';
import { bestOneRm, isoWeekStart, streakWeeks } from './workout-records';

export const MUSCLE_WINDOWS = ['week', '30d', '90d', 'all'] as const;
export const EFFORT_WINDOWS = ['30d', '90d', '1y', 'all'] as const;
type MuscleWindow = (typeof MUSCLE_WINDOWS)[number];
type EffortWindow = (typeof EFFORT_WINDOWS)[number];
const WINDOW_DAYS: Record<string, number> = { '30d': 30, '90d': 90, '1y': 365 };

const DEFAULT_SETS = 3;
const ENERGY_DAYS = 30;
const RECENT = 6;
const TOP_MUSCLES = 4;
const LAST_SESSIONS = 5;
const CALENDAR_WEEKS = 6;

export type ExerciseDetailResponse = {
  exercise: ExerciseDetailView;
  best_weight_kg: number | null;
  best_e1rm: {
    value_kg: number;
    weight_kg: number;
    reps: number;
    date: string;
  } | null;
  last: { date: string; sets: WorkoutSet[] } | null;
  /// What adding it to a workout right now would start with.
  plan_entry: SessionEntry;
  routine_ids: number[];
};

export type ProgressPoint = {
  date: string;
  workout_id: string;
  top: number;
  e1rm: number | null;
  effort: number | null;
};

@Injectable()
export class GymStatsService {
  constructor(
    private readonly library: GymLibraryService,
    private readonly workouts: GymWorkoutsService,
    private readonly plan: GymPlanService,
  ) {}

  public async exerciseDetail(
    userId: number,
    id: string,
  ): Promise<ExerciseDetailResponse> {
    const [exercise, logged, profile, routines] = await Promise.all([
      this.library.visible(userId, id),
      this.workouts.logged(userId),
      this.workouts.profileOf(userId),
      this.plan.routineRows(userId),
    ]);
    const sessions = sessionsByExercise(logged).get(id) ?? [];
    const working = profile.workingWeights[id];
    const bests = bestsOf(sessions, working);
    const e1rm = this.bestE1rm(sessions);
    return {
      exercise: this.library.toDetailView(exercise),
      best_weight_kg: bests?.weightKg || null,
      best_e1rm: e1rm,
      last: sessions[0]
        ? { date: sessions[0].date, sets: sessions[0].sets }
        : null,
      plan_entry: planEntry({
        cfg: defaultConfig(exercise),
        routineRule: null,
        exercise: {
          name: exercise.name,
          bodyPart: exercise.bodyPart,
          isBodyweight: exercise.isBodyweight,
          mediaUrl: this.library.mediaUrlFor(exercise),
          muscles: musclesOf(exercise),
          steps: exercise.steps,
        },
        history: sessions,
        workingWeightKg: working?.weight_kg ?? 0,
        bestWeightKg: bests?.weightKg || null,
      }),
      routine_ids: routines
        .filter((r) => r.exercises.some((e) => e.exercise_id === id))
        .map((r) => r.id),
    };
  }

  public async exerciseProgress(userId: number, id: string) {
    const [exercise, logged, profile] = await Promise.all([
      this.library.visible(userId, id),
      this.workouts.logged(userId),
      this.workouts.profileOf(userId),
    ]);
    const mode = exercise.bodyPart === 'cardio' ? 'cardio' : null;
    const points: ProgressPoint[] = [];
    const sessions: { date: string; sets: WorkoutSet[] }[] = [];
    for (const w of [...logged].reverse()) {
      const entry = w.entries.find(
        (e) => e.exercise_id === id && e.sets.some((s) => s.done),
      );
      if (!entry) continue;
      const done = entry.sets.filter((s) => s.done);
      const top =
        entry.mode === 'cardio'
          ? Math.max(...done.map((s) => s.speed_kmh ?? 0))
          : entry.mode === 'time'
            ? Math.max(...done.map((s) => s.seconds ?? 0))
            : Math.max(
                entry.top_weight_kg ?? 0,
                ...done.map((s) => s.weight_kg ?? 0),
              );
      const rated = done.map(rirOf).filter((r): r is number => r !== null);
      points.push({
        date: w.diaryDate,
        workout_id: w.id,
        top,
        e1rm: entry.mode === 'reps' ? (bestOneRm(done)?.value ?? null) : null,
        effort:
          rated.length > 0
            ? Math.round(
                (rated.reduce((a, b) => a + b, 0) / rated.length) * 10,
              ) / 10
            : null,
      });
      sessions.unshift({ date: w.diaryDate, sets: entry.sets });
    }
    const lastMode = logged
      .find((w) => w.entries.some((e) => e.exercise_id === id))
      ?.entries.find((e) => e.exercise_id === id)?.mode;
    const best = points.reduce<ProgressPoint | null>(
      (b, p) => (b === null || p.top > b.top ? p : b),
      null,
    );
    const history = sessionsByExercise(logged).get(id) ?? [];
    return {
      exercise: this.library.toView(exercise),
      mode: mode ?? lastMode ?? 'reps',
      effort_scale: profile.effortScale,
      points,
      sessions: sessions.slice(0, LAST_SESSIONS),
      best: best ? { value: best.top, date: best.date } : null,
      best_e1rm: this.bestE1rm(history),
    };
  }

  public async stats(
    userId: number,
    query: { muscle_window?: string; effort_window?: string; hard?: string },
    now = new Date(),
  ) {
    const muscleWindow = (MUSCLE_WINDOWS as readonly string[]).includes(
      query.muscle_window ?? '',
    )
      ? (query.muscle_window as MuscleWindow)
      : 'week';
    const effortWindow = (EFFORT_WINDOWS as readonly string[]).includes(
      query.effort_window ?? '',
    )
      ? (query.effort_window as EffortWindow)
      : '90d';
    const hard = query.hard === 'true';
    const today = diaryDateFor(now);
    const [logged, profile] = await Promise.all([
      this.workouts.logged(userId),
      this.workouts.profileOf(userId),
    ]);
    const exercises = await this.library.byIds(
      userId,
      logged.flatMap((w) => w.entries.map((e) => e.exercise_id)),
    );

    const inMuscleWindow = logged.filter((w) =>
      muscleWindow === 'week'
        ? isoWeekStart(w.diaryDate) === mondayOf(today)
        : muscleWindow === 'all' ||
          w.diaryDate >= addDays(today, -WINDOW_DAYS[muscleWindow] + 1),
    );
    const levels = this.levelsOf(inMuscleWindow, exercises, hard);
    const anyHard = inMuscleWindow.some((w) =>
      w.entries.some((e) => e.sets.some((s) => s.done && isHard(s))),
    );

    const inEffortWindow = logged.filter(
      (w) =>
        effortWindow === 'all' ||
        w.diaryDate >= addDays(today, -WINDOW_DAYS[effortWindow] + 1),
    );
    const everRated = logged.some((w) =>
      w.entries.some((e) => e.sets.some((s) => rirOf(s) !== null)),
    );

    return {
      tiles: {
        total_workouts: logged.length,
        this_month: logged.filter(
          (w) => w.diaryDate.slice(0, 7) === today.slice(0, 7),
        ).length,
        streak_weeks: streakWeeks(
          logged.map((w) => w.diaryDate),
          today,
        ),
        week_kcal: this.kcalOf(
          logged.filter((w) => isoWeekStart(w.diaryDate) === mondayOf(today)),
        ),
      },
      heatmap: this.heatmapOf(logged, today),
      muscles: {
        window: muscleWindow,
        hard,
        has_hard_sets: anyHard,
        workouts: inMuscleWindow.length,
        levels,
        untrained:
          inMuscleWindow.length > 0
            ? levels.filter((l) => l.level === 0).map((l) => l.muscle)
            : [],
        top: levels
          .filter((l) => l.sets > 0)
          .sort((a, b) => b.sets - a.sets)
          .slice(0, TOP_MUSCLES)
          .map((l) => ({ muscle: l.muscle, sets: l.sets })),
      },
      effort: everRated
        ? {
            window: effortWindow,
            ...effortSummary(
              inEffortWindow.flatMap((w) =>
                w.entries
                  .filter((e) => e.mode === 'reps')
                  .flatMap((e) =>
                    e.sets.map((set) => ({ date: w.diaryDate, set })),
                  ),
              ),
              profile.effortScale === 'rpe' ? 'rpe' : 'rir',
            ),
          }
        : null,
      energy: this.energyDays(logged, today),
      recent: logged.slice(0, RECENT).map((w) => this.workouts.toSummary(w)),
      exercises: [
        ...new Map(
          logged.flatMap((w) =>
            w.entries.map((e) => [
              e.exercise_id,
              exercises.get(e.exercise_id)?.name ?? e.name,
            ]),
          ),
        ).entries(),
      ]
        .map(([id, name]) => ({ id, name }))
        .sort((a, b) => a.name.localeCompare(b.name)),
    };
  }

  public async calendar(userId: number, month: string, now = new Date()) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))
      throw gymInvalid(GYM_COPY.badMonth);
    const today = diaryDateFor(now);
    const [logged, profile, routines] = await Promise.all([
      this.workouts.logged(userId),
      this.workouts.profileOf(userId),
      this.plan.routineRows(userId),
    ]);
    const routineIds = new Set(routines.map((r) => r.id));
    const start = mondayOf(`${month}-01`);
    const inMonth = logged.filter((w) => w.diaryDate.slice(0, 7) === month);
    const weeks = Array.from({ length: CALENDAR_WEEKS }, (_, w) =>
      Array.from({ length: 7 }, (_, d) => {
        const date = addDays(start, w * 7 + d);
        const planned = this.plan.routineFor(date, profile, routineIds);
        return {
          date,
          in_month: date.slice(0, 7) === month,
          is_today: date === today,
          routine_id: planned.routine_id,
          source: planned.source as DaySource,
          workouts: logged
            .filter((x) => x.diaryDate === date)
            .map((x) => ({
              id: x.id,
              name: x.name,
              energy_kcal: x.energyKcal,
            })),
        };
      }),
    );
    return {
      month,
      weeks,
      summary: {
        workouts: inMonth.length,
        minutes: Math.round(
          inMonth.reduce((m, w) => m + w.durationSec, 0) / 60,
        ),
        volume_kg: Math.round(
          inMonth.reduce((v, w) => v + Number(w.volumeKg), 0),
        ),
        kcal: this.kcalOf(inMonth),
      },
    };
  }

  /// One diary day per entry for the last 30, oldest first — null where nothing was estimated.
  public energyDays(logged: GymWorkoutEntity[], today: string) {
    const days = Array.from({ length: ENERGY_DAYS }, (_, i) =>
      addDays(today, i - ENERGY_DAYS + 1),
    );
    return {
      days: days.map((date) => ({
        date,
        kcal: this.kcalOf(logged.filter((w) => w.diaryDate === date)),
      })),
    };
  }

  private kcalOf(rows: GymWorkoutEntity[]): number | null {
    return rows.some((w) => w.energyKcal !== null)
      ? rows.reduce((sum, w) => sum + (w.energyKcal ?? 0), 0)
      : null;
  }

  private heatmapOf(logged: GymWorkoutEntity[], today: string): HeatCell[][] {
    const days = new Map<string, { minutes: number; workouts: number }>();
    for (const w of logged) {
      const d = days.get(w.diaryDate) ?? { minutes: 0, workouts: 0 };
      days.set(w.diaryDate, {
        minutes: d.minutes + w.durationSec / 60,
        workouts: d.workouts + 1,
      });
    }
    return heatmap(days, today);
  }

  private levelsOf(
    rows: GymWorkoutEntity[],
    exercises: Map<string, ExerciseEntity>,
    hard: boolean,
  ): MuscleLevel[] {
    return muscleLevels(
      rows.flatMap((w) =>
        w.entries.map((e) => {
          const ex = exercises.get(e.exercise_id);
          return { muscles: ex ? musclesOf(ex) : [], sets: e.sets };
        }),
      ),
      hard,
    );
  }

  private bestE1rm(
    sessions: { date: string; mode: string; sets: WorkoutSet[] }[],
  ) {
    let best: {
      value_kg: number;
      weight_kg: number;
      reps: number;
      date: string;
    } | null = null;
    for (const s of sessions) {
      if (s.mode !== 'reps') continue;
      const e = bestOneRm(s.sets);
      if (e && (best === null || e.value > best.value_kg)) {
        best = {
          value_kg: e.value,
          weight_kg: e.weight_kg,
          reps: e.reps,
          date: s.date,
        };
      }
    }
    return best;
  }
}

/// What an exercise starts as when it is added without a routine.
export function defaultConfig(
  e: ExerciseEntity | ExerciseView,
): RoutineExercise {
  const id = 'id' in e ? e.id : '';
  const cardio =
    ('bodyPart' in e ? e.bodyPart : (e as ExerciseView).body_part) === 'cardio';
  return cardio
    ? {
        exercise_id: id,
        mode: 'cardio',
        sets: 1,
        minutes: DEFAULT_MINUTES,
        speed_kmh: DEFAULT_SPEED_KMH,
      }
    : {
        exercise_id: id,
        mode: 'reps',
        sets: DEFAULT_SETS,
        reps: DEFAULT_REPS,
        weight_kg: 0,
      };
}

export type { BodyMuscle, EffortSummary };
