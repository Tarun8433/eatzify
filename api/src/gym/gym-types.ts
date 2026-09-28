/// The Gym section's wire and storage shapes (ADR-013). Routine exercises and workout entries are
/// stored in jsonb exactly as they travel, snake_case, so a view is a pass-through rather than a
/// second mapping to keep in step.

export const EXERCISE_MODES = ['reps', 'time', 'cardio'] as const;
export type ExerciseMode = (typeof EXERCISE_MODES)[number];

/// 'time' only applies to timed exercises; a routine-wide rule is one of the first four.
export const PROGRESSION_RULES = [
  'off',
  'linear',
  'greyskull',
  'double',
  'time',
] as const;
export type ProgressionRule = (typeof PROGRESSION_RULES)[number];
export const ROUTINE_RULES = ['off', 'linear', 'greyskull', 'double'] as const;
export type RoutineRule = (typeof ROUTINE_RULES)[number];

/// Names, not glyphs: the app maps each to one of its own icons.
export const ROUTINE_ICONS = [
  'strength',
  'gymnastics',
  'body',
  'martial',
  'rowing',
  'run',
  'walk',
  'bike',
  'heart',
  'fire',
  'timer',
  'yoga',
] as const;

export const EFFORT_SCALES = ['off', 'rir', 'rpe'] as const;
export const BODY_FIGURES = ['male', 'female'] as const;
export const REST_OPTIONS_SEC = [60, 90, 120, 150, 180] as const;

/// One exercise as a routine prescribes it. Only the fields its mode uses are meaningful.
export type RoutineExercise = {
  exercise_id: string;
  mode: ExerciseMode;
  sets: number;
  reps?: number | null;
  /// Added weight when the exercise is done at bodyweight.
  weight_kg?: number | null;
  seconds?: number | null;
  minutes?: number | null;
  speed_kmh?: number | null;
  /// Overrides the library's own bodyweight flag.
  bodyweight?: boolean | null;
  /// Reps are the total of both sides; the app shows the split.
  per_side?: boolean | null;
  /// Overrides the routine's rule for this exercise.
  progression?: ProgressionRule | null;
  increment?: number | null;
  /// Bottom of the range for double progression.
  reps_min?: number | null;
  /// The rep ceiling at which a bodyweight exercise gains a set instead of a rep.
  reps_max?: number | null;
  /// Adjacent exercises sharing an id are done back to back, resting after the group.
  superset?: string | null;
};

export type WorkoutSet = {
  weight_kg?: number | null;
  reps?: number | null;
  seconds?: number | null;
  minutes?: number | null;
  speed_kmh?: number | null;
  done: boolean;
  /// Reps in reserve / rate of perceived exertion — each set keeps the scale it was logged in.
  rir?: number | null;
  rpe?: number | null;
};

export type WorkoutEntry = {
  exercise_id: string;
  /// Stamped by the server at save, so history reads even after a custom exercise is deleted.
  name: string;
  mode: ExerciseMode;
  /// What the session prescribed, which is what the next session judges a "hit" against.
  target: RoutineExercise | null;
  sets: WorkoutSet[];
  /// The working weight the user confirmed after the last set.
  top_weight_kg?: number | null;
  superset?: string | null;
};

export type WorkingWeight = { weight_kg: number; date: string };

export type DayOverride = number | 'rest';

export type WorkoutRecord = {
  exercise_id: string;
  /// 'weight' — heavier than every earlier best; 'e1rm' — a better estimated one-rep max that is
  /// not already a weight record.
  kind: 'weight' | 'e1rm';
  value_kg: number;
  weight_kg?: number;
  reps?: number;
};

export type EnergyBasis = {
  weight_kg: number;
  weight_source: 'weigh_in' | 'measurement' | 'profile';
  cardio_minutes: number;
  strength_minutes: number;
};

/// Why a session's numbers are what they are. A code the app localises, never prose from here.
export type PrescriptionWhy =
  | { code: 'baseline' }
  | { code: 'off' }
  | { code: 'up_weight'; step: number }
  | { code: 'up_weight_double'; step: number }
  | { code: 'hold'; left: number }
  | { code: 'deload'; weight_kg: number }
  | { code: 'double_up'; step: number; reps: number }
  | { code: 'double_reps'; reps: number }
  | { code: 'double_deload'; weight_kg: number; reps: number }
  | { code: 'bw_up_reps'; reps: number }
  | { code: 'bw_add_set'; sets: number }
  | { code: 'bw_max' }
  | { code: 'bw_hold' }
  | { code: 'time_up'; step: number }
  | { code: 'time_hold' }
  | { code: 'time_deload'; seconds: number };

export type Prescription = {
  rule: ProgressionRule;
  kind: 'first' | 'up' | 'hold' | 'deload' | 'off';
  weight_kg?: number;
  reps?: number;
  seconds?: number;
  sets?: number;
  why: PrescriptionWhy;
};
