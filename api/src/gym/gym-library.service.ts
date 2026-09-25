import { randomUUID } from 'crypto';
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, QueryFailedError, Repository } from 'typeorm';
import { ExerciseEntity } from './entities/exercise.entity';
import { GymProfileEntity } from './entities/gym-profile.entity';
import { GymRoutineEntity } from './entities/gym-routine.entity';
import type { CreateExerciseDto, UpdateExerciseDto } from './dto/exercise.dto';
import { GYM_COPY, gymConflict, gymForbidden, gymNotFound } from './gym-copy';
import { musclesOf, type MuscleShare } from './muscles';
import { cleanSupersets } from './routine-rules';

export type ExerciseView = {
  id: string;
  name: string;
  body_part: string;
  equipment: string;
  target: string;
  secondary: string[];
  muscles: MuscleShare[];
  is_bodyweight: boolean;
  is_cardio: boolean;
  is_custom: boolean;
  description: string | null;
  /// D-243: null until exercise media is licensed and GYM_MEDIA_BASE_URL is set.
  media_url: string | null;
  thumb_url: string | null;
};

export type ExerciseDetailView = ExerciseView & {
  steps: { en: string[]; hi: string[] };
};

/// The list omits steps: 1,324 exercises with two languages of steps is 2.5 MB, the list without is
/// a tenth of that. Steps come with the detail.
const LIST_COLUMNS: (keyof ExerciseEntity)[] = [
  'id',
  'name',
  'bodyPart',
  'equipment',
  'target',
  'secondaryMuscles',
  'description',
  'mediaKey',
  'energyActivity',
  'isBodyweight',
  'ownerUserId',
];

const CUSTOM_ENERGY = { cardio: 'circuit', other: 'strength' } as const;
const CUSTOM_EQUIPMENT = 'custom';

@Injectable()
export class GymLibraryService {
  constructor(
    @InjectRepository(ExerciseEntity)
    private readonly exercises: Repository<ExerciseEntity>,
    @InjectRepository(GymRoutineEntity)
    private readonly routines: Repository<GymRoutineEntity>,
    @InjectRepository(GymProfileEntity)
    private readonly profiles: Repository<GymProfileEntity>,
  ) {}

  /// The shared library plus this person's own exercises — their own first, the way they look for them.
  public async list(userId: number): Promise<ExerciseView[]> {
    const rows = await this.exercises.find({
      select: LIST_COLUMNS,
      where: [{ ownerUserId: IsNull() }, { ownerUserId: userId }],
      order: { name: 'ASC' },
    });
    const own = rows.filter((r) => r.ownerUserId !== null);
    const library = rows.filter((r) => r.ownerUserId === null);
    return [...own, ...library].map((r) => this.toView(r));
  }

  /// One exercise this person may see, or a 404 — someone else's custom exercise does not exist to them.
  public async visible(userId: number, id: string): Promise<ExerciseEntity> {
    const row = await this.exercises.findOne({
      where: [
        { id, ownerUserId: IsNull() },
        { id, ownerUserId: userId },
      ],
    });
    if (!row)
      throw gymNotFound('GYM_EXERCISE_NOT_FOUND', GYM_COPY.exerciseNotFound);
    return row;
  }

  public async byIds(
    userId: number,
    ids: string[],
  ): Promise<Map<string, ExerciseEntity>> {
    if (ids.length === 0) return new Map();
    const rows = await this.exercises.find({
      // Steps too, unlike the whole-library list: this is one routine's handful of exercises, and
      // the workout screen reads them with no signal.
      select: [...LIST_COLUMNS, 'steps'],
      where: [
        { id: In([...new Set(ids)]), ownerUserId: IsNull() },
        { id: In([...new Set(ids)]), ownerUserId: userId },
      ],
    });
    return new Map(rows.map((r) => [r.id, r]));
  }

  public async create(
    userId: number,
    dto: CreateExerciseDto,
  ): Promise<ExerciseView> {
    const row = this.exercises.create({
      id: `c-${randomUUID()}`,
      name: dto.name.trim(),
      bodyPart: dto.body_part,
      equipment: CUSTOM_EQUIPMENT,
      target: '',
      secondaryMuscles: [],
      steps: { en: [], hi: [] },
      description: dto.description?.trim() || null,
      mediaKey: null,
      energyActivity:
        dto.body_part === 'cardio' ? CUSTOM_ENERGY.cardio : CUSTOM_ENERGY.other,
      isBodyweight: false,
      ownerUserId: userId,
    });
    return this.toView(await this.saveUnique(row));
  }

  public async update(
    userId: number,
    id: string,
    dto: UpdateExerciseDto,
  ): Promise<ExerciseView> {
    const row = await this.owned(userId, id);
    if (dto.name !== undefined) row.name = dto.name.trim();
    if (dto.body_part !== undefined) {
      row.bodyPart = dto.body_part;
      row.energyActivity =
        dto.body_part === 'cardio' ? CUSTOM_ENERGY.cardio : CUSTOM_ENERGY.other;
    }
    if (dto.description !== undefined)
      row.description = dto.description?.trim() || null;
    return this.toView(await this.saveUnique(row));
  }

  /// Gone from routines and working weights; past workouts keep it, by the name stamped on them.
  public async remove(userId: number, id: string): Promise<void> {
    const row = await this.owned(userId, id);
    const routines = await this.routines.find({ where: { userId } });
    for (const routine of routines) {
      if (!routine.exercises.some((e) => e.exercise_id === id)) continue;
      routine.exercises = cleanSupersets(
        routine.exercises.filter((e) => e.exercise_id !== id),
      );
      await this.routines.save(routine);
    }
    const profile = await this.profiles.findOne({ where: { userId } });
    if (profile?.workingWeights[id]) {
      profile.workingWeights = Object.fromEntries(
        Object.entries(profile.workingWeights).filter(([key]) => key !== id),
      );
      await this.profiles.save(profile);
    }
    await this.exercises.delete({ id: row.id });
  }

  /// The animation's address, or null until media is licensed and GYM_MEDIA_BASE_URL is set.
  public mediaUrlFor(e: Pick<ExerciseEntity, 'id' | 'mediaKey'>): string | null {
    const base = process.env.GYM_MEDIA_BASE_URL?.replace(/\/$/, '');
    return base && e.mediaKey ? `${base}/${e.id}-${e.mediaKey}.gif` : null;
  }

  public toView(e: ExerciseEntity): ExerciseView {
    const base = process.env.GYM_MEDIA_BASE_URL?.replace(/\/$/, '');
    const media = base && e.mediaKey ? `${base}/${e.id}-${e.mediaKey}` : null;
    return {
      id: e.id,
      name: e.name,
      body_part: e.bodyPart,
      equipment: e.equipment,
      target: e.target,
      secondary: e.secondaryMuscles,
      muscles: musclesOf(e),
      is_bodyweight: e.isBodyweight,
      is_cardio: e.bodyPart === 'cardio',
      is_custom: e.ownerUserId !== null,
      description: e.description,
      media_url: media ? `${media}.gif` : null,
      thumb_url: media ? `${media}.jpg` : null,
    };
  }

  public toDetailView(e: ExerciseEntity): ExerciseDetailView {
    return { ...this.toView(e), steps: e.steps };
  }

  private async owned(userId: number, id: string): Promise<ExerciseEntity> {
    const row = await this.visible(userId, id);
    if (row.ownerUserId !== userId)
      throw gymForbidden(GYM_COPY.exerciseNotYours);
    return row;
  }

  /// The database decides duplicates (UQ_exercise_owner_name), so two taps cannot both win.
  private async saveUnique(row: ExerciseEntity): Promise<ExerciseEntity> {
    try {
      return await this.exercises.save(row);
    } catch (error) {
      const code = (
        error as QueryFailedError & { driverError?: { code?: string } }
      ).driverError?.code;
      if (error instanceof QueryFailedError && code === '23505') {
        throw gymConflict(GYM_COPY.exerciseExists);
      }
      throw error;
    }
  }
}
