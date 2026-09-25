import type {
  Prescription,
  RoutineExercise,
  RoutineRule,
  WorkoutSet,
} from './gym-types';
import type { MuscleShare } from './muscles';
import {
  DEFAULT_MINUTES,
  DEFAULT_REPS,
  DEFAULT_SECONDS,
  DEFAULT_SPEED_KMH,
  prescribe,
  type PastSession,
} from './progression';

/// A session's opening numbers for one exercise: last time's sets, then the progression rule on
/// top. Built on the server and sent ahead in `GET /gym`, so a workout can start with no signal.

export type DatedSession = PastSession & { date: string };

export type SessionEntry = {
  exercise_id: string;
  name: string;
  mode: RoutineExercise['mode'];
  body_part: string;
  is_bodyweight: boolean;
  per_side: boolean;
  superset: string | null;
  /// What this session asks for — stored with the workout, and what the next one is judged against.
  target: RoutineExercise;
  sets: WorkoutSet[];
  prescription: Prescription;
  last: { date: string; sets: WorkoutSet[] } | null;
  best_weight_kg: number | null;
  /// Null unless media is licensed and served (D-243).
  media_url: string | null;
  /// Enough to draw and read the exercise mid-workout without another round trip — the workout
  /// screen has to work with no signal.
  muscles: MuscleShare[];
  steps: { en: string[]; hi: string[] };
};

export type PlanExercise = {
  name: string;
  bodyPart: string;
  isBodyweight: boolean;
  mediaUrl?: string | null;
  muscles?: MuscleShare[];
  steps?: { en: string[]; hi: string[] };
};

export function planEntry(input: {
  cfg: RoutineExercise;
  routineRule: RoutineRule | null;
  exercise: PlanExercise;
  /// This exercise's sessions, newest first.
  history: DatedSession[];
  workingWeightKg: number;
  bestWeightKg: number | null;
}): SessionEntry {
  const { cfg, exercise } = input;
  const isBodyweight = cfg.bodyweight ?? exercise.isBodyweight;
  const history = input.history.filter(
    (h) => h.mode === cfg.mode && h.sets.some((s) => s.done),
  );
  const last = history[0] ?? null;
  const prescription = prescribe({
    cfg,
    routineRule: input.routineRule,
    bodyPart: exercise.bodyPart,
    isBodyweight,
    history,
  });

  const sets = applyPrescription(
    prefill(cfg, last, input.workingWeightKg),
    prescription,
  );
  const target: RoutineExercise = {
    ...cfg,
    sets: sets.length,
    ...(prescription.reps !== undefined && { reps: prescription.reps }),
    ...(prescription.weight_kg !== undefined && {
      weight_kg: prescription.weight_kg,
    }),
    ...(prescription.seconds !== undefined && {
      seconds: prescription.seconds,
    }),
  };

  return {
    exercise_id: cfg.exercise_id,
    name: exercise.name,
    mode: cfg.mode,
    body_part: exercise.bodyPart,
    is_bodyweight: isBodyweight,
    per_side: cfg.per_side ?? false,
    superset: cfg.superset ?? null,
    target,
    sets,
    prescription,
    last: last ? { date: last.date, sets: last.sets } : null,
    best_weight_kg: input.bestWeightKg,
    media_url: exercise.mediaUrl ?? null,
    muscles: exercise.muscles ?? [],
    steps: exercise.steps ?? { en: [], hi: [] },
  };
}

/// Set i copies set i of last time (or its last set); a confirmed working weight beats both.
export function prefill(
  cfg: RoutineExercise,
  last: PastSession | null,
  workingWeightKg: number,
): WorkoutSet[] {
  const previous = (i: number) =>
    last?.sets[i] ?? last?.sets[last.sets.length - 1];
  return Array.from({ length: Math.max(cfg.sets, 1) }, (_, i) => {
    const p = previous(i);
    switch (cfg.mode) {
      case 'cardio':
        return {
          minutes: p?.minutes ?? cfg.minutes ?? DEFAULT_MINUTES,
          speed_kmh: p?.speed_kmh ?? cfg.speed_kmh ?? DEFAULT_SPEED_KMH,
          done: false,
        };
      case 'time':
        return {
          seconds: p?.seconds ?? cfg.seconds ?? DEFAULT_SECONDS,
          weight_kg: p?.weight_kg ?? cfg.weight_kg ?? 0,
          done: false,
        };
      default:
        return {
          weight_kg:
            workingWeightKg > 0
              ? workingWeightKg
              : (p?.weight_kg ?? cfg.weight_kg ?? 0),
          reps: p?.reps ?? cfg.reps ?? DEFAULT_REPS,
          done: false,
        };
    }
  });
}

/// The rule only ever touches sets not yet done, and only ever adds sets.
export function applyPrescription(
  sets: WorkoutSet[],
  p: Prescription,
): WorkoutSet[] {
  const grown = [...sets];
  while (p.sets !== undefined && grown.length < p.sets)
    grown.push({ ...grown[grown.length - 1] });
  return grown.map((s) =>
    s.done
      ? s
      : {
          ...s,
          ...(p.weight_kg !== undefined && { weight_kg: p.weight_kg }),
          ...(p.reps !== undefined && { reps: p.reps }),
          ...(p.seconds !== undefined && { seconds: p.seconds }),
        },
  );
}
