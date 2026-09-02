import type { RulePack } from './pack';
import type { EngineInput, Gate, Goal, WarningCode } from './types';

/**
 * docs/05 §2 and §3, mirrored by docs/04 §4. This module can veto anything the rest of the engine
 * wants to do. Nothing here is skippable and nothing here is a warning-only path.
 */

export interface GateResult {
  readonly gates: readonly Gate[];
  readonly warnings: readonly WarningCode[];
}

/** docs/04 §2 step 6. A blocking gate means no plan is emitted at all. */
export function evaluateGates(
  input: EngineInput,
  bmi: number,
  pack: RulePack,
): GateResult {
  const gates: Gate[] = [];
  const warnings: WarningCode[] = [];
  const { blocking_gates: blocking, clinician_gated: clinician } = pack.safety;

  if (input.ageYears < blocking.min_age)
    gates.push({ code: 'age_ineligible', blocking: true });
  if (bmi < blocking.min_bmi)
    gates.push({ code: 'bmi_critical', blocking: true });

  for (const condition of input.conditions) {
    if (!blocking.conditions.includes(condition)) continue;
    // post_surgery is the one blocking condition a clinician attestation can unlock (docs/05 §3).
    if (condition === 'post_surgery') {
      if (input.clinicianAttestation !== true) {
        gates.push({ code: 'post_surgery_needs_clinician', blocking: true });
      }
      continue;
    }
    gates.push({ code: condition as Gate['code'], blocking: true });
  }

  // Non-blocking review gates. A plan is still produced; the app surfaces the referral.
  if (
    bmi >= blocking.min_bmi &&
    bmi < pack.safety.force_maintenance_below_bmi
  ) {
    gates.push({ code: 'underweight_review', blocking: false });
  }
  if (input.ageYears >= clinician.min_age || bmi >= clinician.min_bmi) {
    gates.push({ code: 'clinician_review_required', blocking: false });
  }

  return { gates, warnings };
}

/** docs/05 §2 — 20 % of TDEE by default, 15 % for age >= 65 or T2D / HTN / hypothyroid. */
export function maxDeficitPct(
  input: EngineInput,
  pack: RulePack,
): { pct: number; warnings: readonly WarningCode[] } {
  const s = pack.safety;
  const warnings: WarningCode[] = [];
  let pct = s.max_deficit_pct_default;

  if (input.ageYears >= s.reduced_deficit_age) {
    pct = Math.min(pct, s.max_deficit_pct_reduced);
    warnings.push('deficit_capped_age');
  }
  if (input.conditions.some((c) => s.reduced_deficit_conditions.includes(c))) {
    pct = Math.min(pct, s.max_deficit_pct_reduced);
    warnings.push('deficit_capped_condition');
  }
  return { pct, warnings };
}

export interface EffectiveGoalResult {
  readonly goal: Goal;
  readonly warnings: readonly WarningCode[];
}

/**
 * docs/04 §4: BMI < 18.5 forces maintenance. BMI < 22 permits no deficit at all.
 *
 * Ordering note (docs/16 GV-06): the BMI check runs BEFORE the absolute kcal floor, so a low-BMI
 * user gets TDEE rather than a deficit floored up. `clampTarget` applies the floors afterwards.
 */
export function effectiveGoal(
  input: EngineInput,
  bmi: number,
  pack: RulePack,
): EffectiveGoalResult {
  const warnings: WarningCode[] = [];
  if (bmi < pack.safety.force_maintenance_below_bmi) {
    warnings.push('goal_forced_maintenance_low_bmi');
    return { goal: 'maintenance', warnings };
  }
  if (input.goal === 'fat_loss' && bmi < pack.safety.no_deficit_below_bmi) {
    warnings.push('deficit_suppressed_low_bmi');
    return { goal: 'maintenance', warnings };
  }
  return { goal: input.goal, warnings };
}

export interface ClampResult {
  readonly target: number;
  readonly applied: boolean;
  readonly warnings: readonly WarningCode[];
}

/**
 * docs/04 §4 / docs/05 §2 — the hard floors, applied last so nothing downstream can undercut them.
 * Also enforces the 0.25–1.0 %/week planned-loss band.
 */
export function clampTarget(
  rawTarget: number,
  bmr: number,
  tdee: number,
  input: EngineInput,
  pack: RulePack,
): ClampResult {
  const s = pack.safety;
  const warnings: WarningCode[] = [];
  let target = rawTarget;

  // Weekly rate band — only meaningful while there is a deficit.
  const deficit = tdee - target;
  if (deficit > 0) {
    const maxDailyDeficit =
      (s.weekly_loss_pct_max * input.weightKg * s.kcal_per_kg_body_fat) / 7;
    if (deficit > maxDailyDeficit) {
      target = tdee - maxDailyDeficit;
      warnings.push('deficit_capped_weekly_rate');
    }
  }

  const floor =
    input.sexAtBirth === 'female' ? s.floor_kcal.female : s.floor_kcal.male;
  if (target < floor) {
    target = floor;
    warnings.push('target_raised_to_floor');
  }

  const bmrFloor = bmr * s.never_below_bmr_multiple;
  if (target < bmrFloor) {
    target = bmrFloor;
    warnings.push('target_raised_to_bmr');
  }

  return { target, applied: warnings.length > 0, warnings };
}
