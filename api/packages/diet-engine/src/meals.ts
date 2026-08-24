import type { RulePack } from './pack';
import type { Constraints, MealTarget } from './types';

/**
 * docs/04 §7 — meal structuring (pipeline step 12). Steps 11, 13 and 14 (candidate pool, greedy
 * fill, alternates) need the food database, which does not exist yet: docs/20 §1 and §6 record that
 * the Indian home-cooked table with household measures has to be built by hand. Until it exists this
 * module produces per-slot *targets* only, and `fillMeals` is deliberately absent rather than faked.
 */

export interface DistributeArgs {
  readonly mealCount: string;
  readonly targetKcal: number;
  readonly proteinTargetG: number;
  readonly abw: number;
  readonly constraints: Constraints;
  readonly pack: RulePack;
}

export function distributeMeals(args: DistributeArgs): readonly MealTarget[] {
  const { mealCount, targetKcal, abw, constraints, pack } = args;
  const pattern = pack.meals.patterns[mealCount];
  if (pattern === undefined) throw new Error(`unknown meal pattern: ${mealCount}`);

  const m = pack.meals;
  const perMealFloor = Math.max(
    m.min_protein_g_per_meal,
    m.min_protein_g_per_kg_abw_per_meal * abw,
  );

  const slots = pattern.map((spec): MealTarget => {
    const isSnack = spec.pct < m.snack_pct_threshold;
    return {
      slot: spec.slot,
      pct: spec.pct,
      kcal: spec.pct * targetKcal,
      minProteinG: isSnack ? m.snack_min_protein_g : perMealFloor,
      optional: spec.optional === true,
    };
  });

  // docs/04 §6 priority 5 — diabetes needs at least N eating occasions.
  const required = constraints.minEatingOccasions;
  if (required !== undefined) {
    const available = slots.filter((s) => !s.optional).length;
    if (available < required) {
      throw new Error(
        `meal pattern "${mealCount}" gives ${available} eating occasions, condition requires ${required}`,
      );
    }
  }

  return slots;
}

/** docs/04 §7 tolerance check, usable once a fill exists. Kept here so the rule has one home. */
export function isWithinTolerance(
  actualKcal: number,
  targetKcal: number,
  slotPct: number,
  pack: RulePack,
): boolean {
  const actualPp = (actualKcal / targetKcal) * 100;
  return Math.abs(actualPp - slotPct * 100) <= pack.meals.tolerance_pp;
}
