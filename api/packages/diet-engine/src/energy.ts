import type { BmrCoefficients, RulePack } from './pack';
import type { EngineInput, Goal, WarningCode } from './types';

/** docs/04 §3 — Mifflin-St Jeor. Current weight, never goal weight. */
export function computeBmr(
  input: EngineInput,
  pack: RulePack,
): { bmr: number; reducedPrecision: boolean } {
  const { male, female } = pack.energy.bmr;
  const apply = (c: BmrCoefficients): number =>
    c.weight * input.weightKg +
    c.height * input.heightCm +
    c.age * input.ageYears +
    c.constant;

  if (input.sexAtBirth === 'male')
    return { bmr: apply(male), reducedPrecision: false };
  if (input.sexAtBirth === 'female')
    return { bmr: apply(female), reducedPrecision: false };
  // intersex_prefer_not_say: mean of both, and flag the precision loss to the user.
  return { bmr: (apply(male) + apply(female)) / 2, reducedPrecision: true };
}

export function computeBmi(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

export function computeTdee(
  bmr: number,
  input: EngineInput,
  pack: RulePack,
): number {
  const multiplier = pack.energy.activity_multipliers[input.activityLevel];
  if (multiplier === undefined)
    throw new Error(`unknown activity level: ${input.activityLevel}`);
  return bmr * multiplier;
}

export interface GoalAdjustResult {
  readonly target: number;
  readonly appliedPct: number;
  readonly warnings: readonly WarningCode[];
}

/**
 * docs/04 §3 — goal adjustment with its own absolute cap, before the §4 clamps.
 * `maxDeficitPct` comes from the safety layer (age / condition reductions) and can only tighten.
 */
export function applyGoalAdjustment(
  tdee: number,
  goal: Goal,
  pack: RulePack,
  maxDeficitPct: number,
): GoalAdjustResult {
  const spec = pack.energy.goal_adjustment[goal];
  if (spec === undefined) throw new Error(`unknown goal: ${goal}`);
  if (spec.pct === 0) return { target: tdee, appliedPct: 0, warnings: [] };

  const warnings: WarningCode[] = [];

  if (spec.pct < 0) {
    let pct = Math.abs(spec.pct);
    if (pct > maxDeficitPct) {
      pct = maxDeficitPct;
      warnings.push('deficit_capped_condition');
    }
    let deficit = tdee * pct;
    if (deficit > spec.abs_cap_kcal) {
      deficit = spec.abs_cap_kcal;
      warnings.push('deficit_capped_absolute');
    }
    return { target: tdee - deficit, appliedPct: -(deficit / tdee), warnings };
  }

  let surplus = tdee * spec.pct;
  if (surplus > spec.abs_cap_kcal) {
    surplus = spec.abs_cap_kcal;
    warnings.push('surplus_capped_absolute');
  }
  return { target: tdee + surplus, appliedPct: surplus / tdee, warnings };
}
