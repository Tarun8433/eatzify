import type { WorkoutEntry } from '../src/gym/gym-types';
import { musclesOf } from '../src/gym/muscles';
import {
  metFor,
  workoutEnergy,
  type EnergyRow,
} from '../src/gym/workout-energy';
import {
  estimateOneRm,
  isoWeekStart,
  raiseWorkingWeights,
  recordsOf,
  setsDone,
  streakWeeks,
  volumeKg,
} from '../src/gym/workout-records';

const bench = (
  sets: [number, number, boolean?][],
  top?: number,
): WorkoutEntry => ({
  exercise_id: '0025',
  name: 'barbell bench press',
  mode: 'reps',
  target: null,
  sets: sets.map(([w, r, done = true]) => ({ weight_kg: w, reps: r, done })),
  top_weight_kg: top,
});

describe('gym records', () => {
  it.each([
    [100, 1, 100],
    [100, 5, 116.7],
    [80, 12, 112],
    [80, 13, null],
    [0, 5, null],
    [60, 0, null],
  ])('should estimate a 1RM from %s kg × %s as %s', (w, r, expected) => {
    expect(estimateOneRm(w, r)).toBe(expected);
  });

  it('should count volume over done rep sets only', () => {
    const plank: WorkoutEntry = {
      exercise_id: '0464',
      name: 'plank',
      mode: 'time',
      target: null,
      sets: [{ seconds: 60, weight_kg: 10, done: true }],
    };
    expect(
      volumeKg([
        bench([
          [60, 8],
          [60, 8],
          [60, 8, false],
        ]),
        plank,
      ]),
    ).toBe(960);
    expect(
      setsDone([
        bench([
          [60, 8],
          [60, 8],
          [60, 8, false],
        ]),
        plank,
      ]),
    ).toBe(3);
  });

  it('should set no record on the first session of an exercise', () => {
    expect(recordsOf([bench([[60, 8]])], () => null)).toEqual([]);
  });

  it('should name a weight record when the heaviest set beats every earlier best', () => {
    const records = recordsOf([bench([[62.5, 8]])], () => ({
      weightKg: 60,
      oneRmKg: 76,
    }));
    expect(records).toEqual([
      { exercise_id: '0025', kind: 'weight', value_kg: 62.5 },
    ]);
  });

  it('should name an e1RM record only when it is not already a weight record', () => {
    const records = recordsOf([bench([[60, 10]])], () => ({
      weightKg: 60,
      oneRmKg: 76,
    }));
    expect(records).toEqual([
      {
        exercise_id: '0025',
        kind: 'e1rm',
        value_kg: 80,
        weight_kg: 60,
        reps: 10,
      },
    ]);
  });

  it('should only ever raise a working weight', () => {
    const now = raiseWorkingWeights(
      { '0025': { weight_kg: 70, date: '2026-09-01' } },
      [bench([[60, 8]])],
      '2026-09-19',
    );
    expect(now['0025'].weight_kg).toBe(70);
    const raised = raiseWorkingWeights(
      {},
      [bench([[60, 8]], 62.5)],
      '2026-09-19',
    );
    expect(raised['0025']).toEqual({ weight_kg: 62.5, date: '2026-09-19' });
  });

  it('should start an ISO week on Monday', () => {
    expect(isoWeekStart('2026-09-19')).toBe('2026-09-14');
    expect(isoWeekStart('2026-09-14')).toBe('2026-09-14');
    expect(isoWeekStart('2026-09-20')).toBe('2026-09-14');
  });

  it('should count consecutive weeks, letting this week still be empty', () => {
    const today = '2026-09-21';
    expect(streakWeeks(['2026-09-15', '2026-09-08', '2026-09-01'], today)).toBe(
      3,
    );
    expect(streakWeeks(['2026-09-21', '2026-09-15'], today)).toBe(2);
    expect(streakWeeks(['2026-09-01'], today)).toBe(0);
  });
});

describe('gym energy (D-242)', () => {
  const rows: EnergyRow[] = [
    { activity: 'strength', value: 3.5, unit: 'MET', minSpeedKmh: null },
    { activity: 'calisthenics', value: 3.8, unit: 'MET', minSpeedKmh: null },
    { activity: 'run', value: 4.8, unit: 'MET', minSpeedKmh: 0 },
    { activity: 'run', value: 8.5, unit: 'MET', minSpeedKmh: 8 },
    { activity: 'run', value: 9.3, unit: 'MET', minSpeedKmh: 9.7 },
    { activity: 'strength_set_cap', value: 3, unit: 'min', minSpeedKmh: null },
  ];
  const lifting = (sets: number) => ({
    ...bench(Array.from({ length: sets }, () => [60, 8] as [number, number])),
    energy_activity: 'strength',
  });
  const run = (minutes: number, speed: number) => ({
    exercise_id: '0685',
    name: 'run',
    mode: 'cardio' as const,
    target: null,
    sets: [{ minutes, speed_kmh: speed, done: true }],
    energy_activity: 'run',
  });

  it('should pick the highest speed band at or below the logged speed', () => {
    expect(metFor(rows, 'run', 8.5)).toBe(8.5);
    expect(metFor(rows, 'run', 12)).toBe(9.3);
    expect(metFor(rows, 'run', 3)).toBe(4.8);
    expect(metFor(rows, 'run', null)).toBe(4.8);
  });

  it('should price an unknown activity as general strength work', () => {
    expect(metFor(rows, 'underwater_basket', null)).toBe(3.5);
  });

  it('should count only the energy above rest: (MET − 1) × kg × hours', () => {
    // 30 min at 8 km/h, 70 kg: (8.5 − 1) × 70 × 0.5 = 262.5
    const result = workoutEnergy({
      entries: [run(30, 8)],
      durationSec: 1800,
      weightKg: 70,
      weightSource: 'weigh_in',
      rows,
    });
    expect(result?.kcal).toBe(263);
    expect(result?.basis).toEqual({
      weight_kg: 70,
      weight_source: 'weigh_in',
      cardio_minutes: 30,
      strength_minutes: 0,
    });
  });

  it('should price lifting for the session time, capped per done set', () => {
    // 9 sets × 3 min cap = 27 min of a 60-minute session; (3.5 − 1) × 80 × 27/60 = 90
    const result = workoutEnergy({
      entries: [lifting(9)],
      durationSec: 3600,
      weightKg: 80,
      weightSource: 'measurement',
      rows,
    });
    expect(result?.kcal).toBe(90);
    expect(result?.basis.strength_minutes).toBe(27);
  });

  it('should not count cardio minutes twice as lifting time', () => {
    // 20 min run + 12 sets in a 50-minute session: lifting gets the other 30 min (under 36 cap)
    const result = workoutEnergy({
      entries: [run(20, 8), lifting(12)],
      durationSec: 3000,
      weightKg: 70,
      weightSource: 'profile',
      rows,
    });
    expect(result?.basis).toMatchObject({
      cardio_minutes: 20,
      strength_minutes: 30,
    });
    expect(result?.kcal).toBe(
      Math.round(7.5 * 70 * (20 / 60) + 2.5 * 70 * (30 / 60)),
    );
  });

  it('should estimate nothing without a body weight', () => {
    expect(
      workoutEnergy({
        entries: [lifting(3)],
        durationSec: 600,
        weightKg: 0,
        weightSource: 'profile',
        rows,
      }),
    ).toBeNull();
  });

  it('should ignore sets that were not done', () => {
    const idle = {
      ...lifting(0),
      sets: [{ weight_kg: 60, reps: 8, done: false }],
    };
    expect(
      workoutEnergy({
        entries: [idle],
        durationSec: 1800,
        weightKg: 70,
        weightSource: 'profile',
        rows,
      })?.kcal,
    ).toBe(0);
  });
});

describe('gym muscles', () => {
  it('should fold spellings onto drawn muscles at their highest weight', () => {
    expect(
      musclesOf({
        target: 'pectorals',
        secondaryMuscles: ['triceps', 'shoulders', 'chest'],
        bodyPart: 'chest',
      }),
    ).toEqual([
      { muscle: 'chest', weight: 1 },
      { muscle: 'triceps', weight: 0.4 },
      { muscle: 'deltoids', weight: 0.4 },
    ]);
  });

  it('should fall back to the body part when nothing is drawable', () => {
    expect(
      musclesOf({
        target: 'cardiovascular system',
        secondaryMuscles: [],
        bodyPart: 'upper legs',
      }),
    ).toEqual([
      { muscle: 'quadriceps', weight: 0.4 },
      { muscle: 'hamstring', weight: 0.35 },
      { muscle: 'gluteal', weight: 0.25 },
    ]);
  });
});
