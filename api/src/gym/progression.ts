import type {
  ExerciseMode,
  Prescription,
  ProgressionRule,
  RoutineExercise,
  RoutineRule,
  WorkoutSet,
} from './gym-types';

/// What the next session of one exercise should ask for (ADR-013). Pure: the past sessions in,
/// a prescription out, with a `why` the app localises. It is arithmetic on the user's OWN logged
/// numbers — it never reads health data and never sets intensity from it.

/// Heavier compound lifts move in bigger jumps.
const BIG_STEP_KG = 5;
const SMALL_STEP_KG = 2.5;
const BIG_STEP_BODY_PARTS = new Set(['upper legs', 'lower legs', 'back']);
const TIME_STEP_SEC = 5;

/// Misses in a row before the load comes down. Greyskull resets on the first miss.
const DELOAD_AFTER: Record<Exclude<ProgressionRule, 'off'>, number> = {
  linear: 3,
  greyskull: 1,
  double: 3,
  time: 3,
};
const DELOAD_FACTOR = 0.9;
/// Greyskull's AMRAP: a last set at twice the target earns a double jump.
const DOUBLE_JUMP_AT = 2;
/// Past this many sets, a bodyweight exercise needs load or a harder variation, not more volume.
const MAX_BODYWEIGHT_SETS = 6;
const DOUBLE_RANGE_WIDTH = 2;

export const DEFAULT_REPS = 10;
export const DEFAULT_SECONDS = 45;
export const DEFAULT_MINUTES = 20;
export const DEFAULT_SPEED_KMH = 8;

const ALLOWED: Record<ExerciseMode, readonly ProgressionRule[]> = {
  reps: ['off', 'linear', 'greyskull', 'double'],
  time: ['off', 'time'],
  cardio: ['off'],
};
const DEFAULT_RULE: Record<ExerciseMode, ProgressionRule> = {
  reps: 'linear',
  time: 'off',
  cardio: 'off',
};

/// A past session of this exercise, newest first when passed as history.
export type PastSession = {
  mode: ExerciseMode;
  target: RoutineExercise | null;
  sets: WorkoutSet[];
  top_weight_kg?: number | null;
};

export function ruleFor(
  cfg: RoutineExercise,
  routineRule: RoutineRule | null,
): ProgressionRule {
  const rule = cfg.progression ?? routineRule ?? DEFAULT_RULE[cfg.mode];
  return ALLOWED[cfg.mode].includes(rule) ? rule : 'off';
}

export function stepFor(cfg: RoutineExercise, bodyPart: string): number {
  if (cfg.increment && cfg.increment > 0) return cfg.increment;
  if (cfg.mode === 'time') return TIME_STEP_SEC;
  return BIG_STEP_BODY_PARTS.has(bodyPart) ? BIG_STEP_KG : SMALL_STEP_KG;
}

export const round1 = (v: number) => Math.round(v * 10) / 10;
const toStep = (v: number, step: number) => round1(Math.round(v / step) * step);

/// 10 % off, on the step grid, always actually lower, never below one step.
export function deload(value: number, step: number): number {
  let lower = toStep(value * DELOAD_FACTOR, step);
  if (lower >= value) lower = round1(value - step);
  return Math.max(lower, step);
}

const measure = (mode: ExerciseMode, s: WorkoutSet): number =>
  s.done ? ((mode === 'time' ? s.seconds : s.reps) ?? 0) : 0;

function targetOf(session: PastSession, cfg: RoutineExercise): number {
  const t = session.target ?? cfg;
  return (session.mode === 'time' ? t.seconds : t.reps) ?? 0;
}

/// Every planned set done at or above the target it was asked for.
export function isHit(
  session: PastSession,
  cfg: RoutineExercise,
  target = targetOf(session, cfg),
): boolean {
  const planned = (session.target ?? cfg).sets;
  return (
    target > 0 &&
    session.sets.length >= planned &&
    session.sets.every((s) => measure(session.mode, s) >= target)
  );
}

export function stallsOf(history: PastSession[], cfg: RoutineExercise): number {
  let stalls = 0;
  for (const session of history) {
    if (isHit(session, cfg)) break;
    stalls += 1;
  }
  return stalls;
}

/// The load the last session was worked at: the confirmed weight, or the heaviest done set.
export function workedWeight(session: PastSession): number {
  const sets = session.sets.filter((s) => s.done).map((s) => s.weight_kg ?? 0);
  return Math.max(session.top_weight_kg ?? 0, ...sets, 0);
}

export function prescribe(input: {
  cfg: RoutineExercise;
  routineRule: RoutineRule | null;
  bodyPart: string;
  isBodyweight: boolean;
  /// Newest first; only sessions of this mode with at least one done set.
  history: PastSession[];
}): Prescription {
  const { cfg, bodyPart, isBodyweight } = input;
  const rule = ruleFor(cfg, input.routineRule);
  const history = input.history.filter(
    (h) => h.mode === cfg.mode && h.sets.some((s) => s.done),
  );
  if (rule === 'off') return { rule, kind: 'off', why: { code: 'off' } };
  if (history.length === 0)
    return { rule, kind: 'first', why: { code: 'baseline' } };

  const step = stepFor(cfg, bodyPart);
  const last = history[0];
  const stalls = stallsOf(history, cfg);

  if (rule === 'time') return timeRule(last, cfg, step, stalls);
  if (isBodyweight && workedWeight(last) <= 0)
    return bodyweightRule(rule, last, cfg);
  if (rule === 'double') return doubleRule(last, cfg, step, stalls);
  return linearRule(rule, last, cfg, step, stalls);
}

function timeRule(
  last: PastSession,
  cfg: RoutineExercise,
  step: number,
  stalls: number,
): Prescription {
  const target = targetOf(last, cfg) || (cfg.seconds ?? DEFAULT_SECONDS);
  if (isHit(last, cfg)) {
    return {
      rule: 'time',
      kind: 'up',
      seconds: target + step,
      why: { code: 'time_up', step },
    };
  }
  if (stalls >= DELOAD_AFTER.time) {
    const seconds = deload(target, step);
    return {
      rule: 'time',
      kind: 'deload',
      seconds,
      why: { code: 'time_deload', seconds },
    };
  }
  return {
    rule: 'time',
    kind: 'hold',
    seconds: target,
    why: { code: 'time_hold' },
  };
}

function bodyweightRule(
  rule: ProgressionRule,
  last: PastSession,
  cfg: RoutineExercise,
): Prescription {
  const target = targetOf(last, cfg) || (cfg.reps ?? DEFAULT_REPS);
  const sets = (last.target ?? cfg).sets;
  if (!isHit(last, cfg)) {
    return { rule, kind: 'hold', reps: target, why: { code: 'bw_hold' } };
  }
  const ceiling = cfg.reps_max ?? null;
  if (ceiling !== null && target >= ceiling) {
    if (sets >= MAX_BODYWEIGHT_SETS) {
      return { rule, kind: 'hold', reps: target, why: { code: 'bw_max' } };
    }
    const bottom = cfg.reps ?? DEFAULT_REPS;
    return {
      rule,
      kind: 'up',
      sets: sets + 1,
      reps: bottom,
      why: { code: 'bw_add_set', sets: sets + 1 },
    };
  }
  const reps = target + (cfg.per_side ? 2 : 1);
  return { rule, kind: 'up', reps, why: { code: 'bw_up_reps', reps } };
}

function doubleRule(
  last: PastSession,
  cfg: RoutineExercise,
  step: number,
  stalls: number,
): Prescription {
  const top = cfg.reps ?? last.target?.reps ?? DEFAULT_REPS;
  const bottom = Math.min(cfg.reps_min ?? top - DOUBLE_RANGE_WIDTH, top);
  const weight = workedWeight(last);

  if (isHit(last, cfg, top)) {
    const next = toStep(weight + step, step);
    return {
      rule: 'double',
      kind: 'up',
      weight_kg: next,
      reps: bottom,
      why: { code: 'double_up', step, reps: bottom },
    };
  }
  if (stalls >= DELOAD_AFTER.double) {
    const lower = deload(weight, step);
    return {
      rule: 'double',
      kind: 'deload',
      weight_kg: lower,
      reps: bottom,
      why: { code: 'double_deload', weight_kg: lower, reps: bottom },
    };
  }
  const fewest = Math.min(...last.sets.map((s) => measure('reps', s)));
  const reps = Math.min(Math.max(fewest + 1, bottom), top);
  return {
    rule: 'double',
    kind: 'hold',
    weight_kg: weight,
    reps,
    why: { code: 'double_reps', reps },
  };
}

function linearRule(
  rule: ProgressionRule,
  last: PastSession,
  cfg: RoutineExercise,
  step: number,
  stalls: number,
): Prescription {
  const weight = workedWeight(last);
  const reps = cfg.reps ?? (targetOf(last, cfg) || DEFAULT_REPS);
  const threshold = DELOAD_AFTER[rule as 'linear' | 'greyskull'];

  if (isHit(last, cfg)) {
    const lastSet = last.sets[last.sets.length - 1];
    const doubled =
      rule === 'greyskull' &&
      measure('reps', lastSet) >= DOUBLE_JUMP_AT * targetOf(last, cfg);
    const jump = doubled ? step * DOUBLE_JUMP_AT : step;
    return {
      rule,
      kind: 'up',
      weight_kg: toStep(weight + jump, step),
      reps,
      why: doubled
        ? { code: 'up_weight_double', step: jump }
        : { code: 'up_weight', step },
    };
  }
  if (stalls >= threshold) {
    const lower = deload(weight, step);
    return {
      rule,
      kind: 'deload',
      weight_kg: lower,
      reps,
      why: { code: 'deload', weight_kg: lower },
    };
  }
  return {
    rule,
    kind: 'hold',
    weight_kg: weight,
    reps,
    why: { code: 'hold', left: threshold - stalls },
  };
}
