import { type Repository } from 'typeorm';
import { type MeasurementEntity } from '../src/measurements/entities/measurement.entity';
import {
  foldStepsAdded,
  isWithinBounds,
  unitFor,
} from '../src/measurements/measurement-rules';
import { MeasurementsService } from '../src/measurements/measurements.service';
import { LogsService } from '../src/logs/logs.service';

/// D-221. What a person adds to, or takes off, the day's steps is kept apart from what the device
/// counted, so a sync that replaces the device's figure leaves the person's change on top of it.

type Row = Pick<MeasurementEntity, 'kind' | 'diaryDate' | 'value' | 'source'>;

const row = (
  kind: string,
  diaryDate: string,
  value: number,
  source = 'manual',
): Row => ({ kind, diaryDate, value: value.toFixed(2), source });

describe('foldStepsAdded', () => {
  it('should add the person’s steps to the device’s count', () => {
    const folded = foldStepsAdded([
      row('steps', '2026-09-17', 456, 'apple_health'),
      row('steps_added', '2026-09-17', 500),
    ]);

    expect(folded).toEqual([row('steps', '2026-09-17', 956, 'apple_health')]);
  });

  it('should take removed steps off, and never go below zero', () => {
    const folded = foldStepsAdded([
      row('steps', '2026-09-16', 3000, 'health_connect'),
      row('steps_added', '2026-09-16', -1000),
      row('steps', '2026-09-17', 200, 'health_connect'),
      row('steps_added', '2026-09-17', -500),
    ]);

    expect(folded.map((r) => Number(r.value))).toEqual([2000, 0]);
  });

  it('should make a day with only an addition a hand-typed step count', () => {
    const folded = foldStepsAdded([row('steps_added', '2026-09-17', 500)]);

    expect(folded).toEqual([row('steps', '2026-09-17', 500, 'manual')]);
  });

  it('should leave other kinds, other days and the order alone', () => {
    const rows = [
      row('weight', '2026-09-15', 70),
      row('steps', '2026-09-16', 4000, 'apple_health'),
      row('steps_added', '2026-09-17', 300),
      row('water_ml', '2026-09-17', 750),
    ];

    expect(
      foldStepsAdded(rows).map((r) => [r.kind, r.diaryDate, Number(r.value)]),
    ).toEqual([
      ['weight', '2026-09-15', 70],
      ['steps', '2026-09-16', 4000],
      ['steps', '2026-09-17', 300],
      ['water_ml', '2026-09-17', 750],
    ]);
  });

  it('should not change the rows it was given', () => {
    const device = row('steps', '2026-09-17', 456, 'apple_health');
    foldStepsAdded([device, row('steps_added', '2026-09-17', 500)]);

    expect(device.value).toBe('456.00');
  });
});

describe('steps_added as a kind', () => {
  it('should be counted in steps, either way', () => {
    expect(unitFor('steps_added')).toBe('steps');
    expect(isWithinBounds('steps_added', -2000)).toBe(true);
    expect(isWithinBounds('steps_added', 100001)).toBe(false);
    expect(isWithinBounds('steps_added', -100001)).toBe(false);
  });

  it('should refuse one a device sent', async () => {
    const service = new MeasurementsService(
      {} as Repository<MeasurementEntity>,
    );

    await expect(
      service.record(1, {
        kind: 'steps_added',
        value: 500,
        unit: 'steps',
        source: 'apple_health',
      }),
    ).rejects.toMatchObject({
      response: { error: { code: 'SOURCE_NOT_ALLOWED' } },
    });
  });
});

describe('GET /logs/day activity', () => {
  const dayWith = (activity: Row[]) =>
    new LogsService(
      { find: () => Promise.resolve([]) } as never,
      {} as never,
      { findOne: () => Promise.resolve(null) } as never,
      { find: () => Promise.resolve(activity) } as never,
    ).day(1, '2026-09-17');

  it('should send the combined count, its device, and what the person added', async () => {
    const day = await dayWith([
      row('steps', '2026-09-17', 456, 'apple_health'),
      row('steps_added', '2026-09-17', 500),
    ]);

    expect(day.activity).toEqual({
      steps: 956,
      steps_source: 'apple_health',
      steps_added: 500,
      energy_burned_kcal: null,
      workout_kcal: null,
    });
  });

  it('should still say nothing was recorded when nothing was', async () => {
    const day = await dayWith([]);

    expect(day.activity).toEqual({
      steps: null,
      steps_source: null,
      steps_added: null,
      energy_burned_kcal: null,
      workout_kcal: null,
    });
  });
});
