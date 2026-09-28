import type { WorkoutSet } from './gym-types';
import { BODY_MUSCLES, type BodyMuscle, type MuscleShare } from './muscles';

/// The Stats tab's arithmetic, pure. Nothing here scores a person: a muscle not trained is listed
/// neutrally ("not trained in this period"), never marked as missed (docs/05 §6).

const MUSCLE_LEVELS = 4;
const HEATMAP_LEVELS = [0.25, 0.5, 0.75] as const;
export const HEATMAP_WEEKS = 53;
const DAYS_PER_WEEK = 7;
/// RIR ≤ 3 is a hard set; RPE is the same judgement on a 10-point scale (RIR = 10 − RPE).
export const HARD_RIR = 3;
const RPE_TOP = 10;
/// Fewer rated sets than this and an average is noise.
export const MIN_RATED = 5;
const MIN_RATED_PER_WEEK = 2;
const RIR_BUCKETS = ['0', '1', '2', '3', '4+'] as const;

export function rirOf(s: WorkoutSet): number | null {
  if (s.rir != null) return s.rir;
  if (s.rpe != null) return RPE_TOP - s.rpe;
  return null;
}
export const isHard = (s: WorkoutSet) => {
  const rir = rirOf(s);
  return rir !== null && rir <= HARD_RIR;
};

export type MuscleLevel = { muscle: BodyMuscle; sets: number; level: number };

/// Load per muscle = Σ share × done sets ("effective sets"). Kilograms are deliberately not used:
/// 100 kg of leg press and 10 kg of curls are not ten times apart in work.
export function muscleLevels(
  entries: { muscles: MuscleShare[]; sets: WorkoutSet[] }[],
  hardOnly = false,
): MuscleLevel[] {
  const load = new Map<BodyMuscle, number>();
  for (const entry of entries) {
    const count = entry.sets.filter(
      (s) => s.done && (!hardOnly || isHard(s)),
    ).length;
    if (count === 0) continue;
    for (const { muscle, weight } of entry.muscles) {
      load.set(muscle, (load.get(muscle) ?? 0) + weight * count);
    }
  }
  const max = Math.max(0, ...load.values());
  return BODY_MUSCLES.map((muscle) => {
    const sets = Math.round((load.get(muscle) ?? 0) * 10) / 10;
    const level =
      sets > 0
        ? Math.min(
            MUSCLE_LEVELS,
            Math.max(1, Math.ceil((sets / max) * MUSCLE_LEVELS)),
          )
        : 0;
    return { muscle, sets, level };
  });
}

const addDays = (date: string, days: number) => {
  const d = new Date(`${date}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};
export const mondayOf = (date: string) => {
  const d = new Date(`${date}T00:00:00.000Z`);
  return addDays(date, -((d.getUTCDay() + 6) % DAYS_PER_WEEK));
};
export { addDays };

const percentile = (sorted: number[], q: number) =>
  sorted[Math.floor(q * (sorted.length - 1))];

export type HeatCell = {
  date: string;
  minutes: number;
  workouts: number;
  level: number;
  future: boolean;
};

/// 53 Monday-first weeks ending with today's week, shaded by minutes trained against the person's
/// OWN quartiles — a 20-minute day is dark for someone who trains 20 minutes.
export function heatmap(
  days: Map<string, { minutes: number; workouts: number }>,
  today: string,
): HeatCell[][] {
  const trained = [...days.values()]
    .map((d) => d.minutes)
    .filter((m) => m > 0)
    .sort((a, b) => a - b);
  const cuts =
    trained.length > 0 ? HEATMAP_LEVELS.map((q) => percentile(trained, q)) : [];
  const levelOf = (d: { minutes: number; workouts: number } | undefined) => {
    if (!d || d.workouts === 0) return 0;
    if (d.minutes <= 0 || cuts.length === 0) return 1;
    return 1 + cuts.filter((c) => d.minutes >= c).length;
  };
  const start = addDays(mondayOf(today), -(HEATMAP_WEEKS - 1) * DAYS_PER_WEEK);
  return Array.from({ length: HEATMAP_WEEKS }, (_, w) =>
    Array.from({ length: DAYS_PER_WEEK }, (_, d) => {
      const date = addDays(start, w * DAYS_PER_WEEK + d);
      const day = days.get(date);
      return {
        date,
        minutes: Math.round(day?.minutes ?? 0),
        workouts: day?.workouts ?? 0,
        level: levelOf(day),
        future: date > today,
      };
    }),
  );
}

export type RatedSet = { date: string; set: WorkoutSet };
export type EffortSummary = {
  scale: 'rir' | 'rpe';
  rated: number;
  finished: number;
  average: number | null;
  hard_pct: number | null;
  weekly: { week_start: string; average: number }[];
  histogram: { bucket: (typeof RIR_BUCKETS)[number]; count: number }[];
};

/// Stats read in RIR and are shown back in the scale the person uses today.
export function effortSummary(
  sets: RatedSet[],
  scale: 'rir' | 'rpe',
): EffortSummary {
  const done = sets.filter((r) => r.set.done);
  const rated = done
    .map((r) => ({ date: r.date, rir: rirOf(r.set) }))
    .filter((r): r is { date: string; rir: number } => r.rir !== null);
  const show = (rir: number) =>
    Math.round((scale === 'rpe' ? RPE_TOP - rir : rir) * 10) / 10;
  const enough = rated.length >= MIN_RATED;

  const byWeek = new Map<string, number[]>();
  rated.forEach((r) =>
    byWeek.set(mondayOf(r.date), [
      ...(byWeek.get(mondayOf(r.date)) ?? []),
      r.rir,
    ]),
  );
  const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;

  return {
    scale,
    rated: rated.length,
    finished: done.length,
    average: enough ? show(mean(rated.map((r) => r.rir))) : null,
    hard_pct: enough
      ? Math.round(
          (rated.filter((r) => r.rir <= HARD_RIR).length / rated.length) * 100,
        )
      : null,
    weekly: [...byWeek]
      .filter(([, xs]) => xs.length >= MIN_RATED_PER_WEEK)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([week_start, xs]) => ({ week_start, average: show(mean(xs)) })),
    histogram: RIR_BUCKETS.map((bucket, i) => ({
      bucket,
      count: rated.filter((r) =>
        i === RIR_BUCKETS.length - 1 ? r.rir >= i : Math.floor(r.rir) === i,
      ).length,
    })),
  };
}
