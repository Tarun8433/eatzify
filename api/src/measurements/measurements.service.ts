import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import { MeasurementEntity } from './entities/measurement.entity';
import { CreateMeasurementDto } from './dto/create-measurement.dto';
import { diaryDateFor } from '../plans/diary-date';
import {
  BOUNDS,
  canOverwrite,
  unitFor,
  isSuspectDelta,
  isWithinBounds,
  trendChange,
  windowedTrendChange,
  type MeasurementKind,
  type MeasurementSource,
} from './measurement-rules';

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
};

@Injectable()
export class MeasurementsService {
  constructor(
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
  ) {}

  /// docs/09 §4. One reading per kind per diary day — a second entry the same day corrects the
  /// first rather than adding to it (docs/08's unique constraint).
  async record(
    userId: number,
    dto: CreateMeasurementDto,
  ): Promise<{ measurement: MeasurementView; is_suspect: boolean }> {
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

    const source = (dto.source ?? 'manual') as MeasurementSource;
    const existingSource = existing
      ? (existing.source as MeasurementSource)
      : null;

    // D-97. A background sync does not get to undo a correction someone made by hand. Returning
    // the row that stands rather than throwing: the sync did nothing wrong, and there is nothing
    // for a user to act on — an error here would surface as a failure on a screen they are not
    // looking at.
    if (!canOverwrite(existingSource, source)) {
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
    const rows = await this.measurements.find({
      where: { userId, kind },
      order: { diaryDate: 'ASC' },
      take: limit,
    });

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
    };
  }

  /// The most recent reading of each kind — used by `GET /profile`.
  async latest(userId: number): Promise<MeasurementView[]> {
    const rows = await this.measurements.find({
      where: { userId },
      order: { diaryDate: 'DESC' },
    });

    const seen = new Set<string>();
    return rows
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
