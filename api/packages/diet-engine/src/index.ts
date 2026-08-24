import { applyGoalAdjustment, computeBmi, computeBmr, computeTdee } from './energy';
import {
  computeAddedSugarMaxG,
  computeBodyWeights,
  computeCarbs,
  computeFat,
  computeFibre,
  computeProtein,
  computeSaturatedFatMaxG,
  computeSodiumMaxMg,
  computeWaterMl,
} from './macros';
import { distributeMeals } from './meals';
import { applyOverrides, type PackWithOverrides } from './overrides';
import { assertMealsCoherent, assertTargetsCoherent, round1, roundTargets } from './output';
import { clampTarget, effectiveGoal, evaluateGates, maxDeficitPct } from './safety';
import type { EngineOutput, EngineInput, TraceStep, WarningCode } from './types';
import { validateInput } from './validate';

export * from './types';
export type { RulePack } from './pack';
export { EngineAssertionError } from './output';
export { EngineInputError } from './validate';
export { createPrng, hashSeed } from './prng';

/**
 * docs/04 §2 — the pipeline, in order. Pure: no clock, no random, no I/O, no locale formatting.
 * Same input + same pack version = byte-identical output, forever.
 *
 * Steps 11, 13 and 14 (candidate pool, greedy fill, alternates) require the food database. It does
 * not exist yet (docs/20 §1, §6), so this returns per-meal targets and leaves `meals` unfilled
 * rather than inventing food. A partial plan is worse than no plan, and fake food is worse than both.
 */
export function generatePlan(input: EngineInput, pack: PackWithOverrides): EngineOutput {
  const trace: TraceStep[] = [];
  const warnings: WarningCode[] = [];

  // 1 — validate & normalise
  validateInput(input);

  // 2 — BMR
  const { bmr, reducedPrecision } = computeBmr(input, pack);
  if (reducedPrecision) warnings.push('estimate_precision_reduced');
  const bmi = computeBmi(input.weightKg, input.heightCm);
  trace.push({
    step: 'bmr',
    formula: pack.energy.bmr.formula,
    inputs: { w: input.weightKg, h: input.heightCm, a: input.ageYears, sex: input.sexAtBirth },
    result: Math.round(bmr),
  });

  // 3 — TDEE
  const tdee = computeTdee(bmr, input, pack);
  trace.push({
    step: 'tdee',
    multiplier: pack.energy.activity_multipliers[input.activityLevel],
    result: Math.round(tdee),
  });

  // 4 — goal adjustment, bounded by the safety layer's deficit ceiling
  const deficitCeiling = maxDeficitPct(input, pack);
  const goalResult = effectiveGoal(input, bmi, pack);
  warnings.push(...goalResult.warnings);
  const goal = goalResult.goal;

  const adjusted = applyGoalAdjustment(tdee, goal, pack, deficitCeiling.pct);
  if (goal !== 'maintenance') warnings.push(...deficitCeiling.warnings);
  warnings.push(...adjusted.warnings);
  trace.push({
    step: 'goal_adjust',
    goal,
    requested_goal: input.goal,
    pct: Math.round(adjusted.appliedPct * 1000) / 10,
    result: Math.round(adjusted.target),
  });

  // 5 — safety floors and ceilings. Cannot be skipped.
  const clamped = clampTarget(adjusted.target, bmr, tdee, input, pack);
  warnings.push(...clamped.warnings);
  const floor = input.sexAtBirth === 'female' ? pack.safety.floor_kcal.female : pack.safety.floor_kcal.male;
  trace.push({
    step: 'safety_clamp',
    applied: clamped.applied,
    floor,
    bmr_floor: Math.round(bmr),
    result: Math.round(clamped.target),
  });

  // 6 — condition gates. A blocking gate means no plan at all.
  const gateResult = evaluateGates(input, bmi, pack);
  const blocking = gateResult.gates.filter((g) => g.blocking);
  trace.push({ step: 'gates', codes: gateResult.gates.map((g) => g.code), blocking: blocking.length > 0 });

  if (blocking.length > 0) {
    return {
      packVersion: pack.version,
      targets: null,
      derived: null,
      mealTargets: [],
      constraints: null,
      warnings: dedupe(warnings),
      gates: gateResult.gates,
      trace,
    };
  }

  // 7 — protein, on adjusted body weight
  const weights = computeBodyWeights(input, pack);
  const protein = computeProtein(input, clamped.target, weights, goal, pack);
  warnings.push(...protein.warnings);
  trace.push({
    step: 'protein',
    basis: input.weightKg > weights.ibw ? 'abw' : 'actual',
    ibw: round1(weights.ibw),
    abw: round1(weights.abw),
    rate: protein.rate,
    result: Math.round(protein.grams),
  });

  // 8 — fat, then the caps that do not consume the energy budget
  const fat = computeFat(input.conditions, goal, clamped.target, weights.abw, pack);
  trace.push({ step: 'fat', pct: Math.round(fat.pct * 1000) / 10, result: Math.round(fat.grams) });

  const baseSodium = computeSodiumMaxMg(input.conditions, pack);
  const baseSugar = computeAddedSugarMaxG(clamped.target, input.conditions, pack);

  // 9 — carbs are the remainder, and the 100 g floor outranks the calorie number
  const carbs = computeCarbs(clamped.target, protein.grams, fat.grams, input, pack);
  warnings.push(...carbs.warnings);
  trace.push({ step: 'carbs', result: Math.round(carbs.carbG), target_kcal: Math.round(carbs.targetKcal) });

  // 10 — ordered medical overrides, intersected
  const overrides = applyOverrides(
    input,
    carbs.targetKcal,
    deficitCeiling.pct,
    baseSodium,
    baseSugar,
    pack,
  );
  trace.push({
    step: 'override',
    rule: overrides.appliedPriorities.length === 0 ? 'none' : overrides.appliedPriorities.join(','),
  });

  const targets = roundTargets({
    kcal: carbs.targetKcal,
    proteinG: carbs.proteinG,
    fatG: fat.grams,
    carbG: carbs.carbG,
    fibreG: computeFibre(carbs.targetKcal, pack),
    sodiumMaxMg: overrides.constraints.sodiumMaxMg,
    addedSugarMaxG: overrides.constraints.addedSugarMaxG,
    saturatedFatMaxG: computeSaturatedFatMaxG(carbs.targetKcal, input.conditions, pack),
    waterMl: computeWaterMl(input.weightKg, pack),
  });

  // 12 — distribute across meals (11, 13, 14 await the food DB)
  const mealTargets = distributeMeals({
    mealCount: input.mealCount,
    targetKcal: carbs.targetKcal,
    proteinTargetG: carbs.proteinG,
    abw: weights.abw,
    constraints: overrides.constraints,
    pack,
  });
  trace.push({
    step: 'distribute',
    pattern: `${input.mealCount}_meal`,
    split: mealTargets.map((m) => Math.round(m.pct * 100)),
  });

  // 15 — validate. An assertion failure here is a bug, never a warning.
  assertTargetsCoherent(targets, pack);
  assertMealsCoherent(mealTargets, carbs.targetKcal, pack);

  return {
    packVersion: pack.version,
    targets,
    derived: {
      bmr: Math.round(bmr),
      tdee: Math.round(tdee),
      bmi: round1(bmi),
      ibw: round1(weights.ibw),
      abw: round1(weights.abw),
      proteinBasisKg: round1(weights.proteinBasisKg),
      effectiveGoal: goal,
    },
    mealTargets,
    constraints: overrides.constraints,
    warnings: dedupe(warnings),
    gates: gateResult.gates,
    trace,
  };
}

function dedupe(warnings: readonly WarningCode[]): readonly WarningCode[] {
  return [...new Set(warnings)];
}
