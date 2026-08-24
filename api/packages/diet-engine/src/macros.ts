import type { RulePack } from './pack';
import type { Condition, EngineInput, Goal, WarningCode } from './types';

/** docs/04 §5. Every constant comes from the pack — hard rule 1 forbids a literal here. */

const KCAL_PER_G_PROTEIN = 4;
const KCAL_PER_G_CARB = 4;
const KCAL_PER_G_FAT = 9;

export interface BodyWeights {
  readonly ibw: number;
  readonly abw: number;
  /** What the protein rate is applied to: ABW above IBW, actual weight at or below it. */
  readonly proteinBasisKg: number;
}

/** IBW at the Indian/Asian BMI reference of 23, not 25. */
export function computeBodyWeights(input: EngineInput, pack: RulePack): BodyWeights {
  const heightM = input.heightCm / 100;
  const ibw = pack.macros.ibw_bmi_reference * heightM * heightM;
  const abw =
    input.weightKg > ibw
      ? ibw + pack.macros.abw_excess_fraction * (input.weightKg - ibw)
      : input.weightKg;
  return { ibw, abw, proteinBasisKg: input.weightKg > ibw ? abw : input.weightKg };
}

export interface ProteinResult {
  readonly grams: number;
  readonly rate: number;
  readonly warnings: readonly WarningCode[];
}

/**
 * docs/04 §5 protein. Caps tighten, the ICMR floor never yields.
 *
 * SPEC GAP: docs/16 GV-04 expects 1.4 g/kg for a 60-year-old with type2_diabetes and emits
 * `renal_protein_caution`. No such rule exists in docs/04 §5 or docs/05 §2 — the only renal taper
 * defined is `ckd`, or age > 60 WITH diabetes AND hypertension. We implement the written spec.
 * Resolving this needs the clinical reviewer docs/05 requires, then a pack entry — not a code edit.
 */
export function computeProtein(
  input: EngineInput,
  targetKcal: number,
  weights: BodyWeights,
  goal: Goal,
  pack: RulePack,
): ProteinResult {
  const p = pack.macros.protein;
  const warnings: WarningCode[] = [];
  const spec = p.rate_g_per_kg_abw[goal];
  if (spec === undefined) throw new Error(`no protein rate for goal: ${goal}`);

  let rate = spec.default;
  if (input.coachProteinRate !== undefined) {
    rate = Math.min(Math.max(input.coachProteinRate, spec.min), spec.max);
  }

  // Renal caution: ckd (already a blocking gate) or unknown eGFR in >60 with diabetes + hypertension.
  const over60WithBoth =
    input.ageYears > 60 &&
    input.conditions.some((c) => c === 'type2_diabetes' || c === 'prediabetes') &&
    input.conditions.includes('hypertension');
  if (input.conditions.includes('ckd') || over60WithBoth) {
    rate = Math.min(rate, p.renal_caution_rate);
    warnings.push('renal_protein_caution');
  }

  let grams = rate * weights.proteinBasisKg;

  const capByAbw = p.max_g_per_kg_abw * weights.abw;
  const capByEnergy = (p.max_pct_energy * targetKcal) / KCAL_PER_G_PROTEIN;
  grams = Math.min(grams, capByAbw, capByEnergy);

  // ICMR RDA floor — applied last so no cap can push below the national recommendation.
  grams = Math.max(grams, p.min_g_per_kg_actual * input.weightKg);

  return { grams, rate, warnings };
}

/**
 * docs/04 §5 fat. Condition overrides take precedence over the goal override; when a user matches
 * more than one condition we take the highest declared percentage, since both listed conditions
 * raise fat to displace carbohydrate rather than restrict it.
 */
export function computeFat(
  conditions: readonly Condition[],
  goal: Goal,
  targetKcal: number,
  abw: number,
  pack: RulePack,
): { grams: number; pct: number } {
  const f = pack.macros.fat;
  const conditionPcts = conditions
    .map((c) => f.pct_by_condition[c])
    .filter((v): v is number => v !== undefined);

  let pct: number;
  if (conditionPcts.length > 0) pct = Math.max(...conditionPcts);
  else pct = f.pct_by_goal[goal] ?? f.pct_default;

  pct = Math.max(pct, f.min_pct_energy);
  let grams = (pct * targetKcal) / KCAL_PER_G_FAT;
  grams = Math.max(grams, f.min_g_per_kg_abw * abw);

  return { grams, pct: (grams * KCAL_PER_G_FAT) / targetKcal };
}

export interface CarbResult {
  readonly carbG: number;
  readonly proteinG: number;
  readonly targetKcal: number;
  readonly warnings: readonly WarningCode[];
}

/**
 * docs/04 §5 — carbs are the remainder, with a hard 100 g floor. To honour the floor, reduce protein
 * toward its own floor first, then raise the target. The engine must never emit a ketogenic plan.
 */
export function computeCarbs(
  targetKcal: number,
  proteinG: number,
  fatG: number,
  input: EngineInput,
  pack: RulePack,
): CarbResult {
  const minCarbG = pack.macros.carbs.min_g;
  const proteinFloorG = pack.macros.protein.min_g_per_kg_actual * input.weightKg;
  const warnings: WarningCode[] = [];

  const remainderG = (kcal: number, protein: number): number =>
    (kcal - protein * KCAL_PER_G_PROTEIN - fatG * KCAL_PER_G_FAT) / KCAL_PER_G_CARB;

  let protein = proteinG;
  let carbG = remainderG(targetKcal, protein);
  if (carbG >= minCarbG) return { carbG, proteinG: protein, targetKcal, warnings };

  // Step 1: give back protein, down to its floor.
  const deficitG = minCarbG - carbG;
  const proteinGiveG = Math.min(protein - proteinFloorG, deficitG);
  if (proteinGiveG > 0) {
    protein -= proteinGiveG;
    carbG = remainderG(targetKcal, protein);
    warnings.push('protein_reduced_for_carb_floor');
  }
  if (carbG >= minCarbG) return { carbG, proteinG: protein, targetKcal, warnings };

  // Step 2: raise the target. Floors win over the calorie number, never the other way round.
  const raisedKcal = targetKcal + (minCarbG - carbG) * KCAL_PER_G_CARB;
  return { carbG: minCarbG, proteinG: protein, targetKcal: raisedKcal, warnings };
}

export function computeFibre(targetKcal: number, pack: RulePack): number {
  const f = pack.macros.fibre;
  const raw = (targetKcal / 1000) * f.g_per_1000_kcal;
  return Math.min(Math.max(raw, f.min_g), f.max_g);
}

export function computeSodiumMaxMg(conditions: readonly Condition[], pack: RulePack): number {
  const s = pack.macros.sodium;
  return conditions.includes('hypertension') ? s.max_mg_hypertension : s.max_mg_default;
}

const SUGAR_ABSOLUTE_CONDITIONS: readonly Condition[] = ['type2_diabetes', 'prediabetes', 'pcos'];

export function computeAddedSugarMaxG(
  targetKcal: number,
  conditions: readonly Condition[],
  pack: RulePack,
): number {
  const s = pack.macros.added_sugar;
  const byEnergy = (s.max_pct_energy * targetKcal) / KCAL_PER_G_CARB;
  const needsAbsolute = conditions.some((c) => SUGAR_ABSOLUTE_CONDITIONS.includes(c));
  return needsAbsolute ? Math.min(byEnergy, s.max_g_absolute) : byEnergy;
}

export function computeSaturatedFatMaxG(
  targetKcal: number,
  conditions: readonly Condition[],
  pack: RulePack,
): number {
  const f = pack.macros.fat;
  const tighten = conditions.includes('hypertension');
  const pct = tighten ? f.saturated_max_pct_tightened : f.saturated_max_pct_default;
  return (pct * targetKcal) / KCAL_PER_G_FAT;
}

/** docs/04 §5 — 33 ml/kg, clamped 2–4 L. Not a flat 3 L for everyone. */
export function computeWaterMl(weightKg: number, pack: RulePack): number {
  const w = pack.macros.water;
  return Math.min(Math.max(weightKg * w.ml_per_kg, w.min_ml), w.max_ml);
}

export const ENERGY_PER_G = {
  protein: KCAL_PER_G_PROTEIN,
  carb: KCAL_PER_G_CARB,
  fat: KCAL_PER_G_FAT,
} as const;
