import {
  HttpException,
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  In,
  LessThan,
  LessThanOrEqual,
  QueryFailedError,
  Repository,
} from 'typeorm';
import { MeasurementEntity } from './entities/measurement.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { CreateMeasurementDto } from './dto/create-measurement.dto';
import { BulkReadingDto } from './dto/create-measurements-bulk.dto';
import { diaryDateFor } from '../plans/diary-date';
import {
  BOUNDS,
  canOverwrite,
  foldStepsAdded,
  unitFor,
  isSuspectDelta,
  isWithinBounds,
  trendChange,
  windowedTrendChange,
  type MeasurementKind,
  type MeasurementSource,
} from './measurement-rules';
import {
  ACTIVITY_KINDS,
  burnedByDay,
  kcalPer1000Steps,
  type Body,
  type WalkingEnergy,
} from './walking-energy';

export type MeasurementView = {
  id: string;
  kind: string;
  value: number;
  unit: string;
  diary_date: string;
  is_suspect: boolean;
  /// Rule 10: the app has to be able to say where a number came from, so it has to be told.
  source: MeasurementSource;
};

export type HistoryView = {
  kind: string;
  points: MeasurementView[];
  /// From the moving average, never from min/max (docs/16). Null when there is no trend yet.
  change: number | null;
  /// The same discipline over only the last 30 diary days (docs/21 §3) — the figure the weight
  /// card's sentence wants. Null when the window has too little; the app then falls back to
  /// [change]'s since-start sentence.
  change_30d: number | null;
  /// Steps only (D-256): calories per 1,000 steps for this person. Null when there is no weight
  /// to work from. A rate to read, never a figure to add to calories burned.
  kcal_per_1000_steps?: WalkingEnergy | null;
};

/// How many days of activity the rate and the usual stride are taken over — a month smooths one odd
/// day out.
const STRIDE_WINDOW_DAYS = 30;

export type RecordedView = {
  measurement: MeasurementView;
  is_suspect: boolean;
};

/// One slot per reading sent, in the order sent.
export type BulkResultView =
  | ({ ok: true } & RecordedView)
  | { ok: false; error: { code: string; user_message: string } };

/// Postgres `unique_violation`.
const UNIQUE_VIOLATION = '23505';

function isUniqueViolation(error: unknown): boolean {
  return (
    error instanceof QueryFailedError &&
    (error.driverError as { code?: string } | undefined)?.code ===
      UNIQUE_VIOLATION
  );
}

/// The `{ code, user_message }` this module's refusals already carry, so a bulk caller reads the
/// same envelope a single POST would have returned.
function refusalOf(error: HttpException): {
  code: string;
  user_message: string;
} {
  const body = error.getResponse() as {
    error?: { code?: string; user_message?: string };
  };
  return {
    code: body.error?.code ?? 'VALIDATION_FAILED',
    user_message: body.error?.user_message ?? error.message,
  };
}

@Injectable()
export class MeasurementsService {
  constructor(
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
  ) {}

  /// docs/09 §4. One reading per kind per diary day — a second entry the same day corrects the
  /// first rather than adding to it (docs/08's unique constraint).
  async record(
    userId: number,
    dto: CreateMeasurementDto,
    replaceManual = false,
  ): Promise<RecordedView> {
    try {
      return await this.write(userId, dto, replaceManual);
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      // D-216. Two writes for the same (user, kind, day) both found no row and both inserted; this
      // one lost. Once more, and the retry finds the winner's row and applies the overwrite rule
      // to it — so the outcome is what it would have been had they arrived in order.
      return this.write(userId, dto, replaceManual);
    }
  }

  /// D-216. A health-platform sync: many readings, one request.
  ///
  /// Sequential, not concurrent. Two readings for the same kind and day in one batch must resolve
  /// in the order they were sent, and parallel writes would race each other into the unique index.
  ///
  /// A reading the rules refuse is reported in its own slot and the rest still land — one
  /// out-of-range day must not discard a month of good ones. Anything that is NOT a refusal (the
  /// database going away) still fails the request: a partial answer to that is not an answer.
  async recordMany(
    userId: number,
    readings: BulkReadingDto[],
  ): Promise<{ results: BulkResultView[] }> {
    const results: BulkResultView[] = [];
    for (const reading of readings) {
      try {
        const recorded = await this.record(
          userId,
          reading,
          reading.replace_manual === true,
        );
        results.push({ ok: true, ...recorded });
      } catch (error) {
        if (!(error instanceof HttpException)) throw error;
        results.push({ ok: false, error: refusalOf(error) });
      }
    }
    return { results };
  }

  private async write(
    userId: number,
    dto: CreateMeasurementDto,
    replaceManual: boolean,
  ): Promise<RecordedView> {
    const kind = dto.kind as MeasurementKind;

    if (!isWithinBounds(kind, dto.value)) {
      const bound = BOUNDS[kind];
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'VALUE_OUT_OF_RANGE',
          user_message: `Please enter a ${kind.replace('_', ' ')} between ${bound.min} and ${bound.max} ${bound.unit}.`,
        },
      });
    }

    // The DTO only says the unit is one the app knows. This says it is the right one for THIS
    // kind — without it "80 steps" stores happily as a body weight (D-80).
    const expected = unitFor(kind);
    if (dto.unit !== expected) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'UNIT_MISMATCH',
          user_message: `A ${kind.replace('_', ' ')} is measured in ${expected}.`,
        },
      });
    }

    const source = (dto.source ?? 'manual') as MeasurementSource;
    // D-221. A device reports what it counted; only a person adds to it.
    if (kind === 'steps_added' && source !== 'manual') {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'SOURCE_NOT_ALLOWED',
          user_message: 'Added steps can only be entered by hand.',
        },
      });
    }

    const recordedAt = dto.recorded_at ? new Date(dto.recorded_at) : new Date();
    const diaryDate = diaryDateFor(recordedAt);

    const previous = await this.measurements.findOne({
      where: { userId, kind, diaryDate: LessThan(diaryDate) },
      order: { diaryDate: 'DESC' },
    });

    const isSuspect = isSuspectDelta(
      kind,
      dto.value,
      previous
        ? { value: Number(previous.value), diaryDate: previous.diaryDate }
        : null,
      diaryDate,
    );

    const existing = await this.measurements.findOne({
      where: { userId, kind, diaryDate },
    });

    const existingSource = existing
      ? (existing.source as MeasurementSource)
      : null;

    // D-97. A background sync does not get to undo a correction someone made by hand. Returning
    // the row that stands rather than throwing: the sync did nothing wrong, and there is nothing
    // for a user to act on — an error here would surface as a failure on a screen they are not
    // looking at.
    if (!canOverwrite(existingSource, source, replaceManual)) {
      return {
        measurement: this.toView(existing as MeasurementEntity),
        is_suspect: (existing as MeasurementEntity).isSuspect,
      };
    }

    const saved = await this.measurements.save({
      ...(existing ?? {}),
      userId,
      kind,
      value: dto.value.toFixed(2),
      unit: dto.unit,
      diaryDate,
      source,
      isSuspect,
    });

    return {
      measurement: this.toView(saved as MeasurementEntity),
      is_suspect: isSuspect,
    };
  }

  async history(
    userId: number,
    kind: string,
    limit = 90,
  ): Promise<HistoryView> {
    // Steps carry the person's additions with them (D-221), so a steps history reads both kinds —
    // up to two rows a day, hence the doubled take — and folds them back into one.
    if (kind === 'energy_burned_kcal') return this.burnedHistory(userId, limit);
    const steps = kind === 'steps';
    const rows = foldStepsAdded(
      await this.measurements.find({
        where: { userId, kind: steps ? In(['steps', 'steps_added']) : kind },
        order: { diaryDate: 'ASC' },
        take: steps ? limit * 2 : limit,
      }),
    ).slice(0, limit);

    return {
      kind,
      points: rows.map((r) => this.toView(r)),
      change: trendChange(
        rows.map((r) => ({ value: Number(r.value), isSuspect: r.isSuspect })),
      ),
      change_30d: windowedTrendChange(
        rows.map((r) => ({
          value: Number(r.value),
          isSuspect: r.isSuspect,
          diaryDate: r.diaryDate,
        })),
        30,
      ),
      ...(steps && {
        kcal_per_1000_steps: await this.walkingEnergy(userId),
      }),
    };
  }

  /// D-268: calories burned per day are worked out, never the phone's own figure — the same
  /// numbers Home shows. Points are the most recent [limit] days, oldest first.
  private async burnedHistory(
    userId: number,
    limit: number,
  ): Promise<HistoryView> {
    const [rows, body] = await Promise.all([
      this.activityRows(userId, limit),
      this.body(userId),
    ]);
    const burned = burnedByDay(rows, body);
    // The day's own row says where the figure came from (rule 10): the steps it was worked out
    // from, or the calories someone reported on a day with none.
    const sourceRow = (date: string) =>
      rows.find((r) => r.diaryDate === date && r.kind === 'steps') ??
      rows.find((r) => r.diaryDate === date);
    const points = [...burned.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .slice(-limit)
      .map(([date, kcal]): MeasurementView => {
        const row = sourceRow(date)!;
        return {
          id: row.id,
          kind: 'energy_burned_kcal',
          value: kcal,
          unit: unitFor('energy_burned_kcal'),
          diary_date: date,
          is_suspect: false,
          source: row.source as MeasurementSource,
        };
      });
    const trend = points.map((p) => ({ value: p.value, isSuspect: false }));
    return {
      kind: 'energy_burned_kcal',
      points,
      change: trendChange(trend),
      change_30d: windowedTrendChange(
        points.map((p) => ({
          ...p,
          isSuspect: false,
          diaryDate: p.diary_date,
        })),
        30,
      ),
    };
  }

  /// D-268: what [diaryDate] burned above resting, from its steps at the person's own weight, or
  /// the figure reported for a day with no steps. Null when there is neither.
  async burnedOn(userId: number, diaryDate: string): Promise<number | null> {
    const [rows, body] = await Promise.all([
      this.activityRows(userId, STRIDE_WINDOW_DAYS, diaryDate),
      this.body(userId),
    ]);
    return burnedByDay(rows, body).get(diaryDate) ?? null;
  }

  /// D-268. Calories per 1,000 steps from the person's last month of activity and their weight.
  async walkingEnergy(userId: number): Promise<WalkingEnergy | null> {
    const [rows, body] = await Promise.all([
      this.activityRows(userId, STRIDE_WINDOW_DAYS),
      this.body(userId),
    ]);
    return kcalPer1000Steps(rows, body);
  }

  /// The newest trustworthy weight, else the profile's, and the profile's height.
  async body(userId: number): Promise<Body> {
    const [weight, profile] = await Promise.all([
      this.measurements.findOne({
        where: { userId, kind: 'weight', isSuspect: false },
        order: { diaryDate: 'DESC' },
      }),
      this.profiles.findOne({ where: { userId } }),
    ]);
    return {
      weightKg: weight
        ? Number(weight.value)
        : profile
          ? Number(profile.weightKg)
          : null,
      heightCm: profile?.heightCm ?? null,
    };
  }

  /// The activity rows of about the last [days] diary days up to [until] (inclusive).
  // ponytail: a row cap, not a date range — a day rarely holds every kind, so it reaches back a
  // little further than [days]; a date range if that ever matters.
  private activityRows(
    userId: number,
    days: number,
    until?: string,
  ): Promise<MeasurementEntity[]> {
    return this.measurements.find({
      where: {
        userId,
        kind: In([...ACTIVITY_KINDS]),
        ...(until && { diaryDate: LessThanOrEqual(until) }),
      },
      order: { diaryDate: 'DESC' },
      take: days * ACTIVITY_KINDS.length,
    });
  }

  /// The most recent reading of each kind — used by `GET /profile`.
  async latest(userId: number): Promise<MeasurementView[]> {
    const rows = await this.measurements.find({
      where: { userId },
      order: { diaryDate: 'DESC' },
    });

    const seen = new Set<string>();
    return foldStepsAdded(rows)
      .filter((r) =>
        seen.has(r.kind) ? false : seen.add(r.kind) !== undefined,
      )
      .map((r) => this.toView(r));
  }

  private toView(row: MeasurementEntity): MeasurementView {
    return {
      id: row.id,
      kind: row.kind,
      value: Number(row.value),
      unit: row.unit,
      diary_date: row.diaryDate,
      is_suspect: row.isSuspect,
      source: (row.source ?? 'manual') as MeasurementSource,
    };
  }
}
