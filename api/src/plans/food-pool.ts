import type { EngineFood } from '@eatzify/diet-engine';
import type { FoodEntity } from '../foods/entities/food.entity';

/**
 * A database row, as the engine needs it (D-164).
 *
 * The engine is pure and never queries — the pool is read here and handed in, which is also what
 * makes a plan reproducible: the same rows produce the same plan forever. This file is the seam,
 * and it is the only place that knows both shapes.
 */

/// Postgres `numeric` arrives as a string, because a float would quietly lose paise-equivalent
/// precision on money and grams on food. Every nutrition column on `food` is numeric.
function num(value: string | number | null | undefined): number {
  return value === null || value === undefined ? 0 : Number(value);
}

/**
 * The serving a plan quotes this food in, default first.
 *
 * Order matters: the engine's fill takes `measures[0]` as the serving it speaks in, so the row
 * flagged `isDefault` has to lead. A food whose default is second would have its plan quoted in
 * whatever measure happened to sort first — "2 tablespoons of rice" rather than "1 katori".
 */
function measuresOf(food: FoodEntity): EngineFood['measures'] {
  const rows = food.measures ?? [];
  const ordered = [...rows].sort((a, b) => {
    if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1;
    // Total order, so the pool is identical between runs (engine rule 2).
    return a.label.localeCompare(b.label);
  });

  return ordered.map((m) => ({ label: m.label, grams: num(m.grams) }));
}

/**
 * Only foods the engine can actually serve.
 *
 * A food with no household measure cannot be quoted in one, and docs/04 §7 is explicit that a plan
 * speaks in katoris and rotis rather than grams. Dropping it here is better than letting the fill
 * skip it silently, because the count is visible to the caller.
 */
export function toEngineFoods(
  rows: readonly FoodEntity[],
): readonly EngineFood[] {
  return rows
    .map((food) => ({
      id: food.id,
      name: food.name,
      kcal: num(food.kcal),
      proteinG: num(food.proteinG),
      fatG: num(food.fatG),
      carbG: num(food.carbG),
      fibreG: num(food.fibreG),
      sodiumMg: num(food.sodiumMg),
      addedSugarG: num(food.addedSugarG),
      saturatedFatG: num(food.saturatedFatG),
      tags: food.tags ?? [],
      suitableFor: food.suitableFor ?? [],
      allergens: food.allergens ?? [],
      costTier: food.costTier,
      measures: measuresOf(food),
    }))
    .filter((food) => food.measures.length > 0);
}
