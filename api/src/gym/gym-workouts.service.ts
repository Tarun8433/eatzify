import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, QueryFailedError, Repository } from 'typeorm';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { diaryDateFor } from '../plans/diary-date';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { EnergyReferenceEntity } from './entities/energy-reference.entity';
import type { ExerciseEntity } from './entities/exercise.entity';
import { GymProfileEntity } from './entities/gym-profile.entity';
import { GymWorkoutEntity } from './entities/gym-workout.entity';
import type {
  SaveWorkoutDto,
  WorkoutEntryDto,
  WorkoutSetDto,
} from './dto/workout.dto';
import { GYM_COPY, gymInvalid, gymNotFound } from './gym-copy';
import { bestsOf, sessionsByExercise } from './gym-history';
import { muscleLevels, type MuscleLevel } from './gym-stats';
import type {
  EnergyBasis,
  WorkoutEntry,
  WorkoutRecord,
  WorkoutSet,
} from './gym-types';
import { GymLibraryService } from './gym-library.service';
import { musclesOf } from './muscles';
import { workoutEnergy, type EnergyRow } from './workout-energy';
import {
  raiseWorkingWeights,
  recordsOf,
  setsDone,
  volumeKg,
} from './workout-records';

export type WorkoutSummaryView = {
  id: string;
  routine_id: number | null;
  name: string;
  diary_date: string;
  started_at: string;
  ended_at: string;
  duration_sec: number;
  sets_done: number;
  volume_kg: number;
  /// D-242: an estimate of energy above rest. Null when no body weight was known.
  energy_kcal: number | null;
  pr_count: number;
  exercise_count: number;
};

export type WorkoutDetailView = WorkoutSummaryView & {
  body_weight_kg: number | null;
  entries: WorkoutEntry[];
  prs: (WorkoutRecord & { name: string })[];
  energy_basis: EnergyBasis | null;
  muscles: MuscleLevel[];
};

const MAX_WORKOUT_SEC = 24 * 60 * 60;
export const HISTORY_PAGE = 20;
const MAX_HISTORY_PAGE = 100;

@Injectable()
export class GymWorkoutsService {
  constructor(
    @InjectRepository(GymWorkoutEntity)
    private readonly workouts: Repository<GymWorkoutEntity>,
    @InjectRepository(GymProfileEntity)
    private readonly profiles: Repository<GymProfileEntity>,
    @InjectRepository(EnergyReferenceEntity)
    private readonly energy: Repository<EnergyReferenceEntity>,
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
    @InjectRepository(ProfileEntity)
    private readonly userProfiles: Repository<ProfileEntity>,
    private readonly library: GymLibraryService,
  ) {}

  /// Created on first use with the defaults, so every reader can assume one exists.
  public async profileOf(userId: number): Promise<GymProfileEntity> {
    const found = await this.profiles.findOne({ where: { userId } });
    if (found) return found;
    try {
      return await this.profiles.save(this.profiles.create({ userId }));
    } catch (error) {
      // Two first requests at once: the other one created it.
      if (error instanceof QueryFailedError) {
        const again = await this.profiles.findOne({ where: { userId } });
        if (again) return again;
      }
      throw error;
    }
  }

  /// Every workout, newest first. See gym-history.ts for the ceiling on this.
  public logged(userId: number): Promise<GymWorkoutEntity[]> {
    return this.workouts.find({
      where: { userId },
      order: { startedAt: 'DESC' },
    });
  }

  /// Idempotent on the phone's id: a retried save returns the first save, unchanged.
  public async save(
    userId: number,
    dto: SaveWorkoutDto,
  ): Promise<WorkoutDetailView> {
    const existing = await this.workouts.findOne({ where: { id: dto.id } });
    if (existing) return this.detailOf(userId, existing);

    const startedAt = new Date(dto.started_at);
    const endedAt = new Date(dto.ended_at);
    if (endedAt < startedAt) throw gymInvalid(GYM_COPY.badSpan);
    const durationSec = Math.round(
      (endedAt.getTime() - startedAt.getTime()) / 1000,
    );
    if (durationSec > MAX_WORKOUT_SEC) throw gymInvalid(GYM_COPY.tooLong);

    const exercises = await this.library.byIds(
      userId,
      dto.entries.map((e) => e.exercise_id),
    );
    const entries = dto.entries
      .map((e) => this.entryOf(e, exercises.get(e.exercise_id)))
      .filter((e) => e.sets.some((s) => s.done));

    const [history, profile, weight, rows] = await Promise.all([
      this.logged(userId),
      this.profileOf(userId),
      this.weightFor(userId, dto.body_weight_kg ?? null),
      this.energy.find(),
    ]);
    const diaryDate = diaryDateFor(startedAt);
    const sessions = sessionsByExercise(
      history.map((w) => ({ ...w, diaryDate: w.diaryDate })),
    );
    const prs = recordsOf(entries, (id) =>
      bestsOf(sessions.get(id), profile.workingWeights[id]),
    );

    const energyRows: EnergyRow[] = rows.map((r) => ({
      activity: r.activity,
      value: Number(r.value),
      unit: r.unit,
      minSpeedKmh: r.minSpeedKmh === null ? null : Number(r.minSpeedKmh),
    }));
    const energy = weight
      ? workoutEnergy({
          entries: entries.map((e) => ({
            ...e,
            energy_activity:
              exercises.get(e.exercise_id)?.energyActivity ?? 'strength',
          })),
          durationSec,
          weightKg: weight.kg,
          weightSource: weight.source,
          rows: energyRows,
        })
      : null;

    const row = this.workouts.create({
      id: dto.id,
      userId,
      routineId: dto.routine_id ?? null,
      name: dto.name.trim(),
      startedAt,
      endedAt,
      diaryDate,
      bodyWeightKg:
        dto.body_weight_kg != null ? String(dto.body_weight_kg) : null,
      entries,
      setsDone: setsDone(entries),
      volumeKg: String(volumeKg(entries)),
      durationSec,
      energyKcal: energy?.kcal ?? null,
      energyBasis: energy?.basis ?? null,
      prs,
    });

    try {
      await this.workouts.manager.transaction(async (tx) => {
        await tx.getRepository(GymWorkoutEntity).insert(row);
        await tx.getRepository(GymProfileEntity).update(
          { userId },
          {
            workingWeights: raiseWorkingWeights(
              profile.workingWeights,
              entries,
              diaryDate,
            ),
          },
        );
      });
    } catch (error) {
      // The same save arriving twice at once: the first one's row is the answer.
      const saved = await this.workouts.findOne({ where: { id: dto.id } });
      if (saved) return this.detailOf(userId, saved);
      throw error;
    }
    return this.detailOf(userId, row);
  }

  public async list(
    userId: number,
    before: string | undefined,
    limit: number,
  ): Promise<{ workouts: WorkoutSummaryView[]; next_cursor: string | null }> {
    const take = Math.min(Math.max(limit, 1), MAX_HISTORY_PAGE);
    const rows = await this.workouts.find({
      where: before
        ? { userId, startedAt: LessThan(new Date(before)) }
        : { userId },
      order: { startedAt: 'DESC' },
      take: take + 1,
    });
    const page = rows.slice(0, take);
    return {
      workouts: page.map((w) => this.toSummary(w)),
      next_cursor:
        rows.length > take
          ? page[page.length - 1].startedAt.toISOString()
          : null,
    };
  }

  public async detail(userId: number, id: string): Promise<WorkoutDetailView> {
    const row = await this.workouts.findOne({ where: { id, userId } });
    if (!row)
      throw gymNotFound('GYM_WORKOUT_NOT_FOUND', GYM_COPY.workoutNotFound);
    return this.detailOf(userId, row);
  }

  /// Working weights are not lowered: they are what the person confirmed they can lift, and a
  /// deleted log does not un-lift it.
  public async remove(userId: number, id: string): Promise<void> {
    const result = await this.workouts.delete({ id, userId });
    if (!result.affected)
      throw gymNotFound('GYM_WORKOUT_NOT_FOUND', GYM_COPY.workoutNotFound);
  }

  public toSummary(w: GymWorkoutEntity): WorkoutSummaryView {
    return {
      id: w.id,
      routine_id: w.routineId,
      name: w.name,
      diary_date: w.diaryDate,
      started_at: new Date(w.startedAt).toISOString(),
      ended_at: new Date(w.endedAt).toISOString(),
      duration_sec: w.durationSec,
      sets_done: w.setsDone,
      volume_kg: Number(w.volumeKg),
      energy_kcal: w.energyKcal,
      pr_count: w.prs.length,
      exercise_count: w.entries.length,
    };
  }

  private async detailOf(
    userId: number,
    w: GymWorkoutEntity,
  ): Promise<WorkoutDetailView> {
    if (w.userId !== userId)
      throw gymNotFound('GYM_WORKOUT_NOT_FOUND', GYM_COPY.workoutNotFound);
    const exercises = await this.library.byIds(
      userId,
      w.entries.map((e) => e.exercise_id),
    );
    const nameOf = (id: string) =>
      exercises.get(id)?.name ??
      w.entries.find((e) => e.exercise_id === id)?.name ??
      id;
    return {
      ...this.toSummary(w),
      body_weight_kg: w.bodyWeightKg === null ? null : Number(w.bodyWeightKg),
      entries: w.entries,
      prs: w.prs.map((p) => ({ ...p, name: nameOf(p.exercise_id) })),
      energy_basis: w.energyBasis,
      muscles: muscleLevels(
        w.entries.map((e) => {
          const ex = exercises.get(e.exercise_id);
          return { muscles: ex ? musclesOf(ex) : [], sets: e.sets };
        }),
      ),
    };
  }

  private entryOf(
    e: WorkoutEntryDto,
    exercise: ExerciseEntity | undefined,
  ): WorkoutEntry {
    if (!exercise) throw gymInvalid(GYM_COPY.unknownExercise);
    if ((exercise.bodyPart === 'cardio') !== (e.mode === 'cardio')) {
      throw gymInvalid(GYM_COPY.modeMismatch);
    }
    return {
      exercise_id: exercise.id,
      name: exercise.name,
      mode: e.mode,
      target: e.target ? { ...e.target } : null,
      sets: e.sets.map((s) => setOf(e.mode, s)),
      top_weight_kg: e.top_weight_kg ?? null,
      superset: e.superset ?? null,
    };
  }

  /// The weigh-in if there was one, then the latest weight they logged (not a suspect one), then
  /// the weight they onboarded with. Never a guess.
  private async weightFor(
    userId: number,
    weighIn: number | null,
  ): Promise<{ kg: number; source: EnergyBasis['weight_source'] } | null> {
    if (weighIn) return { kg: weighIn, source: 'weigh_in' };
    const logged = await this.measurements.findOne({
      where: { userId, kind: 'weight', isSuspect: false },
      order: { diaryDate: 'DESC' },
    });
    if (logged) return { kg: Number(logged.value), source: 'measurement' };
    const profile = await this.userProfiles.findOne({ where: { userId } });
    if (profile?.weightKg)
      return { kg: Number(profile.weightKg), source: 'profile' };
    return null;
  }
}

/// Only the fields a set of this mode means, so a stray number cannot count as volume.
function setOf(mode: WorkoutEntry['mode'], s: WorkoutSetDto): WorkoutSet {
  const effort = {
    ...(s.rir != null && { rir: s.rir }),
    ...(s.rpe != null && { rpe: s.rpe }),
  };
  switch (mode) {
    case 'cardio':
      return {
        minutes: s.minutes ?? 0,
        speed_kmh: s.speed_kmh ?? 0,
        done: s.done,
      };
    case 'time':
      return {
        seconds: s.seconds ?? 0,
        weight_kg: s.weight_kg ?? 0,
        done: s.done,
      };
    default:
      return {
        weight_kg: s.weight_kg ?? 0,
        reps: s.reps ?? 0,
        done: s.done,
        ...effort,
      };
  }
}
