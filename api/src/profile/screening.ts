/// docs/05 §3 gates, enforced server-side.
///
/// The Flutter app runs the same rules for immediate feedback, but that is a courtesy — an app
/// build is not a trustworthy enforcement point, so every rule is re-run here and this answer wins.
/// Keep this file in sync with `lib/domain/usecases/validate_onboarding.dart`.

export const MIN_AGE = 18;
export const MAX_AGE = 99;
export const CLINICIAN_GATE_AGE = 70;
export const MIN_BMI = 16;

/// docs/05 §2's healthy floor, used to refuse a GOAL weight rather than to gate a current one:
/// [MIN_BMI] is where a present body blocks a plan, this is where a target stops being one we
/// will aim at.
export const MIN_HEALTHY_BMI = 18.5;
export const CLINICIAN_GATE_BMI = 40;

/// docs/05 §3 BLOCK list — mirrors `Condition.isBlockingGate`.
export const BLOCKING_CONDITIONS = [
  'ckd',
  'pregnancy',
  'lactation',
  'hyperthyroid',
  'post_surgery',
] as const;

export type GateOutcome = {
  /// Non-empty ⇒ no plan is generated and the app shows the referral screen.
  blocked: string[];
  /// Plan only after a coach with a recorded clinician attestation unlocks it.
  clinicianGated: string[];
};

export type ScreeningInput = {
  ageYears: number;
  heightCm: number;
  weightKg: number;
  conditions: string[];
  screenedInsulinOrKidney?: boolean | null;
  screenedEatingDisorder?: boolean | null;
  screenedSpecialDiet?: boolean | null;
};

export function bmiOf(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

export function evaluateGates(input: ScreeningInput): GateOutcome {
  const blocked: string[] = [];
  const clinicianGated: string[] = [];

  for (const condition of input.conditions) {
    if ((BLOCKING_CONDITIONS as readonly string[]).includes(condition)) {
      blocked.push(condition);
    }
  }

  // docs/05 §4 screening questions. Q2 is a hard block; Q3 routes to support, also a block.
  if (input.screenedInsulinOrKidney === true) blocked.push('insulin_or_kidney');
  if (input.screenedEatingDisorder === true) blocked.push('eating_disorder');
  // Q1 is a clinician gate, not a block — a declared special diet needs a human to sign off.
  if (input.screenedSpecialDiet === true) clinicianGated.push('special_diet');

  if (input.ageYears < MIN_AGE) blocked.push('age_ineligible');
  if (input.ageYears >= CLINICIAN_GATE_AGE) clinicianGated.push('age_70_plus');

  const bmi = bmiOf(input.weightKg, input.heightCm);
  if (bmi < MIN_BMI) blocked.push('bmi_below_16');
  if (bmi >= CLINICIAN_GATE_BMI) clinicianGated.push('bmi_40_plus');

  return { blocked, clinicianGated };
}
