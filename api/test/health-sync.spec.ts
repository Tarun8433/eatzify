import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { FindOperator, QueryFailedError, type Repository } from 'typeorm';
import {
  CreateMeasurementsBulkDto,
  MAX_BULK_READINGS,
} from '../src/measurements/dto/create-measurements-bulk.dto';
import { type CreateMeasurementDto } from '../src/measurements/dto/create-measurement.dto';
import { type MeasurementEntity } from '../src/measurements/entities/measurement.entity';
import {
  MEASUREMENT_KINDS,
  isSuspectDelta,
  isWithinBounds,
  unitFor,
} from '../src/measurements/measurement-rules';
import { MeasurementsService } from '../src/measurements/measurements.service';
import {
  diaryDateFor,
  diaryWindowFor,
  recentDiaryWindows,
} from '../src/plans/diary-date';
import { LogsService, MAX_WINDOW_DAYS } from '../src/logs/logs.service';

/// D-214 / D-216. What a health-platform sync needs from the server: a distance kind, many readings
/// in one request, a window per past day, and no 500 when two syncs collide.

type Row = Partial<MeasurementEntity>;

/// In-memory stand-in for the measurement table. Only what `MeasurementsService.record` touches.
function fakeRepo(rows: Row[] = []) {
  const matches = (row: Row, where: Record<string, unknown>) =>
    Object.entries(where).every(([key, want]) => {
      const have = row[key as keyof Row];
      if (want instanceof FindOperator && want.type === 'lessThan') {
        return (have as string) < (want.value as string);
      }
      return have === want;
    });

  const repo = {
    rows,
    /// Set to make the next `save` lose a race on the unique index, once.
    loseNextSave: false,
    saves: 0,
    findOne: ({
      where,
      order,
    }: {
      where: Record<string, unknown>;
      order?: { diaryDate: 'ASC' | 'DESC' };
    }) => {
      const found = rows.filter((r) => matches(r, where));
      if (order?.diaryDate === 'DESC') {
        found.sort((a, b) => (b.diaryDate! < a.diaryDate! ? -1 : 1));
      }
      return Promise.resolve(found[0] ?? null);
    },
    save: (row: Row) => {
      repo.saves++;
      if (repo.loseNextSave) {
        repo.loseNextSave = false;
        // What the pg driver raises when the unique index refuses a row. The winner's row is
        // already there by the time the loser is told.
        rows.push({ ...row, id: 'winner', source: 'health_connect' });
        throw new QueryFailedError('INSERT', [], {
          code: '23505',
        } as unknown as Error);
      }
      const saved = { id: row.id ?? `m${rows.length + 1}`, ...row };
      const at = rows.findIndex((r) => r.id === saved.id);
      if (at >= 0) rows[at] = saved;
      else rows.push(saved);
      return Promise.resolve(saved);
    },
  };
  return repo;
}

function serviceWith(repo: ReturnType<typeof fakeRepo>) {
  return new MeasurementsService(
    repo as unknown as Repository<MeasurementEntity>,
  );
}

const TODAY = diaryDateFor(new Date());

function reading(
  over: Partial<CreateMeasurementDto> = {},
): CreateMeasurementDto {
  return {
    kind: 'steps',
    value: 8000,
    unit: 'steps',
    source: 'health_connect',
    ...over,
  };
}

describe('distance is a kind', () => {
  it('should be part of the closed list, in metres', () => {
    expect(MEASUREMENT_KINDS).toContain('distance_m');
    expect(unitFor('distance_m')).toBe('m');
  });

  it('should accept a real day and refuse an impossible one', () => {
    expect(isWithinBounds('distance_m', 0)).toBe(true);
    expect(isWithinBounds('distance_m', 6200)).toBe(true);
    expect(isWithinBounds('distance_m', 100001)).toBe(false);
    expect(isWithinBounds('distance_m', -1)).toBe(false);
  });

  /// A long walk followed by a rest day is a genuine swing, exactly as it is for steps.
  it('should never flag a fast-changing distance as suspect', () => {
    expect(
      isSuspectDelta(
        'distance_m',
        500,
        { value: 30000, diaryDate: '2026-09-01' },
        '2026-09-02',
      ),
    ).toBe(false);
  });

  it('should refuse a distance sent in the wrong unit', async () => {
    const service = serviceWith(fakeRepo());
    await expect(
      service.record(
        1,
        reading({ kind: 'distance_m', value: 6, unit: 'kcal' }),
      ),
    ).rejects.toMatchObject({
      response: { error: { code: 'UNIT_MISMATCH' } },
    });
  });
});

describe('the bulk body', () => {
  const body = (count: number) =>
    plainToInstance(CreateMeasurementsBulkDto, {
      readings: Array.from({ length: count }, () => reading()),
    });

  it('should accept the most a 30-day backfill can send', async () => {
    expect(await validate(body(MAX_BULK_READINGS))).toHaveLength(0);
  });

  it('should refuse one more than that', async () => {
    expect(await validate(body(MAX_BULK_READINGS + 1))).not.toHaveLength(0);
  });

  it('should refuse a replace flag that is not a boolean', async () => {
    const bad = plainToInstance(CreateMeasurementsBulkDto, {
      readings: [{ ...reading(), replace_manual: 'yes' }],
    });
    expect(await validate(bad)).not.toHaveLength(0);
  });

  it('should refuse an empty batch', async () => {
    expect(await validate(body(0))).not.toHaveLength(0);
  });

  /// Nested validation is the easy part to forget: without it an unknown kind sails through the
  /// array and only fails deep in the service.
  it('should validate every reading, not just the array', async () => {
    const bad = plainToInstance(CreateMeasurementsBulkDto, {
      readings: [reading(), { ...reading(), kind: 'vo2max' }],
    });
    expect(await validate(bad)).not.toHaveLength(0);
  });
});

describe('recordMany', () => {
  it('should write every reading and answer in the order they were sent', async () => {
    const repo = fakeRepo();
    const { results } = await serviceWith(repo).recordMany(1, [
      reading(),
      reading({ kind: 'distance_m', value: 5600, unit: 'm' }),
      reading({ kind: 'energy_burned_kcal', value: 310, unit: 'kcal' }),
    ]);

    expect(results.map((r) => r.ok)).toEqual([true, true, true]);
    expect(results.map((r) => (r.ok ? r.measurement.kind : null))).toEqual([
      'steps',
      'distance_m',
      'energy_burned_kcal',
    ]);
    expect(repo.rows).toHaveLength(3);
  });

  /// One bad day must not throw away a month of good ones.
  it('should report a refused reading in its own slot and keep the rest', async () => {
    const repo = fakeRepo();
    const { results } = await serviceWith(repo).recordMany(1, [
      reading(),
      reading({ value: 250000 }),
      reading({ kind: 'distance_m', value: 5600, unit: 'm' }),
    ]);

    expect(results[0].ok).toBe(true);
    expect(results[1]).toMatchObject({
      ok: false,
      error: { code: 'VALUE_OUT_OF_RANGE' },
    });
    expect(results[1].ok ? null : results[1].error.user_message).toBeTruthy();
    expect(results[2].ok).toBe(true);
    expect(repo.rows).toHaveLength(2);
  });

  /// D-97 holds for a batch exactly as it does for one POST.
  it('should not let a device reading overwrite a hand-typed figure', async () => {
    const repo = fakeRepo([
      {
        id: 'typed',
        userId: 1,
        kind: 'steps',
        value: '8000.00',
        unit: 'steps',
        diaryDate: TODAY,
        source: 'manual',
        isSuspect: false,
      },
    ]);

    const { results } = await serviceWith(repo).recordMany(1, [
      reading({ value: 12000 }),
    ]);

    expect(results[0]).toMatchObject({
      ok: true,
      measurement: { value: 8000, source: 'manual' },
    });
    expect(repo.saves).toBe(0);
  });

  /// D-218. A tap on Sync or Connect is the person choosing the device's figure.
  it('should replace a hand-typed figure when the person asked for the device', async () => {
    const repo = fakeRepo([
      {
        id: 'typed',
        userId: 1,
        kind: 'steps',
        value: '200.00',
        unit: 'steps',
        diaryDate: TODAY,
        source: 'manual',
        isSuspect: false,
      },
    ]);

    const { results } = await serviceWith(repo).recordMany(1, [
      {
        ...reading({ value: 456, source: 'apple_health' }),
        replace_manual: true,
      },
    ]);

    expect(results[0]).toMatchObject({
      ok: true,
      measurement: { value: 456, source: 'apple_health' },
    });
    expect(repo.rows).toHaveLength(1);
  });

  it('should still refuse that replacement when the flag is false', async () => {
    const repo = fakeRepo([
      {
        id: 'typed',
        userId: 1,
        kind: 'steps',
        value: '200.00',
        unit: 'steps',
        diaryDate: TODAY,
        source: 'manual',
        isSuspect: false,
      },
    ]);

    await serviceWith(repo).recordMany(1, [
      { ...reading({ value: 456 }), replace_manual: false },
    ]);
    expect(repo.rows[0]).toMatchObject({ value: '200.00', source: 'manual' });
  });

  it('should land two readings for the same day in the order sent', async () => {
    const repo = fakeRepo();
    await serviceWith(repo).recordMany(1, [
      reading({ value: 4000 }),
      reading({ value: 9000 }),
    ]);

    expect(repo.rows).toHaveLength(1);
    expect(repo.rows[0].value).toBe('9000.00');
  });

  /// A partial answer to "the database went away" is not an answer.
  it('should fail the whole request on an error that is not a refusal', async () => {
    const repo = fakeRepo();
    repo.save = () => {
      throw new Error('connection terminated');
    };
    await expect(serviceWith(repo).recordMany(1, [reading()])).rejects.toThrow(
      'connection terminated',
    );
  });
});

describe('two syncs at once', () => {
  /// Both found no row, both inserted, one lost to the unique index. That used to be a raw 500.
  it('should retry the loser instead of failing it', async () => {
    const repo = fakeRepo();
    repo.loseNextSave = true;

    const result = await serviceWith(repo).record(1, {
      ...reading({ value: 9100 }),
      recorded_at: diaryWindowFor(TODAY).start.toISOString(),
    });

    expect(result.measurement.value).toBe(9100);
    expect(repo.saves).toBe(2);
  });

  it('should not swallow a database error that is not the race', async () => {
    const repo = fakeRepo();
    repo.save = () => {
      throw new QueryFailedError('INSERT', [], {
        code: '23502',
      } as unknown as Error);
    };
    await expect(serviceWith(repo).record(1, reading())).rejects.toBeInstanceOf(
      QueryFailedError,
    );
  });
});

describe('recentDiaryWindows', () => {
  const now = new Date('2026-09-17T06:00:00.000Z');

  it('should return one window per day, oldest first, ending today', () => {
    const windows = recentDiaryWindows(now, 3);
    expect(windows.map((w) => w.diary_date)).toEqual([
      '2026-09-15',
      '2026-09-16',
      '2026-09-17',
    ]);
  });

  /// Every boundary still comes from the one implementation (rule 4).
  it('should use exactly the windows diaryWindowFor gives', () => {
    for (const w of recentDiaryWindows(now, 30)) {
      const expected = diaryWindowFor(w.diary_date);
      expect(w.start).toEqual(expected.start);
      expect(w.end).toEqual(expected.end);
      expect(diaryDateFor(w.start)).toBe(w.diary_date);
    }
  });

  /// Consecutive windows must tile with no gap and no overlap, or a walk near 04:00 IST is
  /// counted twice or not at all.
  it('should tile the days with no gap and no overlap', () => {
    const windows = recentDiaryWindows(now, 30);
    for (let i = 1; i < windows.length; i++) {
      expect(windows[i].start).toEqual(windows[i - 1].end);
    }
  });

  it('should cross a month boundary', () => {
    const windows = recentDiaryWindows(new Date('2026-09-01T06:00:00Z'), 2);
    expect(windows.map((w) => w.diary_date)).toEqual([
      '2026-08-31',
      '2026-09-01',
    ]);
  });

  /// 02:00 IST on the 17th is still the 16th's diary day.
  it('should end on the diary day, not the calendar day', () => {
    const beforeFour = new Date('2026-09-16T20:30:00.000Z');
    const windows = recentDiaryWindows(beforeFour, 1);
    expect(windows[0].diary_date).toBe('2026-09-16');
  });
});

describe('GET /logs/windows', () => {
  const service = new LogsService(
    {} as never,
    {} as never,
    {} as never,
    {} as never,
  );

  it('should serialise windows the way a day serialises its own', () => {
    const [w] = service.windows(1);
    expect(w.diary_date).toBe(TODAY);
    expect(w.start).toBe(diaryWindowFor(TODAY).start.toISOString());
    expect(w.end).toBe(diaryWindowFor(TODAY).end.toISOString());
  });

  it('should allow a 30-day backfill plus today', () => {
    expect(service.windows(MAX_WINDOW_DAYS)).toHaveLength(31);
  });

  it('should refuse a count outside that', () => {
    expect(() => service.windows(0)).toThrow();
    expect(() => service.windows(MAX_WINDOW_DAYS + 1)).toThrow();
  });
});
