/**
 * Engine vocabulary. Every name here is defined in docs/03-domain-model.md — if this file and that
 * document disagree, this file is wrong.
 */

import type { ItemAlternates } from './alternates';
import type { Meal } from './fill';

export type SexAtBirth = 'male' | 'female' | 'intersex_prefer_not_say';
export type Goal = 'fat_loss' | 'muscle_gain' | 'maintenance';
export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'heavy';
export type MealCount = '3' | '4' | '5_6';

/** docs/03 §2. `none` is exclusive — enforced in the API DTO, asserted again here. */
export type Condition =
  | 'none'
  | 'type2_diabetes'
  | 'prediabetes'
  | 'hypertension'
  | 'hypothyroid'
  | 'hyperthyroid'
  | 'pcos'
  | 'post_surgery'
  | 'ckd'
  | 'pregnancy'
  | 'lactation'
  | 'type_1_diabetes'
  | 'eating_disorder'
  | 'other_declared';

export type FoodPreference =
  'veg' | 'non_veg' | 'eggetarian' | 'jain' | 'vegan';
export type BudgetTier = 'low' | 'medium' | 'premium';
export type Lifestyle =
  'office' | 'student' | 'night_shift' | 'flexible' | 'home';

export interface EngineInput {
  readonly userId: string;
  /** ISO date (YYYY-MM-DD). Supplied by the caller — the engine never reads a clock. */
  readonly planDate: string;
  readonly ageYears: number;
  readonly sexAtBirth: SexAtBirth;
  readonly heightCm: number;
  readonly weightKg: number;
  readonly goal: Goal;
  readonly activityLevel: ActivityLevel;
  readonly conditions: readonly Condition[];
  readonly foodPreference: FoodPreference;
  readonly foodAllergies: readonly string[];
  readonly budgetTier: BudgetTier;
  readonly lifestyle: Lifestyle;
  readonly mealCount: MealCount;
  /** Coach overrides, already authorised upstream. Can only tighten, never breach a doc 05 floor. */
  readonly coachProteinRate?: number;
  /** Set by a coach with a recorded clinician attestation (docs/05 §3). */
  readonly clinicianAttestation?: boolean;
}

export interface Targets {
  readonly kcal: number;
  readonly proteinG: number;
  readonly fatG: number;
  readonly carbG: number;
  readonly fibreG: number;
  readonly sodiumMaxMg: number;
  readonly addedSugarMaxG: number;
  readonly saturatedFatMaxG: number;
  readonly waterMl: number;
}

export interface Derived {
  readonly bmr: number;
  readonly tdee: number;
  readonly bmi: number;
  readonly ibw: number;
  readonly abw: number;
  /** Weight the protein rate was applied to — ABW, or actual when W <= IBW. */
  readonly proteinBasisKg: number;
  readonly effectiveGoal: Goal;
}

export type WarningCode =
  | 'deficit_suppressed_low_bmi'
  | 'deficit_capped_age'
  | 'deficit_capped_condition'
  | 'deficit_capped_absolute'
  | 'deficit_capped_weekly_rate'
  | 'target_raised_to_bmr'
  | 'target_raised_to_floor'
  | 'goal_forced_maintenance_low_bmi'
  | 'renal_protein_caution'
  | 'protein_reduced_for_carb_floor'
  | 'estimate_precision_reduced'
  | 'surplus_capped_absolute'
  /**
   * docs/04 §7's per-occasion carbohydrate cap and the day's carbohydrate target cannot both be
   * met at this meal count (D-231). Emitted rather than resolved: the cap is clinical, the split
   * is clinical, and the engine choosing between them silently is the one thing it must not do.
   */
  | 'carb_cap_limits_energy';

export type GateCode =
  | 'ckd'
  | 'pregnancy'
  | 'lactation'
  | 'hyperthyroid'
  | 'type_1_diabetes'
  | 'eating_disorder'
  | 'post_surgery_needs_clinician'
  | 'underweight_review'
  | 'bmi_critical'
  | 'age_ineligible'
  | 'clinician_review_required'
  | 'insufficient_food_coverage';

export interface Gate {
  readonly code: GateCode;
  /** true = no plan may be emitted at all (docs/04 §2 step 6). */
  readonly blocking: boolean;
}

/** Constraint set produced by the ordered medical overrides (docs/04 §6). Intersect, never loosen. */
export interface Constraints {
  readonly maxDeficitPct: number;
  readonly sodiumMaxMg: number;
  readonly addedSugarMaxG: number;
  readonly minLowGiCarbFraction?: number;
  readonly maxCarbGPerOccasion?: number;
  readonly minEatingOccasions?: number;
  readonly maxCarbPctEnergy?: number;
  readonly excludeTags: readonly string[];
  readonly preferTags: readonly string[];
  readonly requireEasyDigest: boolean;
  readonly maxPrepMinutes?: number;
  readonly minPortableMeals?: number;
  readonly costLowFraction?: number;
}

export interface MealTarget {
  readonly slot: string;
  readonly pct: number;
  readonly kcal: number;
  readonly minProteinG: number;
  readonly optional: boolean;
}

export interface TraceStep {
  readonly step: string;
  readonly [key: string]: unknown;
}

export interface EngineOutput {
  readonly packVersion: string;
  /** null when a blocking gate fired. A partial plan is worse than no plan (docs/04 §2). */
  readonly targets: Targets | null;
  readonly derived: Derived | null;
  readonly mealTargets: readonly MealTarget[];
  /**
   * The food itself (docs/04 §2 steps 11 and 13). Empty when the caller passed no pool — the
   * engine has no database and will not invent food to fill a slot.
   */
  readonly meals: readonly Meal[];
  /**
   * docs/04 §2 step 14 (D-235). Same-group swaps for served items, inside the pack's
   * `alternates` tolerances. Empty when the pack carries no block, or no swap qualifies.
   */
  readonly alternates: readonly ItemAlternates[];
  readonly constraints: Constraints | null;
  readonly warnings: readonly WarningCode[];
  readonly gates: readonly Gate[];
  readonly trace: readonly TraceStep[];
}
