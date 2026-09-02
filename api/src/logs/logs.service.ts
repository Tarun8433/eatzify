import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { FoodLogEntity } from './entities/food-log.entity';
import { FoodEntity } from '../foods/entities/food.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { PlanEntity } from '../plans/entities/plan.entity';
import { LogFoodDto } from './dto/log-food.dto';
import { diaryDateFor, diaryWindowFor } from '../plans/diary-date';

export type LogEntryView = {
  id: string;
  slot: string;
  name: string;
  quantity_g: number;
  measure_label: string | null;
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  /// Null means "not recorded" (a custom entry, or a row from before D-136) — not zero.
  fibre_g: number | null;
  locked: boolean;
};

export type DayView = {
  diary_date: string;
  entries: LogEntryView[];
  totals: {
    kcal: number;
    protein_g: number;
    carb_g: number;
    fat_g: number;
    fibre_g: number;
  };
  /// Null when no plan exists yet — the client must show "no plan", not a comparison against zero.
  targets: {
    kcal: number;
    protein_g: number;
    carb_g: number;
    fat_g: number;
    fibre_g: number | null;
  } | null;
  /// What the user reported moving today (D-80). Null means NOT RECORDED, and the client must say
  /// so rather than showing a zero — "you burned nothing" and "we are not measuring" are different
  /// sentences and the second one is the true one.
  /// `source` says where the step count came from — `manual`, `apple_health`, `health_connect` —
  /// so the client can label it (rule 10). Null when nothing was recorded.
  activity: {
    steps: number | null;
    energy_burned_kcal: number | null;
    steps_source: string | null;
  };
  /// The UTC instants this diary day spans, [start, end). Sent so a phone can ask HealthKit or
  /// Health Connect for the day's steps without deriving the 04:00 IST boundary itself — rule 8
  /// puts that arithmetic in exactly one place (D-98).
  diary_window: { start: string; end: string };
  /// Hydration (D-86). `target_ml` is the engine's, computed from body weight against the rule
  /// pack — the app never works out how much anyone should drink. Null means no plan yet.
  water: { logged_ml: number | null; target_ml: number | null };
};

/// docs/08: a diary entry is editable for 48 hours, then locked.
const EDIT_WINDOW_MS = 48 * 60 * 60 * 1000;

@Injectable()
export class LogsService {
  constructor(
    @InjectRepository(FoodLogEntity)
    private readonly logs: Repository<FoodLogEntity>,
    @InjectRepository(FoodEntity)
    private readonly foods: Repository<FoodEntity>,
    @InjectRepository(PlanEntity)
    private readonly plans: Repository<PlanEntity>,
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
  ) {}

  /// docs/09 §5. The diary date is resolved here, never sent by the client (CLAUDE.md rule 8).
  async logFood(userId: number, dto: LogFoodDto): Promise<LogEntryView> {
    const diaryDate = diaryDateFor(new Date());

    if (dto.food_id) return this.logKnownFood(userId, diaryDate, dto);
    if (dto.custom_name) return this.logCustom(userId, diaryDate, dto);

    throw this.invalid('Choose a food, or give your entry a name.');
  }

  private async logKnownFood(
    userId: number,
    diaryDate: string,
    dto: LogFoodDto,
  ): Promise<LogEntryView> {
    const food = await this.foods.findOne({
      where: { id: dto.food_id },
      relations: { measures: true },
    });

    if (!food || !food.isVerified) {
      throw this.invalid('That food is not available. Please pick another.');
    }

    const grams = this.gramsFor(food, dto);

    // Per 100 g edible portion (docs/03), scaled to what was eaten. The result is COPIED onto the
    // row — see the entity comment: correcting this food later must not rewrite an old diary.
    const factor = grams / 100;
    const saved = await this.logs.save({
      userId,
      diaryDate,
      slot: dto.slot,
      foodId: food.id,
      customName: null,
      quantityG: grams.toFixed(1),
      measureLabel: dto.measure ?? null,
      kcal: (Number(food.kcal) * factor).toFixed(1),
      proteinG: (Number(food.proteinG) * factor).toFixed(1),
      carbG: (Number(food.carbG) * factor).toFixed(1),
      fatG: (Number(food.fatG) * factor).toFixed(1),
      fibreG: (Number(food.fibreG) * factor).toFixed(1),
      source: 'manual',
    });

    return this.toView(saved as FoodLogEntity, food.name);
  }

  private async logCustom(
    userId: number,
    diaryDate: string,
    dto: LogFoodDto,
  ): Promise<LogEntryView> {
    if (dto.kcal === undefined) {
      throw this.invalid('Please add the calories for your own entry.');
    }

    const saved = await this.logs.save({
      userId,
      diaryDate,
      slot: dto.slot,
      foodId: null,
      customName: dto.custom_name,
      quantityG: (dto.quantity_g ?? 0).toFixed(1),
      measureLabel: null,
      kcal: dto.kcal.toFixed(1),
      // Nobody types their fibre for a custom entry; null says "not recorded" rather than nought.
      fibreG: null,
      proteinG: (dto.protein_g ?? 0).toFixed(1),
      carbG: (dto.carb_g ?? 0).toFixed(1),
      fatG: (dto.fat_g ?? 0).toFixed(1),
      source: 'manual',
    });

    return this.toView(saved as FoodLogEntity, dto.custom_name!);
  }

  /// A measure the food does not define is refused rather than guessed at — silently falling back
  /// to 100 g would log a quantity nobody chose.
  private gramsFor(food: FoodEntity, dto: LogFoodDto): number {
    if (dto.measure) {
      const measure = food.measures?.find((m) => m.label === dto.measure);
      if (!measure)
        throw this.invalid('That measure is not available for this food.');
      return Number(measure.grams) * (dto.measure_count ?? 1);
    }

    if (dto.quantity_g !== undefined) return dto.quantity_g;

    throw this.invalid('Please say how much you had.');
  }

  async day(userId: number, date?: string): Promise<DayView> {
    const diaryDate = date ?? diaryDateFor(new Date());

    const [rows, plan, activity] = await Promise.all([
      this.logs.find({
        where: { userId, diaryDate },
        relations: { food: true },
        order: { loggedAt: 'ASC' },
      }),
      this.plans.findOne({ where: { userId }, order: { createdAt: 'DESC' } }),
      // Same diary day as the food, from the same request, so Home does not need a second call
      // to answer a question it is already asking.
      this.measurements.find({
        where: [
          { userId, diaryDate, kind: 'steps' },
          { userId, diaryDate, kind: 'energy_burned_kcal' },
          { userId, diaryDate, kind: 'water_ml' },
        ],
      }),
    ]);

    const rowFor = (kind: string) => activity.find((m) => m.kind === kind);
    const reported = (kind: string): number | null => {
      const row = rowFor(kind);
      return row === undefined ? null : Number(row.value);
    };

    const entries = rows.map((r) =>
      this.toView(r, r.customName ?? r.food?.name ?? '—'),
    );
    const totals = entries.reduce(
      (sum, e) => ({
        kcal: sum.kcal + e.kcal,
        protein_g: sum.protein_g + e.protein_g,
        carb_g: sum.carb_g + e.carb_g,
        fat_g: sum.fat_g + e.fat_g,
        // Null contributes nothing: a custom entry or a pre-D-136 row under-reports the day
        // rather than blocking the sum, and new rows always carry a value.
        fibre_g: sum.fibre_g + (e.fibre_g ?? 0),
      }),
      { kcal: 0, protein_g: 0, carb_g: 0, fat_g: 0, fibre_g: 0 },
    );

    const window = diaryWindowFor(diaryDate);

    return {
      diary_date: diaryDate,
      diary_window: {
        start: window.start.toISOString(),
        end: window.end.toISOString(),
      },
      entries,
      totals: {
        kcal: Math.round(totals.kcal),
        protein_g: Math.round(totals.protein_g),
        carb_g: Math.round(totals.carb_g),
        fat_g: Math.round(totals.fat_g),
        fibre_g: Math.round(totals.fibre_g),
      },
      targets: plan?.targets
        ? {
            kcal: plan.targets.kcal,
            protein_g: plan.targets.proteinG,
            carb_g: plan.targets.carbG,
            fat_g: plan.targets.fatG,
            // The engine has always computed this (computeFibre, pack g_per_1000_kcal) and
            // persisted it in plan.targets; this line is the whole reason the app never saw it.
            fibre_g: plan.targets.fibreG ?? null,
          }
        : null,
      activity: {
        steps: reported('steps'),
        energy_burned_kcal: reported('energy_burned_kcal'),
        steps_source: rowFor('steps')?.source ?? null,
      },
      water: {
        logged_ml: reported('water_ml'),
        // Stored by the engine on every plan since the rule pack has always had a water section;
        // it simply never reached the client (D-86).
        target_ml: plan?.targets?.waterMl ?? null,
      },
    };
  }

  async remove(userId: number, id: string): Promise<void> {
    const row = await this.logs.findOne({ where: { id, userId } });
    if (!row) return;

    if (this.isLocked(row)) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'LOG_LOCKED',
          user_message:
            'Entries can be changed for two days. This one is now part of your history.',
        },
      });
    }

    await this.logs.delete({ id, userId });
  }

  private isLocked(row: FoodLogEntity): boolean {
    if (row.lockedAt) return true;
    return Date.now() - new Date(row.loggedAt).getTime() > EDIT_WINDOW_MS;
  }

  private toView(row: FoodLogEntity, name: string): LogEntryView {
    return {
      id: row.id,
      slot: row.slot,
      name,
      quantity_g: Number(row.quantityG),
      measure_label: row.measureLabel,
      kcal: Number(row.kcal),
      protein_g: Number(row.proteinG),
      carb_g: Number(row.carbG),
      fat_g: Number(row.fatG),
      fibre_g: row.fibreG === null ? null : Number(row.fibreG),
      locked: this.isLocked(row),
    };
  }

  private invalid(userMessage: string): UnprocessableEntityException {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code: 'LOG_INVALID', user_message: userMessage },
    });
  }
}
