/**
 * docs/04 §2 step 14 — pick alternates (D-235).
 *
 * An alternate answers one question: "I don't want this item — what else keeps the meal true?"
 * A swap must therefore stay in the same `group:` (a roti swaps for another cereal, never for a
 * gulab jamun), land within the pack's kcal tolerance of the item it replaces, stay within its
 * protein tolerance, and speak in household increments like everything else the plan says.
 *
 * Pure and deterministic like the fill: same meals, same pool, same pack — same alternates,
 * forever. A pack without an `alternates` block gets none, and a food without a `group:` tag
 * offers none: the engine does not guess what counts as "the same kind of food".
 */

import { increment, MAX_SERVINGS_PER_FOOD } from './fill';
import type { Meal, MealItem } from './fill';
import type { EngineFood } from './foods';
import type { RulePack } from './pack';

export interface AlternateItem {
  readonly foodId: string;
  readonly name: string;
  readonly measureLabel: string;
  readonly quantity: number;
  readonly grams: number;
  readonly kcal: number;
  readonly proteinG: number;
}

/** The swaps on offer for ONE served item. Items with no admissible swap are simply absent. */
export interface ItemAlternates {
  readonly slot: string;
  readonly foodId: string;
  readonly alternates: readonly AlternateItem[];
}

const GROUP_PREFIX = 'group:';

export function pickAlternates(
  meals: readonly Meal[],
  pool: readonly EngineFood[],
  pack: RulePack,
): readonly ItemAlternates[] {
  const rules = pack.alternates;
  if (rules === undefined) return [];

  const step = increment(pack);
  const byId = new Map(pool.map((food) => [food.id, food]));
  const out: ItemAlternates[] = [];

  for (const meal of meals) {
    const served = new Set(meal.items.map((item) => item.foodId));

    for (const item of meal.items) {
      const food = byId.get(item.foodId);
      if (food === undefined) continue;

      const groups = food.tags.filter((tag) => tag.startsWith(GROUP_PREFIX));
      if (groups.length === 0) continue;

      const options = pool
        .filter(
          (alt) =>
            alt.id !== food.id &&
            !served.has(alt.id) &&
            alt.tags.some((tag) => groups.includes(tag)),
        )
        .flatMap((alt) => {
          const swap = portionMatching(item, alt, step, rules);
          return swap === null ? [] : [swap];
        })
        .sort(
          (a, b) =>
            Math.abs(a.kcal - item.kcal) - Math.abs(b.kcal - item.kcal) ||
            a.foodId.localeCompare(b.foodId),
        )
        .slice(0, rules.max_per_item);

      if (options.length > 0) {
        out.push({ slot: meal.slot, foodId: item.foodId, alternates: options });
      }
    }
  }

  return out;
}

/**
 * The household portion of [alt] closest in energy to [item], or null when no portion the fill
 * itself would serve can stay inside the pack's tolerances.
 */
function portionMatching(
  item: MealItem,
  alt: EngineFood,
  step: number,
  rules: NonNullable<RulePack['alternates']>,
): AlternateItem | null {
  const measure = alt.measures[0];
  if (measure === undefined) return null;

  const perStepKcal = (alt.kcal * measure.grams * step) / 100;
  if (perStepKcal <= 0) return null;

  const increments = Math.max(1, Math.round(item.kcal / perStepKcal));
  const quantity = increments * step;
  if (quantity > MAX_SERVINGS_PER_FOOD) return null;

  const grams = measure.grams * quantity;
  const kcal = (alt.kcal * grams) / 100;
  const proteinG = (alt.proteinG * grams) / 100;

  const kcalOk =
    Math.abs(kcal - item.kcal) <= item.kcal * rules.kcal_tolerance_pct;
  const proteinOk =
    Math.abs(proteinG - item.proteinG) <= rules.protein_tolerance_g;
  if (!kcalOk || !proteinOk) return null;

  return {
    foodId: alt.id,
    name: alt.name,
    measureLabel: measure.label,
    quantity,
    grams,
    kcal,
    proteinG,
  };
}
