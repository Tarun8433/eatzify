/// Calories from walking, from the person's own weight and what their phone measured (D-256, D-268).
///
/// Pure, no I/O. The ONE place the app's walking calories are worked out: Home's "burned", the
/// Progress and coach charts, and the "per 1,000 steps" rate all come from here.
///
/// ACSM walking equation, per diary day:
///   VO2 (ml/kg/min) = 3.5 + 0.1 × speed (m/min) + 1.8 × speed × grade
///   MET             = VO2 / 3.5
///   kcal            = MET × 3.5 × weight (kg) / 200 × minutes
/// - minutes = the day's walked distance ÷ its measured walking speed (a default pace without one).
/// - grade   = elevation gained ÷ distance, AFTER the stairs' height is taken out of it — stairs are
///   climbed, not walked uphill, and are priced on their own: 1.8 ml/kg per metre climbed, the same
///   vertical cost the walking equation uses.
///
/// GROSS (`gross_kcal`, the rate per 1,000 steps) includes the resting 1 MET, by the product
/// owner's call (D-256). ACTIVE (`active_kcal`, what Home calls burned) leaves it out (D-267): the
/// plan's TDEE already counts resting metabolism, and counting it again would eat into the day.
///
/// Never a fixed "1,000 steps = X kcal": the rate is the person's own activity calories ÷ the
/// activity's steps × 1,000. A phone's own calorie figure is never added to this (D-268).

/// A typical walking pace (4.8 km/h), used when the phone measured no walking speed — and the
/// result is then marked estimated.
export const DEFAULT_WALKING_SPEED_M_PER_MIN = 80;

/// Outside this a "walking speed" is not walking: running, cycling, or a car. The ACSM walking
/// equation is for 50–100 m/min; a little either side is still a walk.
export const WALKING_SPEED_BOUNDS_M_PER_MIN = { min: 40, max: 120 } as const;

/// Step length ≈ 0.414 × height, the usual walking estimate when no distance was measured.
export const STRIDE_PER_HEIGHT = 0.414;

/// A day under this many steps says too little about a stride to be averaged in.
export const MIN_DAY_STEPS = 1000;

/// Outside this a "stride" is not walking — Android's distance also counts cycling and running.
export const STRIDE_BOUNDS_M = { min: 0.3, max: 1.1 } as const;

/// One floor of stairs, as Health Connect and HealthKit count them (about ten feet).
export const FLOOR_HEIGHT_M = 3;

/// Steeper than this is a climb, not a walk; the walking equation stops holding.
export const MAX_GRADE = 0.2;

const STEPS_PER_RATE = 1000;
const RESTING_VO2 = 3.5;
const HORIZONTAL_VO2_PER_M = 0.1;
const VERTICAL_VO2_PER_M = 1.8;
/// ACSM: kcal/min = MET × 3.5 × kg / 200, i.e. ml O2 × kg / 200.
const ML_O2_PER_KCAL_KG = 200;

/// The kinds a day's walking is read from.
export const ACTIVITY_KINDS = [
  'steps',
  'steps_added',
  'distance_m',
  'walking_speed_m_min',
  'elevation_gain_m',
  'floors',
  'energy_burned_kcal',
] as const;

const DEVICE_SOURCES: ReadonlySet<string> = new Set([
  'apple_health',
  'health_connect',
]);

export type ActivityRow = {
  kind: string;
  value: string | number;
  diaryDate: string;
  source: string;
};

export type Body = { weightKg: number | null; heightCm: number | null };

export type StrideDay = { steps: number; distanceM: number };

/// One diary day as the phone measured it. Null is "not measured", never zero.
export type ActivityDay = {
  /// Including what the person added or took off (D-221).
  steps: number;
  /// What a device counted, without the person's change — the only steps a distance describes.
  deviceSteps: number | null;
  distanceM: number | null;
  speedMPerMin: number | null;
  elevationGainM: number | null;
  floors: number | null;
  /// A calorie figure the phone or the person reported. Used only on a day with no steps.
  reportedKcal: number | null;
};

export type DayEnergy = {
  gross_kcal: number;
  active_kcal: number;
  /// True when a default stood in for a measurement: the pace, or a stride from height.
  is_estimated: boolean;
};

export type WalkingEnergy = {
  /// GROSS kcal per 1,000 steps, rounded.
  kcal: number;
  /// The same above resting — what 1,000 more steps add to Home's "burned".
  active_kcal: number;
  is_estimated: boolean;
  /// Where the step length came from: the person's own distance ÷ steps, or their height.
  stride_from: 'distance' | 'height';
  /// Where the pace came from: the phone's walking speed, or the default.
  speed_from: 'measured' | 'default';
};

type Stride = { m: number; from: 'distance' | 'height' };

/// Metres per step from days a device measured both steps and distance, or null when those days
/// are too few or describe something other than walking.
export function measuredStride(days: readonly StrideDay[]): number | null {
  const walked = days.filter(
    (d) => d.steps >= MIN_DAY_STEPS && d.distanceM > 0,
  );
  const steps = walked.reduce((sum, d) => sum + d.steps, 0);
  if (steps === 0) return null;
  const stride = walked.reduce((sum, d) => sum + d.distanceM, 0) / steps;
  return stride >= STRIDE_BOUNDS_M.min && stride <= STRIDE_BOUNDS_M.max
    ? stride
    : null;
}

/// Rows of [ACTIVITY_KINDS], one diary day each.
export function activityDays(
  rows: readonly ActivityRow[],
): Map<string, ActivityDay> {
  const byDay = new Map<string, Map<string, ActivityRow>>();
  for (const row of rows) {
    const day = byDay.get(row.diaryDate) ?? new Map<string, ActivityRow>();
    day.set(row.kind, row);
    byDay.set(row.diaryDate, day);
  }

  const days = new Map<string, ActivityDay>();
  for (const [date, kinds] of byDay) {
    const value = (kind: string) => {
      const row = kinds.get(kind);
      return row === undefined ? null : Number(row.value);
    };
    const counted = kinds.get('steps');
    const device =
      counted && DEVICE_SOURCES.has(counted.source)
        ? Number(counted.value)
        : null;
    days.set(date, {
      steps: Math.max(0, (value('steps') ?? 0) + (value('steps_added') ?? 0)),
      deviceSteps: device,
      distanceM: value('distance_m'),
      speedMPerMin: value('walking_speed_m_min'),
      elevationGainM: value('elevation_gain_m'),
      floors: value('floors'),
      reportedKcal: value('energy_burned_kcal'),
    });
  }
  return days;
}

/// The person's usual stride: their own, from the days given, else from their height.
function usualStride(
  days: Iterable<ActivityDay>,
  heightCm: number | null,
): Stride | null {
  const paired: StrideDay[] = [];
  for (const d of days) {
    if (d.deviceSteps !== null && d.distanceM !== null) {
      paired.push({ steps: d.deviceSteps, distanceM: d.distanceM });
    }
  }
  const measured = measuredStride(paired);
  if (measured !== null) return { m: measured, from: 'distance' };
  return heightCm && heightCm > 0
    ? { m: (heightCm / 100) * STRIDE_PER_HEIGHT, from: 'height' }
    : null;
}

function within(value: number | null, bounds: { min: number; max: number }) {
  return value !== null && value >= bounds.min && value <= bounds.max;
}

/// One day's walking and stairs. [usual] stands in when the day's own distance cannot give a stride.
export function dayEnergy(
  day: ActivityDay,
  weightKg: number,
  usual: Stride,
): DayEnergy & {
  stride_from: Stride['from'];
  speed_from: 'measured' | 'default';
} {
  const own =
    day.deviceSteps !== null &&
    day.distanceM !== null &&
    day.deviceSteps >= MIN_DAY_STEPS
      ? day.distanceM / day.deviceSteps
      : null;
  const stride: Stride = within(own, STRIDE_BOUNDS_M)
    ? { m: own!, from: 'distance' }
    : usual;
  const speedMeasured = within(
    day.speedMPerMin,
    WALKING_SPEED_BOUNDS_M_PER_MIN,
  );
  const speed = speedMeasured
    ? day.speedMPerMin!
    : DEFAULT_WALKING_SPEED_M_PER_MIN;

  const distance = day.steps * stride.m;
  const minutes = distance / speed;
  const stairsM = Math.max(0, day.floors ?? 0) * FLOOR_HEIGHT_M;
  const hillM = Math.max(0, (day.elevationGainM ?? 0) - stairsM);
  const grade = distance > 0 ? Math.min(MAX_GRADE, hillM / distance) : 0;

  const vo2 =
    RESTING_VO2 +
    HORIZONTAL_VO2_PER_M * speed +
    VERTICAL_VO2_PER_M * speed * grade;
  const perMinute = weightKg / ML_O2_PER_KCAL_KG;
  const stairs = VERTICAL_VO2_PER_M * stairsM * perMinute;

  return {
    gross_kcal: Math.round(vo2 * perMinute * minutes + stairs),
    active_kcal: Math.round((vo2 - RESTING_VO2) * perMinute * minutes + stairs),
    is_estimated: !speedMeasured || stride.from === 'height',
    stride_from: stride.from,
    speed_from: speedMeasured ? 'measured' : 'default',
  };
}

/// What each day burned, above resting. A day with steps is worked out from them; a day without
/// keeps the figure that was reported for it; a day with neither is left out. With no weight or
/// no stride nothing can be worked out, so only reported figures remain.
export function burnedByDay(
  rows: readonly ActivityRow[],
  body: Body,
): Map<string, number> {
  const days = activityDays(rows);
  const usual = usualStride(days.values(), body.heightCm);
  const burned = new Map<string, number>();
  for (const [date, day] of days) {
    if (day.steps > 0 && usual !== null && body.weightKg && body.weightKg > 0) {
      burned.set(date, dayEnergy(day, body.weightKg, usual).active_kcal);
    } else if (day.reportedKcal !== null) {
      burned.set(date, day.reportedKcal);
    }
  }
  return burned;
}

/// Calories per 1,000 steps = activity calories ÷ activity steps × 1,000, over the days given.
/// With no walked day, 1,000 steps at the person's usual stride and the default pace.
export function kcalPer1000Steps(
  rows: readonly ActivityRow[],
  body: Body,
): WalkingEnergy | null {
  const { weightKg } = body;
  if (!weightKg || weightKg <= 0) return null;
  const days = [...activityDays(rows).values()];
  const usual = usualStride(days, body.heightCm);
  if (usual === null) return null;

  const walked = days.filter((d) => d.steps >= MIN_DAY_STEPS);
  const sample: ActivityDay[] =
    walked.length > 0
      ? walked
      : [
          {
            steps: STEPS_PER_RATE,
            deviceSteps: null,
            distanceM: null,
            speedMPerMin: null,
            elevationGainM: null,
            floors: null,
            reportedKcal: null,
          },
        ];

  const energies = sample.map((d) => dayEnergy(d, weightKg, usual));
  const steps = sample.reduce((sum, d) => sum + d.steps, 0);
  const per1000 = (kcal: number) => Math.round((kcal / steps) * STEPS_PER_RATE);
  return {
    kcal: per1000(energies.reduce((sum, e) => sum + e.gross_kcal, 0)),
    active_kcal: per1000(energies.reduce((sum, e) => sum + e.active_kcal, 0)),
    is_estimated: energies.some((e) => e.is_estimated),
    stride_from: energies.some((e) => e.stride_from === 'height')
      ? 'height'
      : 'distance',
    speed_from: energies.every((e) => e.speed_from === 'measured')
      ? 'measured'
      : 'default',
  };
}
