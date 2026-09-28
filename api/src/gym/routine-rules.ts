import type { RoutineExercise } from './gym-types';

/// A superset is adjacent exercises sharing an id. After a remove or reorder, an id left with no
/// neighbour means nothing, so it is cleared rather than left to confuse the workout screen.
export function cleanSupersets(list: RoutineExercise[]): RoutineExercise[] {
  return list.map((e, i) => {
    if (!e.superset) return { ...e, superset: null };
    const paired =
      list[i - 1]?.superset === e.superset ||
      list[i + 1]?.superset === e.superset;
    return paired ? e : { ...e, superset: null };
  });
}

/// Per-side reps are a total of both sides, so they are always even. A rep ceiling below the reps
/// asked for would be reached before it started.
export function normaliseExercise(e: RoutineExercise): RoutineExercise {
  const perSide = e.mode === 'reps' && e.per_side === true;
  const reps =
    e.reps != null && perSide && e.reps % 2 === 1 ? e.reps + 1 : e.reps;
  const repsMax =
    e.reps_max != null && reps != null
      ? Math.max(e.reps_max, reps)
      : e.reps_max;
  return { ...e, per_side: perSide || null, reps, reps_max: repsMax };
}
