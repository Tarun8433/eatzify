import type {
  WorkingWeight,
  WorkoutEntry,
  WorkoutRecord,
  WorkoutSet,
} from './gym-types';
import { round1 } from './progression';

/// What a finished workout adds up to: volume, personal records, estimated one-rep maxes and the
/// working weights it raises. Pure; the service stores the results on the workout row.

/// Epley stops being an estimate and starts being a guess past this many reps.
export const E1RM_MAX_REPS = 12;
const EPLEY_DIVISOR = 30;

/// Epley: w × (1 + r/30). A single rep IS the max. Null where the formula has nothing to say.
export function estimateOneRm(weightKg: number, reps: number): number | null {
  if (reps < 1 || reps > E1RM_MAX_REPS || weightKg <= 0) return null;
  if (reps === 1) return round1(weightKg);
  return round1(weightKg * (1 + reps / EPLEY_DIVISOR));
}

const doneSets = (e: WorkoutEntry): WorkoutSet[] =>
  e.sets.filter((s) => s.done);

export function setsDone(entries: WorkoutEntry[]): number {
  return entries.reduce((n, e) => n + doneSets(e).length, 0);
}

/// Σ weight × reps over done rep sets. Timed, cardio and unloaded sets move no measurable load.
export function volumeKg(entries: WorkoutEntry[]): number {
  const total = entries
    .filter((e) => e.mode === 'reps')
    .flatMap(doneSets)
    .reduce((sum, s) => sum + Math.max(s.weight_kg ?? 0, 0) * (s.reps ?? 0), 0);
  return Math.round(total * 100) / 100;
}

export function topWeight(entry: WorkoutEntry): number {
  return Math.max(0, ...doneSets(entry).map((s) => s.weight_kg ?? 0));
}

export function bestOneRm(
  sets: WorkoutSet[],
): { value: number; weight_kg: number; reps: number } | null {
  let best: { value: number; weight_kg: number; reps: number } | null = null;
  for (const s of sets) {
    if (!s.done) continue;
    const value = estimateOneRm(s.weight_kg ?? 0, s.reps ?? 0);
    if (value !== null && (best === null || value > best.value)) {
      best = { value, weight_kg: s.weight_kg ?? 0, reps: s.reps ?? 0 };
    }
  }
  return best;
}

/// Everything this exercise was ever lifted at before today — the history the record is set against.
export type ExerciseBests = { weightKg: number; oneRmKg: number };

/// A weight record beats every earlier best (confirmed working weights included). An e1RM record is
/// only named when it is not already a weight record, so one lift is never celebrated twice. The
/// first session of an exercise sets its baseline — it breaks no record, there was none.
export function recordsOf(
  entries: WorkoutEntry[],
  bestsBefore: (exerciseId: string) => ExerciseBests | null,
): WorkoutRecord[] {
  const records: WorkoutRecord[] = [];
  for (const entry of entries) {
    if (entry.mode !== 'reps') continue;
    const before = bestsBefore(entry.exercise_id);
    if (before === null) continue;
    const top = Math.max(topWeight(entry), entry.top_weight_kg ?? 0);
    if (top > before.weightKg && top > 0) {
      records.push({
        exercise_id: entry.exercise_id,
        kind: 'weight',
        value_kg: round1(top),
      });
      continue;
    }
    const oneRm = bestOneRm(entry.sets);
    if (oneRm && oneRm.value > before.oneRmKg) {
      records.push({
        exercise_id: entry.exercise_id,
        kind: 'e1rm',
        value_kg: oneRm.value,
        weight_kg: oneRm.weight_kg,
        reps: oneRm.reps,
      });
    }
  }
  return records;
}

/// Working weights only ever go up: the heaviest done set or the confirmed weight, whichever is more.
export function raiseWorkingWeights(
  current: Record<string, WorkingWeight>,
  entries: WorkoutEntry[],
  date: string,
): Record<string, WorkingWeight> {
  const next = { ...current };
  for (const entry of entries) {
    if (entry.mode !== 'reps') continue;
    const top = Math.max(topWeight(entry), entry.top_weight_kg ?? 0);
    if (top > (next[entry.exercise_id]?.weight_kg ?? 0)) {
      next[entry.exercise_id] = { weight_kg: round1(top), date };
    }
  }
  return next;
}

/// Monday of the ISO week a diary date falls in, as YYYY-MM-DD.
export function isoWeekStart(date: string): string {
  const d = new Date(`${date}T00:00:00.000Z`);
  const offset = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - offset);
  return d.toISOString().slice(0, 10);
}

/// Consecutive ISO weeks with a workout, counting back from this one. This week may still be empty —
/// Monday morning does not break a streak.
export function streakWeeks(diaryDates: string[], today: string): number {
  const weeks = new Set(diaryDates.map(isoWeekStart));
  const cursor = new Date(`${isoWeekStart(today)}T00:00:00.000Z`);
  if (!weeks.has(cursor.toISOString().slice(0, 10)))
    cursor.setUTCDate(cursor.getUTCDate() - 7);
  let streak = 0;
  while (weeks.has(cursor.toISOString().slice(0, 10))) {
    streak += 1;
    cursor.setUTCDate(cursor.getUTCDate() - 7);
  }
  return streak;
}
