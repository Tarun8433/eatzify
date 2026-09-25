import {
  applyGoalAdjustment,
  computeBmi,
  computeBmr,
  computeTdee,
} from './energy';
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
import { buildPool, type EngineFood } from './foods';
import { pickAlternates } from './alternates';
import { fillMeals } from './fill';
import { applyOverrides, type PackWithOverrides } from './overrides';
import {
  assertFilledDayCoherent,
  assertMealsCoherent,
  assertTargetsCoherent,
  round1,
  roundTargets,
} from './output';
import {
  clampTarget,
  effectiveGoal,
  evaluateGates,
  maxDeficitPct,
} from './safety';
import type {
  EngineOutput,
  EngineInput,
  TraceStep,
  WarningCode,
} from './types';
import { validateInput } from './validate';

export * from './types';
export type { RulePack } from './pack';
export { EngineAssertionError } from './output';
export { EngineInputError } from './validate';
export { MealPatternError } from './meals';
export { buildPool } from './foods';
export type { EngineFood, EngineMeasure, PoolResult } from './foods';
export { fillMeals } from './fill';
export { pickAlternates } from './alternates';
export type { AlternateItem, ItemAlternates } from './alternates';
export type { Meal, MealItem } from './fill';
export { createPrng, hashSeed } from './prng';

/**
 * docs/04 §2 — the pipeline, in order. Pure: no clock, no random, no I/O, no locale formatting.
 * Same input + same pack version = byte-identical output, forever.
 *
 * Steps 11 and 13 (candidate pool, greedy fill) run only when the caller hands in `foods`. The
 * engine has no database — purity is what makes a plan reproducible — so the pool is queried
 * upstream and passed in. Without it the output carries targets and an empty `meals`, which is
 * what shipped before the food table existed: a partial plan is worse than no plan, and invented
 * food is worse than both.
 *
 * Step 14 (alternates) is not here yet. Its ±10 % / ±5 g window belongs in the rule pack and the
 * pack directory is deny-listed to this agent (.claude/rules/engine.md), so the diff is proposed
 * rather than written.
 */
export function generatePlan(
  input: EngineInput,
  pack: PackWithOverrides,
  foods: readonly EngineFood[] = [],
): EngineOutput {
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
    inputs: {
      w: input.weightKg,
      h: input.heightCm,
      a: input.ageYears,
      sex: input.sexAtBirth,
    },
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
  const floor =
    input.sexAtBirth === 'female'
      ? pack.safety.floor_kcal.female
      : pack.safety.floor_kcal.male;
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
  trace.push({
    step: 'gates',
    codes: gateResult.gates.map((g) => g.code),
    blocking: blocking.length > 0,
  });

  if (blocking.length > 0) {
    return {
      packVersion: pack.version,
      targets: null,
      derived: null,
      mealTargets: [],
      // docs/04 §2 step 6: a blocking gate emits NO plan. Not an empty one it might fill later —
      // there is nothing to fill, which is the point.
      meals: [],
      alternates: [],
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
  const fat = computeFat(
    input.conditions,
    goal,
    clamped.target,
    weights.abw,
    pack,
  );
  trace.push({
    step: 'fat',
    pct: Math.round(fat.pct * 1000) / 10,
    result: Math.round(fat.grams),
  });

  const baseSodium = computeSodiumMaxMg(input.conditions, pack);
  const baseSugar = computeAddedSugarMaxG(
    clamped.target,
    input.conditions,
    pack,
  );

  // 9 — carbs are the remainder, and the 100 g floor outranks the calorie number
  const carbs = computeCarbs(
    clamped.target,
    protein.grams,
    fat.grams,
    input,
    pack,
  );
  warnings.push(...carbs.warnings);
  trace.push({
    step: 'carbs',
    result: Math.round(carbs.carbG),
    target_kcal: Math.round(carbs.targetKcal),
  });

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
    rule:
      overrides.appliedPriorities.length === 0
        ? 'none'
        : overrides.appliedPriorities.join(','),
  });

  const targets = roundTargets({
    kcal: carbs.targetKcal,
    proteinG: carbs.proteinG,
    fatG: fat.grams,
    carbG: carbs.carbG,
    fibreG: computeFibre(carbs.targetKcal, pack),
    sodiumMaxMg: overrides.constraints.sodiumMaxMg,
    addedSugarMaxG: overrides.constraints.addedSugarMaxG,
    saturatedFatMaxG: computeSaturatedFatMaxG(
      carbs.targetKcal,
      input.conditions,
      pack,
    ),
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

  // A conflict INSIDE the pack, surfaced rather than papered over (D-231). A per-occasion carb cap
  // times the number of occasions can be less than the day's carbohydrate target — for type 2
  // diabetes on v1.0.0 it is 4 × 55 g against 394 g — and no search can satisfy both. The plan
  // that comes back is short on energy and says so, because the alternatives are worse: quietly
  // breaching a clinical cap, or quietly serving the difference as fat.
  const carbCap = overrides.constraints.maxCarbGPerOccasion;
  if (carbCap !== undefined && carbCap * mealTargets.length < targets.carbG) {
    warnings.push('carb_cap_limits_energy');
    trace.push({
      step: 'carb_cap',
      cap_g_per_occasion: carbCap,
      occasions: mealTargets.length,
      reachable_carb_g: carbCap * mealTargets.length,
      target_carb_g: targets.carbG,
    });
  }

  // 11 — candidate pool. Traced even when empty: "why is there no food" is the first question a
  // blank plan raises, and the rejection counts are the answer.
  const pool = buildPool(foods, input, overrides.constraints);
  trace.push({
    step: 'pool',
    offered: foods.length,
    eligible: pool.foods.length,
    rejected: pool.rejected,
  });

  // 13 — fill. No pool means no meals; it never means invented ones.
  const meals =
    pool.foods.length > 0
      ? fillMeals({
          mealTargets,
          pool: pool.foods,
          pack,
          constraints: overrides.constraints,
          proteinTargetG: carbs.proteinG,
          sodiumMaxMg: targets.sodiumMaxMg,
          addedSugarMaxG: targets.addedSugarMaxG,
          fatMaxG: targets.fatG,
          fibreTargetG: targets.fibreG,
          saturatedFatMaxG: targets.saturatedFatMaxG,
        })
      : [];
  if (meals.length > 0) {
    trace.push({
      step: 'fill',
      slots: meals.map((m) => m.slot),
      items: meals.reduce((n, m) => n + m.items.length, 0),
      // docs/04 §7: the residual is recorded when the loop falls back to its closest attempt.
      approximated: meals.filter((m) => m.approximated).map((m) => m.slot),
    });
  }

  // 14 — alternates. Same-group swaps inside the pack's tolerances; a pack without the block
  // offers none, and that is a statement, not a gap (D-235).
  const alternates = meals.length > 0 ? pickAlternates(meals, pool.foods, pack) : [];
  if (meals.length > 0) {
    trace.push({
      step: 'alternates',
      items_with_options: alternates.length,
      offered: alternates.reduce((n, a) => n + a.alternates.length, 0),
    });
  }

  // 15 — validate. An assertion failure here is a bug, never a warning.
  assertTargetsCoherent(targets, pack);
  assertMealsCoherent(mealTargets, carbs.targetKcal, pack);
  // docs/04 §8 asserts the FILLED day, not only the split. The split was always coherent while
  // the meals under it summed to 328 g of protein against a 117 g target.
  if (meals.length > 0) assertFilledDayCoherent(meals, targets, pack);

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
    meals,
    alternates,
    constraints: overrides.constraints,
    warnings: dedupe(warnings),
    gates: gateResult.gates,
    trace,
  };
}

function dedupe(warnings: readonly WarningCode[]): readonly WarningCode[] {
  return [...new Set(warnings)];
}
