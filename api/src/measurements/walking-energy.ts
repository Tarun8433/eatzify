/// Calories burned per 1,000 steps, from the person's own weight and stride (D-256).
///
/// Pure, no I/O. ACSM walking equation, flat ground:
///   VO2 (ml/kg/min) = 0.1 × speed (m/min) + 3.5
///   MET             = VO2 / 3.5
///   kcal            = MET × 3.5 × weight (kg) / 200 × minutes
/// GROSS by the product owner's call — it includes the resting 1 MET. That is why this figure is
/// only ever shown as a rate and never added to `energy_burned_kcal`, which is active-only: adding
/// it would count resting metabolism twice against a TDEE that already holds it.
///
/// Never a fixed "1,000 steps = X kcal". The two inputs that move it are the person's weight and
/// how far their 1,000 steps actually carry them.

/// A typical walking pace (4.8 km/h). Health Connect gives us no walking duration today, so the
/// minutes are always derived from this — and the result is always marked estimated.
// ponytail: default speed only; read SPEED / WALKING_SPEED when a real pace is worth a permission.
export const DEFAULT_WALKING_SPEED_M_PER_MIN = 80;

/// Step length ≈ 0.414 × height, the usual walking estimate when no distance was measured.
export const STRIDE_PER_HEIGHT = 0.414;

/// A day under this many steps says too little about a stride to be averaged in.
export const MIN_DAY_STEPS = 1000;

/// Outside this a "stride" is not walking — Android's distance also counts cycling and running.
export const STRIDE_BOUNDS_M = { min: 0.3, max: 1.1 } as const;

const STEPS_PER_RATE = 1000;
const RESTING_VO2 = 3.5;
const HORIZONTAL_VO2_PER_M = 0.1;

export type StrideDay = { steps: number; distanceM: number };

export type WalkingEnergy = {
  /// kcal per 1,000 steps, rounded to a whole number.
  kcal: number;
  /// True whenever a default stood in for a measurement — today, always (no walking speed is read).
  is_estimated: boolean;
  /// Where the step length came from: the person's own distance ÷ steps, or their height.
  stride_from: 'distance' | 'height';
};

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

export function kcalPer1000Steps(input: {
  weightKg: number | null;
  heightCm: number | null;
  days: readonly StrideDay[];
}): WalkingEnergy | null {
  const { weightKg, heightCm } = input;
  if (!weightKg || weightKg <= 0) return null;

  const measured = measuredStride(input.days);
  const stride =
    measured ??
    (heightCm && heightCm > 0 ? (heightCm / 100) * STRIDE_PER_HEIGHT : null);
  if (stride === null) return null;

  const speed = DEFAULT_WALKING_SPEED_M_PER_MIN;
  const minutes = (STEPS_PER_RATE * stride) / speed;
  const met = (HORIZONTAL_VO2_PER_M * speed + RESTING_VO2) / RESTING_VO2;
  const kcal = ((met * RESTING_VO2 * weightKg) / 200) * minutes;

  return {
    kcal: Math.round(kcal),
    is_estimated: true,
    stride_from: measured === null ? 'height' : 'distance',
  };
}
