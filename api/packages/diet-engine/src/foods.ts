/**
 * docs/04 §2 step 11 — build the candidate pool.
 *
 * The engine never reads the food table. The caller queries it and hands the rows in (rule 2:
 * pure, no I/O), which is also what makes a plan reproducible: same pool in, same plan out.
 */

import type { Constraints, EngineInput, FoodPreference } from './types';

/** One serving the plan can speak in. `1.5 katori` is real; `137 g` is not (docs/04 §7). */
export interface EngineMeasure {
  readonly label: string;
  readonly grams: number;
}

/**
 * A food, as the engine needs it. Deliberately smaller than the database row: no images, no
 * provenance, no aliases. Nutrition is per 100 g edible portion, matching docs/03 and the
 * food table.
 */
export interface EngineFood {
  readonly id: string;
  readonly name: string;
  readonly kcal: number;
  readonly proteinG: number;
  readonly fatG: number;
  readonly carbG: number;
  readonly fibreG: number;
  readonly sodiumMg: number;
  readonly addedSugarG: number;
  readonly saturatedFatG: number;
  /** Namespaced, as stored: `gi:high`, `attr:root_veg`. Never an allergen or a diet group. */
  readonly tags: readonly string[];
  /** Diet groups this food is fit for: `veg`, `vegan`, `jain`, … */
  readonly suitableFor: readonly string[];
  readonly allergens: readonly string[];
  readonly costTier: string;
  readonly measures: readonly EngineMeasure[];
}

/**
 * The rule pack writes allergen exclusions in its own namespace; the food table keeps allergens in
 * their own column, and the tag vocabulary forbids the prefix. Without this translation every
 * allergen exclusion in a pack silently matches nothing, which is the worst failure available
 * here: a peanut allergy that filters no peanuts.
 *
 * `group:` needs NO translation, and assuming it did was a bug worth recording. v1.0.0 writes
 * `group:egg`, `group:fish`, `group:meat` — food CATEGORIES to exclude, not diet groups to
 * require. Read as a requirement they rejected every food that was not an egg: 250 of 281 for a
 * vegetarian, leaving an empty pool and a plan with no food in it. They are ordinary tags.
 */
const ALLERGEN_PREFIX = 'allergen:';

/**
 * A food nobody is served a portion of on its own — flour, raw semolina, gram flour (D-231).
 *
 * They belong in the table: people search for them and log them, and a recipe is made of them. They
 * do not belong in a PLAN, and without this the fill answered a 2,700 kcal day with three cups of
 * raw rava, which is nutritionally exact and not food.
 *
 * `attr:ingredient` rather than docs/03's `prep:raw`, because raw is not the question: raw onion and
 * raw tomato are salad. The question is whether it is a dish, and only this tag answers it. The
 * `attr:` namespace is already wider than docs/03 §4 lists (`attr:sugary`, `attr:hydrating` are in
 * the seed data), so this extends a list that was already extended rather than opening a new one.
 */
const NOT_SERVABLE = 'attr:ingredient';

/** A diet preference is a claim about every item, so it filters before anything else. */
function suitsPreference(
  food: EngineFood,
  preference: FoodPreference,
): boolean {
  return food.suitableFor.includes(preference);
}

function hasAllergen(food: EngineFood, allergen: string): boolean {
  return food.allergens.includes(allergen);
}

/** One exclusion from the pack, resolved against whichever column actually holds it. */
function excludedBy(food: EngineFood, exclusion: string): boolean {
  if (exclusion.startsWith(ALLERGEN_PREFIX)) {
    return hasAllergen(food, exclusion.slice(ALLERGEN_PREFIX.length));
  }
  return food.tags.includes(exclusion);
}

export interface PoolResult {
  readonly foods: readonly EngineFood[];
  /** Why the pool is the size it is — the trace has to be able to explain an empty one. */
  readonly rejected: Readonly<Record<string, number>>;
}

/**
 * Filters only. Ordering and selection are step 13's job.
 *
 * Nothing here is a preference weighting: a food is either eatable by this person or it is not.
 * `preferTags` and `costLowFraction` express what to reach for FIRST, which is a fill decision,
 * so they are deliberately not applied as filters — applied here they would shrink the pool to
 * the point where the fill cannot hit a target at all.
 */
export function buildPool(
  foods: readonly EngineFood[],
  input: EngineInput,
  constraints: Constraints,
): PoolResult {
  const rejected: Record<string, number> = {};
  const reject = (reason: string): false => {
    rejected[reason] = (rejected[reason] ?? 0) + 1;
    return false;
  };

  const kept = foods.filter((food) => {
    if (food.tags.includes(NOT_SERVABLE)) return reject('ingredient');

    if (!suitsPreference(food, input.foodPreference)) {
      return reject('food_preference');
    }

    // The user's own allergies, which are not a pack concern and are never overridable.
    if (input.foodAllergies.some((a) => hasAllergen(food, a))) {
      return reject('allergy');
    }

    if (constraints.excludeTags.some((tag) => excludedBy(food, tag))) {
      return reject('excluded_tag');
    }

    return true;
  });

  return { foods: kept, rejected };
}
