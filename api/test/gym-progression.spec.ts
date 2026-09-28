import type { RoutineExercise, WorkoutSet } from '../src/gym/gym-types';
import {
  deload,
  prescribe,
  ruleFor,
  stallsOf,
  stepFor,
  type PastSession,
} from '../src/gym/progression';
import { applyPrescription, planEntry, prefill } from '../src/gym/session-plan';

const cfg = (over: Partial<RoutineExercise> = {}): RoutineExercise => ({
  exercise_id: '0025',
  mode: 'reps',
  sets: 3,
  reps: 8,
  weight_kg: 60,
  ...over,
});
const reps = (weight: number, ...r: number[]): WorkoutSet[] =>
  r.map((n) => ({ weight_kg: weight, reps: n, done: true }));
const session = (
  sets: WorkoutSet[],
  target: RoutineExercise | null = cfg(),
): PastSession => ({
  mode: target?.mode ?? 'reps',
  target,
  sets,
});
const hit = session(reps(60, 8, 8, 8));
const miss = session(reps(60, 8, 8, 6));
const chest = { bodyPart: 'chest', isBodyweight: false };

describe('gym progression', () => {
  describe('which rule applies', () => {
    it('should follow the exercise override, then the routine, then the mode default', () => {
      expect(ruleFor(cfg({ progression: 'double' }), 'linear')).toBe('double');
      expect(ruleFor(cfg(), 'greyskull')).toBe('greyskull');
      expect(ruleFor(cfg(), null)).toBe('linear');
      expect(ruleFor(cfg({ mode: 'time' }), null)).toBe('off');
    });

    it('should turn a rule the mode cannot use into off', () => {
      expect(ruleFor(cfg({ mode: 'time' }), 'linear')).toBe('off');
      expect(ruleFor(cfg({ mode: 'cardio' }), 'linear')).toBe('off');
      expect(ruleFor(cfg({ mode: 'reps', progression: 'time' }), null)).toBe(
        'off',
      );
    });
  });

  describe('step sizes', () => {
    it.each([
      ['upper legs', 5],
      ['back', 5],
      ['chest', 2.5],
      ['upper arms', 2.5],
    ])('should step %s by %s kg', (part, step) => {
      expect(stepFor(cfg(), part)).toBe(step);
    });

    it('should prefer the exercise increment and step timed holds by 5 s', () => {
      expect(stepFor(cfg({ increment: 1.25 }), 'chest')).toBe(1.25);
      expect(stepFor(cfg({ mode: 'time' }), 'waist')).toBe(5);
    });
  });

  describe('deload', () => {
    it.each([
      [100, 2.5, 90],
      [60, 2.5, 55],
      [20, 5, 15],
      [2.5, 2.5, 2.5],
    ])('should take %s kg on a %s step down to %s', (value, step, expected) => {
      expect(deload(value, step)).toBe(expected);
    });
  });

  it('should count misses in a row back from the latest session', () => {
    expect(stallsOf([miss, miss, hit, miss], cfg())).toBe(2);
    expect(stallsOf([hit, miss], cfg())).toBe(0);
  });

  describe('linear', () => {
    const run = (history: PastSession[]) =>
      prescribe({ cfg: cfg(), routineRule: 'linear', ...chest, history });

    it('should set a baseline when there is no history', () => {
      expect(run([])).toMatchObject({
        kind: 'first',
        why: { code: 'baseline' },
      });
    });

    it('should add one step after every set hit', () => {
      expect(run([hit])).toMatchObject({
        kind: 'up',
        weight_kg: 62.5,
        reps: 8,
        why: { code: 'up_weight', step: 2.5 },
      });
    });

    it('should hold after a miss, and say how many misses are left', () => {
      expect(run([miss])).toMatchObject({
        kind: 'hold',
        weight_kg: 60,
        why: { code: 'hold', left: 2 },
      });
    });

    it('should deload after the third miss in a row', () => {
      expect(run([miss, miss, miss])).toMatchObject({
        kind: 'deload',
        weight_kg: 55,
        why: { code: 'deload' },
      });
    });

    it('should treat an unchecked set as zero reps', () => {
      const unchecked = session([
        ...reps(60, 8, 8),
        { weight_kg: 60, reps: 8, done: false },
      ]);
      expect(run([unchecked])).toMatchObject({ kind: 'hold' });
    });

    it("should judge a session against what it prescribed, not today's routine", () => {
      const prescribed12 = session(reps(60, 10, 10, 10), cfg({ reps: 12 }));
      expect(run([prescribed12])).toMatchObject({ kind: 'hold' });
    });
  });

  describe('greyskull', () => {
    const run = (history: PastSession[]) =>
      prescribe({
        cfg: cfg({ reps: 5 }),
        routineRule: 'greyskull',
        ...chest,
        history,
      });

    it('should double the jump when the AMRAP set reaches twice the target', () => {
      const amrap = session(reps(60, 5, 5, 10), cfg({ reps: 5 }));
      expect(run([amrap])).toMatchObject({
        weight_kg: 65,
        why: { code: 'up_weight_double', step: 5 },
      });
    });

    it('should deload on the first miss', () => {
      const missed = session(reps(60, 5, 5, 3), cfg({ reps: 5 }));
      expect(run([missed])).toMatchObject({ kind: 'deload', weight_kg: 55 });
    });
  });

  describe('double progression', () => {
    const range = cfg({ reps: 10, reps_min: 8, progression: 'double' });
    const run = (history: PastSession[]) =>
      prescribe({ cfg: range, routineRule: null, ...chest, history });

    it('should add weight and drop to the bottom once every set reaches the top', () => {
      const top = session(reps(60, 10, 10, 10), range);
      expect(run([top])).toMatchObject({
        kind: 'up',
        weight_kg: 62.5,
        reps: 8,
        why: { code: 'double_up' },
      });
    });

    it('should aim one rep above the weakest set, inside the range', () => {
      const climbing = session(reps(60, 9, 9, 8), cfg({ reps: 9 }));
      expect(run([climbing])).toMatchObject({
        kind: 'hold',
        weight_kg: 60,
        reps: 9,
        why: { code: 'double_reps', reps: 9 },
      });
    });
  });

  describe('bodyweight', () => {
    const pushUp = cfg({ exercise_id: '0662', weight_kg: 0, reps: 12 });
    const run = (history: PastSession[], over: Partial<RoutineExercise> = {}) =>
      prescribe({
        cfg: { ...pushUp, ...over },
        routineRule: 'linear',
        bodyPart: 'chest',
        isBodyweight: true,
        history,
      });
    const done = (r: number, sets = 3, target = pushUp) =>
      session(
        Array.from({ length: sets }, () => ({
          weight_kg: 0,
          reps: r,
          done: true,
        })),
        target,
      );

    it('should add a rep, not weight', () => {
      expect(run([done(12)])).toMatchObject({
        kind: 'up',
        reps: 13,
        why: { code: 'bw_up_reps' },
      });
    });

    it('should add two reps when reps are counted per side', () => {
      expect(run([done(12)], { per_side: true })).toMatchObject({ reps: 14 });
    });

    it('should add a set and return to the bottom at the rep ceiling', () => {
      const atCeiling = cfg({ ...pushUp, reps: 15 });
      expect(
        run([done(15, 3, atCeiling)], { reps_max: 15, reps: 10 }),
      ).toMatchObject({
        sets: 4,
        reps: 10,
        why: { code: 'bw_add_set', sets: 4 },
      });
    });

    it('should stop adding sets at six and say to load it instead', () => {
      const six = cfg({ ...pushUp, reps: 15, sets: 6 });
      expect(run([done(15, 6, six)], { reps_max: 15 })).toMatchObject({
        kind: 'hold',
        why: { code: 'bw_max' },
      });
    });

    it('should follow the weight rule once added weight was used', () => {
      const loaded = session(reps(10, 12, 12, 12), pushUp);
      expect(run([loaded])).toMatchObject({ kind: 'up', weight_kg: 12.5 });
    });
  });

  describe('timed', () => {
    const plank = cfg({
      exercise_id: '0464',
      mode: 'time',
      seconds: 45,
      progression: 'time',
    });
    const held = (s: number) =>
      ({
        mode: 'time',
        target: plank,
        sets: [1, 2, 3].map(() => ({ seconds: s, done: true })),
      }) as PastSession;
    const run = (history: PastSession[]) =>
      prescribe({
        cfg: plank,
        routineRule: null,
        bodyPart: 'waist',
        isBodyweight: true,
        history,
      });

    it('should add five seconds after a full hold', () => {
      expect(run([held(45)])).toMatchObject({ kind: 'up', seconds: 50 });
    });

    it('should shorten the hold after three short sessions', () => {
      expect(run([held(30), held(30), held(30)])).toMatchObject({
        kind: 'deload',
        seconds: 40,
      });
    });
  });

  it('should never progress cardio', () => {
    const treadmill = cfg({ mode: 'cardio', minutes: 20, speed_kmh: 6 });
    const past: PastSession = {
      mode: 'cardio',
      target: treadmill,
      sets: [{ minutes: 20, speed_kmh: 6, done: true }],
    };
    expect(
      prescribe({
        cfg: treadmill,
        routineRule: 'linear',
        ...chest,
        history: [past],
      }),
    ).toMatchObject({ kind: 'off' });
  });
});

describe('gym session plan', () => {
  it('should copy last time set by set, falling back to its last set', () => {
    const last = session(reps(50, 10, 9));
    expect(prefill(cfg({ sets: 3 }), last, 0).map((s) => s.reps)).toEqual([
      10, 9, 9,
    ]);
  });

  it('should prefer the confirmed working weight', () => {
    expect(prefill(cfg(), session(reps(50, 8)), 57.5)[0].weight_kg).toBe(57.5);
  });

  it('should start a new exercise from its routine numbers', () => {
    expect(
      prefill(
        cfg({ mode: 'cardio', sets: 1, minutes: 25, speed_kmh: 9 }),
        null,
        0,
      ),
    ).toEqual([{ minutes: 25, speed_kmh: 9, done: false }]);
  });

  it('should only add sets and only touch sets not yet done', () => {
    const sets = [
      { weight_kg: 50, reps: 8, done: true },
      { weight_kg: 50, reps: 8, done: false },
    ];
    const out = applyPrescription(sets, {
      rule: 'linear',
      kind: 'up',
      weight_kg: 52.5,
      sets: 3,
      why: { code: 'up_weight', step: 2.5 },
    });
    expect(out.map((s) => s.weight_kg)).toEqual([50, 52.5, 52.5]);
  });

  it('should record what it prescribed as the session target', () => {
    const entry = planEntry({
      cfg: cfg(),
      routineRule: 'linear',
      exercise: {
        name: 'barbell bench press',
        bodyPart: 'chest',
        isBodyweight: false,
      },
      history: [{ ...hit, date: '2026-09-15' }],
      workingWeightKg: 60,
      bestWeightKg: 60,
    });
    expect(entry.target).toMatchObject({ weight_kg: 62.5, reps: 8, sets: 3 });
    expect(entry.sets.every((s) => s.weight_kg === 62.5)).toBe(true);
    expect(entry.last?.date).toBe('2026-09-15');
  });
});
