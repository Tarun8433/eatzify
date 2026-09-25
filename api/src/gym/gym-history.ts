import type { WorkingWeight, WorkoutEntry } from './gym-types';
import type { DatedSession } from './session-plan';
import { bestOneRm, topWeight, type ExerciseBests } from './workout-records';

/// Reads the workout log back per exercise: the sessions progression judges, and the bests a record
/// is set against.

export type LoggedWorkout = {
  id: string;
  diaryDate: string;
  entries: WorkoutEntry[];
};

/// Exercise id → its sessions, newest first. `workouts` must already be newest first.
/// ponytail: a full scan of the user's log per request; a per-exercise summary table is the upgrade
/// if one person's history reaches thousands of workouts.
export function sessionsByExercise(
  workouts: LoggedWorkout[],
): Map<string, DatedSession[]> {
  const byExercise = new Map<string, DatedSession[]>();
  for (const workout of workouts) {
    for (const entry of workout.entries) {
      if (!entry.sets.some((s) => s.done)) continue;
      const list = byExercise.get(entry.exercise_id) ?? [];
      list.push({
        date: workout.diaryDate,
        mode: entry.mode,
        target: entry.target,
        sets: entry.sets,
        top_weight_kg: entry.top_weight_kg ?? null,
      });
      byExercise.set(entry.exercise_id, list);
    }
  }
  return byExercise;
}

/// Null when the exercise has never been done — its first session sets the baseline, not a record.
export function bestsOf(
  sessions: DatedSession[] | undefined,
  working: WorkingWeight | undefined,
): ExerciseBests | null {
  if ((!sessions || sessions.length === 0) && !working) return null;
  let weightKg = working?.weight_kg ?? 0;
  let oneRmKg = 0;
  for (const s of sessions ?? []) {
    if (s.mode !== 'reps') continue;
    const entry = { sets: s.sets, mode: s.mode } as WorkoutEntry;
    weightKg = Math.max(weightKg, topWeight(entry), s.top_weight_kg ?? 0);
    oneRmKg = Math.max(oneRmKg, bestOneRm(s.sets)?.value ?? 0);
  }
  return { weightKg, oneRmKg };
}
