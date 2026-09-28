import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { diaryDateFor } from '../plans/diary-date';
import type { ExerciseEntity } from './entities/exercise.entity';
import { GymProfileEntity } from './entities/gym-profile.entity';
import { GymRoutineEntity } from './entities/gym-routine.entity';
import type { GymWorkoutEntity } from './entities/gym-workout.entity';
import type { RoutineDto } from './dto/routine.dto';
import type { DayOverrideDto, GymSettingsDto } from './dto/schedule.dto';
import { GYM_COPY, gymInvalid, gymNotFound } from './gym-copy';
import { bestsOf, sessionsByExercise } from './gym-history';
import { addDays, mondayOf } from './gym-stats';
import type { RoutineExercise, RoutineRule } from './gym-types';
import { GymLibraryService } from './gym-library.service';
import { musclesOf } from './muscles';
import {
  GymWorkoutsService,
  type WorkoutSummaryView,
} from './gym-workouts.service';
import { cleanSupersets, normaliseExercise } from './routine-rules';
import { planEntry, type SessionEntry } from './session-plan';
import { STARTER_PLAN } from './starter-plan';
import { isoWeekStart, streakWeeks } from './workout-records';

export type RoutineExerciseView = RoutineExercise & {
  name: string;
  body_part: string;
  equipment: string;
  is_bodyweight: boolean;
  is_cardio: boolean;
};

export type RoutineView = {
  id: number;
  name: string;
  icon: string;
  progression: string;
  exercises: RoutineExerciseView[];
};

export type GymSettingsView = {
  rest_sec: number;
  effort_scale: string;
  keep_awake: boolean;
  sound: boolean;
  body_figure: string;
};

/// Where a day's routine came from. 'rescheduled' and 'rest_override' are a one-off change the
/// person made; the weekly plan is untouched.
export type DaySource = 'weekly' | 'rescheduled' | 'rest_override' | 'none';

export type PlannedDay = {
  diary_date: string;
  weekday: number;
  routine_id: number | null;
  source: DaySource;
  workouts: number;
  is_today: boolean;
};

export type GymOverview = {
  settings: GymSettingsView;
  week: Record<string, number>;
  routines: RoutineView[];
  today: PlannedDay;
  week_days: PlannedDay[];
  /// Routine id → the session as it would start now: prefilled and progressed, so a workout can
  /// begin with no signal.
  session_plans: Record<string, SessionEntry[]>;
  totals: {
    today_kcal: number | null;
    week_kcal: number | null;
    streak_weeks: number;
    this_week_workouts: number;
    planned_per_week: number;
    total_workouts: number;
  };
  recent: WorkoutSummaryView[];
};

const WEEKDAYS = ['1', '2', '3', '4', '5', '6', '7'];
/// How far either side of today a one-off change may be made — the calendar's reach.
const OVERRIDE_REACH_DAYS = 400;
const RECENT_WORKOUTS = 5;

/// ISO weekday of a diary date: 1 Monday … 7 Sunday.
export const isoWeekday = (date: string) =>
  new Date(`${date}T00:00:00.000Z`).getUTCDay() || 7;

@Injectable()
export class GymPlanService {
  constructor(
    @InjectRepository(GymRoutineEntity)
    private readonly routines: Repository<GymRoutineEntity>,
    @InjectRepository(GymProfileEntity)
    private readonly profiles: Repository<GymProfileEntity>,
    private readonly library: GymLibraryService,
    private readonly workouts: GymWorkoutsService,
  ) {}

  public async overview(
    userId: number,
    now = new Date(),
  ): Promise<GymOverview> {
    const [profile, routines, logged] = await Promise.all([
      this.workouts.profileOf(userId),
      this.routineRows(userId),
      this.workouts.logged(userId),
    ]);
    const exercises = await this.exercisesOf(userId, routines);
    const today = diaryDateFor(now);
    const monday = mondayOf(today);
    const countOn = (date: string) =>
      logged.filter((w) => w.diaryDate === date).length;
    const weekDays = WEEKDAYS.map((_, i) =>
      this.dayOf(addDays(monday, i), profile, routines, countOn, today),
    );
    const sumKcal = (rows: GymWorkoutEntity[]) =>
      rows.some((w) => w.energyKcal !== null)
        ? rows.reduce((sum, w) => sum + (w.energyKcal ?? 0), 0)
        : null;
    const thisWeek = logged.filter((w) => isoWeekStart(w.diaryDate) === monday);

    return {
      settings: this.settingsView(profile),
      week: profile.week,
      routines: routines.map((r) => this.routineView(r, exercises)),
      today: this.dayOf(today, profile, routines, countOn, today),
      week_days: weekDays,
      session_plans: this.sessionPlans(routines, exercises, logged, profile),
      totals: {
        today_kcal: sumKcal(logged.filter((w) => w.diaryDate === today)),
        week_kcal: sumKcal(thisWeek),
        streak_weeks: streakWeeks(
          logged.map((w) => w.diaryDate),
          today,
        ),
        this_week_workouts: thisWeek.length,
        planned_per_week: Object.keys(profile.week).length,
        total_workouts: logged.length,
      },
      recent: logged
        .slice(0, RECENT_WORKOUTS)
        .map((w) => this.workouts.toSummary(w)),
    };
  }

  public async createRoutine(
    userId: number,
    dto: RoutineDto,
  ): Promise<RoutineView> {
    const exercises = await this.checkedExercises(userId, dto.exercises);
    const last = await this.routines.findOne({
      where: { userId },
      order: { position: 'DESC' },
    });
    const row = await this.routines.save(
      this.routines.create({
        userId,
        name: dto.name.trim(),
        icon: dto.icon ?? 'strength',
        progression: dto.progression ?? 'linear',
        exercises: cleanSupersets(
          dto.exercises.map((e) => normaliseExercise({ ...e })),
        ),
        position: (last?.position ?? -1) + 1,
      }),
    );
    return this.routineView(row, exercises);
  }

  public async updateRoutine(
    userId: number,
    id: number,
    dto: RoutineDto,
  ): Promise<RoutineView> {
    const row = await this.ownedRoutine(userId, id);
    const exercises = await this.checkedExercises(userId, dto.exercises);
    row.name = dto.name.trim();
    row.icon = dto.icon ?? row.icon;
    row.progression = dto.progression ?? row.progression;
    row.exercises = cleanSupersets(
      dto.exercises.map((e) => normaliseExercise({ ...e })),
    );
    return this.routineView(await this.routines.save(row), exercises);
  }

  /// Also clears it from the weekly plan and from any one-off day — a schedule never points at nothing.
  public async deleteRoutine(userId: number, id: number): Promise<void> {
    const row = await this.ownedRoutine(userId, id);
    const profile = await this.workouts.profileOf(userId);
    profile.week = Object.fromEntries(
      Object.entries(profile.week).filter(([, r]) => r !== id),
    );
    profile.dayOverrides = Object.fromEntries(
      Object.entries(profile.dayOverrides).filter(([, r]) => r !== id),
    );
    await this.profiles.save(profile);
    await this.routines.delete({ id: row.id });
  }

  /// Push Monday, Pull Wednesday, Legs Friday — only on days the person has not planned already.
  public async loadStarter(userId: number): Promise<GymOverview> {
    const profile = await this.workouts.profileOf(userId);
    const week = { ...profile.week };
    for (const plan of STARTER_PLAN) {
      const routine = await this.createRoutine(userId, {
        name: plan.name,
        icon: plan.icon,
        progression: 'linear',
        exercises: plan.exercises,
      });
      if (week[plan.weekday] === undefined) week[plan.weekday] = routine.id;
    }
    await this.profiles.update({ userId }, { week });
    return this.overview(userId);
  }

  public async setSchedule(
    userId: number,
    week: Record<string, number | null>,
  ): Promise<GymOverview> {
    const owned = new Set((await this.routineRows(userId)).map((r) => r.id));
    const next: Record<string, number> = {};
    for (const [day, routineId] of Object.entries(week)) {
      if (!WEEKDAYS.includes(day)) throw gymInvalid(GYM_COPY.badSchedule);
      if (routineId === null) continue;
      if (!Number.isInteger(routineId) || !owned.has(routineId))
        throw gymInvalid(GYM_COPY.badSchedule);
      next[day] = routineId;
    }
    await this.workouts.profileOf(userId);
    await this.profiles.update({ userId }, { week: next });
    return this.overview(userId);
  }

  public async setDay(
    userId: number,
    dto: DayOverrideDto,
    now = new Date(),
  ): Promise<GymOverview> {
    const today = diaryDateFor(now);
    const date = dto.date;
    const reach = (d: string) =>
      Math.abs(Date.parse(d) - Date.parse(today)) / 86_400_000;
    if (Number.isNaN(Date.parse(date)) || reach(date) > OVERRIDE_REACH_DAYS) {
      throw gymInvalid(GYM_COPY.badDate);
    }
    if (dto.routine_id != null) await this.ownedRoutine(userId, dto.routine_id);

    const profile = await this.workouts.profileOf(userId);
    // This day's old choice goes, and so do one-off changes too old to plan against.
    const kept = Object.fromEntries(
      Object.entries(profile.dayOverrides).filter(
        ([d]) => d !== date && reach(d) <= OVERRIDE_REACH_DAYS,
      ),
    );
    if (dto.rest) kept[date] = 'rest';
    else if (dto.routine_id != null) kept[date] = dto.routine_id;
    await this.profiles.update({ userId }, { dayOverrides: kept });
    return this.overview(userId, now);
  }

  public async updateSettings(
    userId: number,
    dto: GymSettingsDto,
  ): Promise<GymSettingsView> {
    const profile = await this.workouts.profileOf(userId);
    if (dto.rest_sec !== undefined) profile.restSec = dto.rest_sec;
    if (dto.effort_scale !== undefined) profile.effortScale = dto.effort_scale;
    if (dto.keep_awake !== undefined) profile.keepAwake = dto.keep_awake;
    if (dto.sound !== undefined) profile.sound = dto.sound;
    if (dto.body_figure !== undefined) profile.bodyFigure = dto.body_figure;
    return this.settingsView(await this.profiles.save(profile));
  }

  /// A routine for a day: the one-off change if there is one, else the weekly plan.
  public routineFor(
    date: string,
    profile: GymProfileEntity,
    routineIds: Set<number>,
  ): { routine_id: number | null; source: DaySource } {
    const override = profile.dayOverrides[date];
    if (override === 'rest')
      return { routine_id: null, source: 'rest_override' };
    if (typeof override === 'number' && routineIds.has(override)) {
      return { routine_id: override, source: 'rescheduled' };
    }
    const weekly = profile.week[String(isoWeekday(date))];
    if (weekly !== undefined && routineIds.has(weekly))
      return { routine_id: weekly, source: 'weekly' };
    return { routine_id: null, source: 'none' };
  }

  public routineRows(userId: number): Promise<GymRoutineEntity[]> {
    return this.routines.find({
      where: { userId },
      order: { position: 'ASC', id: 'ASC' },
    });
  }

  private dayOf(
    date: string,
    profile: GymProfileEntity,
    routines: GymRoutineEntity[],
    countOn: (date: string) => number,
    today: string,
  ): PlannedDay {
    return {
      diary_date: date,
      weekday: isoWeekday(date),
      ...this.routineFor(date, profile, new Set(routines.map((r) => r.id))),
      workouts: countOn(date),
      is_today: date === today,
    };
  }

  private sessionPlans(
    routines: GymRoutineEntity[],
    exercises: Map<string, ExerciseEntity>,
    logged: GymWorkoutEntity[],
    profile: GymProfileEntity,
  ): Record<string, SessionEntry[]> {
    const sessions = sessionsByExercise(logged);
    return Object.fromEntries(
      routines.map((r) => [
        String(r.id),
        r.exercises
          .filter((cfg) => exercises.has(cfg.exercise_id))
          .map((cfg) => {
            const ex = exercises.get(cfg.exercise_id) as ExerciseEntity;
            const working = profile.workingWeights[cfg.exercise_id];
            return planEntry({
              cfg,
              routineRule: r.progression as RoutineRule,
              exercise: {
                name: ex.name,
                bodyPart: ex.bodyPart,
                isBodyweight: ex.isBodyweight,
                mediaUrl: this.library.mediaUrlFor(ex),
                muscles: musclesOf(ex),
                steps: ex.steps,
              },
              history: sessions.get(cfg.exercise_id) ?? [],
              workingWeightKg: working?.weight_kg ?? 0,
              bestWeightKg:
                bestsOf(sessions.get(cfg.exercise_id), working)?.weightKg ||
                null,
            });
          }),
      ]),
    );
  }

  private routineView(
    r: GymRoutineEntity,
    exercises: Map<string, ExerciseEntity>,
  ): RoutineView {
    return {
      id: r.id,
      name: r.name,
      icon: r.icon,
      progression: r.progression,
      // An exercise deleted since is dropped from the view rather than shown as a blank row.
      exercises: r.exercises
        .filter((e) => exercises.has(e.exercise_id))
        .map((e) => {
          const ex = exercises.get(e.exercise_id) as ExerciseEntity;
          return {
            ...e,
            name: ex.name,
            body_part: ex.bodyPart,
            equipment: ex.equipment,
            is_bodyweight: e.bodyweight ?? ex.isBodyweight,
            is_cardio: ex.bodyPart === 'cardio',
          };
        }),
    };
  }

  private settingsView(p: GymProfileEntity): GymSettingsView {
    return {
      rest_sec: p.restSec,
      effort_scale: p.effortScale,
      keep_awake: p.keepAwake,
      sound: p.sound,
      body_figure: p.bodyFigure,
    };
  }

  private async exercisesOf(userId: number, routines: GymRoutineEntity[]) {
    return this.library.byIds(
      userId,
      routines.flatMap((r) => r.exercises.map((e) => e.exercise_id)),
    );
  }

  /// Every exercise must exist for this person, and cardio is logged as cardio.
  private async checkedExercises(
    userId: number,
    list: RoutineExercise[],
  ): Promise<Map<string, ExerciseEntity>> {
    const exercises = await this.library.byIds(
      userId,
      list.map((e) => e.exercise_id),
    );
    for (const e of list) {
      const ex = exercises.get(e.exercise_id);
      if (!ex) throw gymInvalid(GYM_COPY.unknownExercise);
      if ((ex.bodyPart === 'cardio') !== (e.mode === 'cardio'))
        throw gymInvalid(GYM_COPY.modeMismatch);
    }
    return exercises;
  }

  private async ownedRoutine(
    userId: number,
    id: number,
  ): Promise<GymRoutineEntity> {
    const row = await this.routines.findOne({ where: { id, userId } });
    if (!row)
      throw gymNotFound('GYM_ROUTINE_NOT_FOUND', GYM_COPY.routineNotFound);
    return row;
  }
}
