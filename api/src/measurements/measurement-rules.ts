/// Plausibility and trend rules for measurements.
///
/// Pure functions, no I/O — the delta rule and the moving average are the two things docs/08 and
/// docs/16 call out by name, so they are testable without a database.

/// hip / thigh / chest are optional progress metrics — the product asks for weight and waist as the
/// tracked pair and treats the rest as extras the user may or may not record.
export const MEASUREMENT_KINDS = [
  'weight',
  'waist',
  'hip',
  'thigh',
  'chest',
  'bp_sys',
  'bp_dia',
  'hba1c',
  // Manually reported activity (D-80). Kinds rather than a new module: one row per user per kind
  // per DIARY day is exactly what a day's steps is, and the 04:00 IST boundary and the overwrite
  // rule already live here.
  'steps',
  // What the person added to, or took off, the day's step count (D-221). Signed, manual only, and
  // never shown on its own: every reader sees it folded into `steps` by `foldStepsAdded`.
  'steps_added',
  'energy_burned_kcal',
  // Read from Health Connect / HealthKit alongside steps (D-214). The rest of the same walk, at
  // the same sensitivity as a step count.
  'distance_m',
  // Hydration (D-86). A kind, for the same reason activity is: one row per user per DIARY day, and
  // logging twice corrects the figure rather than doubling it.
  'water_ml',
] as const;
export type MeasurementKind = (typeof MEASUREMENT_KINDS)[number];

/// Where a reading came from. Rule 10 requires the source to be visible wherever the number is,
/// so it has to be stored — a figure that syncs itself and a figure someone typed are not the same
/// claim, and only one of them can be argued with.
export const MEASUREMENT_SOURCES = [
  'manual',
  /// iOS HealthKit.
  'apple_health',
  /// Android Health Connect. Never Google Fit — its APIs shut down at the end of 2026
  /// (CLAUDE.md rule 10).
  'health_connect',
] as const;
export type MeasurementSource = (typeof MEASUREMENT_SOURCES)[number];

/// A person's own correction outranks a device's reading for the rest of that diary day (D-97).
///
/// One row per kind per diary day means a write is an overwrite. Without this rule, someone who
/// fixes 9,500 steps to 8,000 loses the correction at the next foreground sync — silently, because
/// the sync leaves no trace of what it replaced. The reverse is not a problem: a manual entry
/// after a sync is the user disagreeing with the device on purpose, which is exactly what the
/// field is for.
///
/// [replaceManual] is the same person changing their mind the other way (D-218): they tapped
/// "Sync" or "Connect" and asked for the device's figure. A background sync never sends it.
export function canOverwrite(
  existing: MeasurementSource | null,
  incoming: MeasurementSource,
  replaceManual = false,
): boolean {
  if (existing === null) return true;
  // A person always wins, including over their own earlier entry.
  if (incoming === 'manual') return true;
  if (replaceManual) return true;
  return existing !== 'manual';
}

/// A day's steps are what the device counted plus what the person added or took off (D-221).
///
/// Kept as two rows so a sync can keep replacing the device's figure without wiping out the
/// person's change, and folded back into one `steps` row here — the single place every reader
/// (the day, the history, the coach's chart) goes through, so none of them sums it differently.
/// Order is kept; a day with only an addition becomes a manual `steps` row. Never below zero.
export function foldStepsAdded<
  T extends { kind: string; diaryDate: string; value: string },
>(rows: readonly T[]): T[] {
  const added = new Map<string, number>();
  const counted = new Set<string>();
  for (const row of rows) {
    if (row.kind === 'steps_added') added.set(row.diaryDate, Number(row.value));
    if (row.kind === 'steps') counted.add(row.diaryDate);
  }

  const total = (value: number) => Math.max(0, value).toFixed(2);
  return rows.flatMap((row): T[] => {
    if (row.kind === 'steps') {
      const extra = added.get(row.diaryDate);
      return extra === undefined
        ? [row]
        : [{ ...row, value: total(Number(row.value) + extra) }];
    }
    if (row.kind !== 'steps_added') return [row];
    // Only a day nobody's device counted keeps the addition as a row of its own.
    return counted.has(row.diaryDate)
      ? []
      : [{ ...row, kind: 'steps', value: total(Number(row.value)) }];
  });
}

/// Hard bounds. Outside these a value is refused outright, not merely flagged.
export const BOUNDS: Record<
  MeasurementKind,
  { min: number; max: number; unit: string }
> = {
  weight: { min: 20, max: 300, unit: 'kg' },
  waist: { min: 30, max: 200, unit: 'cm' },
  hip: { min: 40, max: 200, unit: 'cm' },
  thigh: { min: 20, max: 120, unit: 'cm' },
  chest: { min: 40, max: 200, unit: 'cm' },
  bp_sys: { min: 60, max: 260, unit: 'mmHg' },
  bp_dia: { min: 30, max: 200, unit: 'mmHg' },
  hba1c: { min: 3, max: 20, unit: '%' },
  // A step count, not a distance. 100k is past any real day and well past a plausible typo.
  steps: { min: 0, max: 100000, unit: 'steps' },
  // Negative is taking steps off: the watch counted a bus ride.
  steps_added: { min: -100000, max: 100000, unit: 'steps' },
  // The upper bound is a hard day's endurance work, not a ceiling on anyone's ambition.
  energy_burned_kcal: { min: 0, max: 8000, unit: 'kcal' },
  // 100 km: past an ultramarathon, and the same ceiling steps uses for the same reason.
  distance_m: { min: 0, max: 100000, unit: 'm' },
  // 10 litres is past what anyone drinks in a day and well past hyponatraemia risk; the rule pack's
  // own ceiling is 4 litres, and this is only the "that cannot be a real number" bound.
  water_ml: { min: 0, max: 10000, unit: 'ml' },
};

/// Every unit any kind is measured in, derived from BOUNDS rather than listed again (D-80).
///
/// It was a second hardcoded list in the DTO, so adding a kind passed every check here and then
/// 422'd at the boundary on a unit nobody had remembered to allow.
export const MEASUREMENT_UNITS = [
  ...new Set(Object.values(BOUNDS).map((b) => b.unit)),
];

/// The unit a kind is measured in. A weight in steps is not a weight.
export function unitFor(kind: MeasurementKind): string {
  return BOUNDS[kind].unit;
}

/// A real body weight does not move faster than this. docs/16's worked example is a 30 kg jump in
/// one day, which must be flagged rather than believed.
const MAX_DAILY_DELTA: Partial<Record<MeasurementKind, number>> = {
  weight: 3,
  waist: 5,
  hip: 5,
  thigh: 4,
  chest: 5,
  // Deliberately absent: steps and energy burned. A rest day after a marathon is a real 40,000-step
  // swing, and flagging it as suspect would mean excluding a true reading (docs/16).
};

export const MOVING_AVERAGE_DAYS = 7;

export function isWithinBounds(kind: MeasurementKind, value: number): boolean {
  const bound = BOUNDS[kind];
  return value >= bound.min && value <= bound.max;
}

/// True when the change from the previous reading is too fast to be real.
///
/// Divided by the gap in days, so a 4 kg change over three weeks is normal while the same change
/// overnight is not. No previous reading means nothing to compare against — a first entry is never
/// suspect, however unusual, because there is no delta to judge it by.
export function isSuspectDelta(
  kind: MeasurementKind,
  value: number,
  previous: { value: number; diaryDate: string } | null,
  diaryDate: string,
): boolean {
  const limit = MAX_DAILY_DELTA[kind];
  if (limit === undefined || previous === null) return false;

  const days = Math.max(1, daysBetween(previous.diaryDate, diaryDate));
  return Math.abs(value - previous.value) / days > limit;
}

export function daysBetween(from: string, to: string): number {
  const ms = Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`);
  return Math.round(ms / 86_400_000);
}

/// docs/16: the "change" readout comes from the moving average, NEVER from min/max — that is
/// exactly how the old build produced a "−30.0 kg" change from two noisy readings. Suspect rows are
/// excluded before averaging.
export function movingAverage(
  points: readonly { value: number; isSuspect: boolean }[],
  window = MOVING_AVERAGE_DAYS,
): number | null {
  const usable = points.filter((p) => !p.isSuspect).slice(-window);
  if (usable.length === 0) return null;

  const total = usable.reduce((sum, p) => sum + p.value, 0);
  return Math.round((total / usable.length) * 100) / 100;
}

/// Change between the oldest and newest moving averages, or null when there is not enough data.
/// Returning null is deliberate: a single reading has no trend, and inventing one from it is the
/// defect docs/15 recorded.
export function trendChange(
  points: readonly { value: number; isSuspect: boolean }[],
): number | null {
  const usable = points.filter((p) => !p.isSuspect);
  if (usable.length < 2) return null;

  const half = Math.max(1, Math.floor(usable.length / 2));
  const earlier = movingAverage(usable.slice(0, half), half);
  const later = movingAverage(usable.slice(-half), half);
  if (earlier === null || later === null) return null;

  return Math.round((later - earlier) * 100) / 100;
}

/// `trendChange` over only the readings from the last [days] diary days, counted back from the
/// newest reading (docs/21 §3). Same moving-average discipline, same nulls: a window with fewer
/// than two usable readings has no trend, and inventing one from it is the docs/15 defect again.
export function windowedTrendChange(
  points: readonly { value: number; isSuspect: boolean; diaryDate: string }[],
  days: number,
): number | null {
  if (points.length === 0) return null;

  const newest = new Date(points[points.length - 1].diaryDate);
  newest.setDate(newest.getDate() - days);
  const cutoff = newest.toISOString().slice(0, 10);

  return trendChange(points.filter((p) => p.diaryDate >= cutoff));
}
