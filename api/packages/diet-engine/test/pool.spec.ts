import { buildPool, type EngineFood } from '../src/foods';
import type { Constraints, EngineInput } from '../src/types';

/// docs/04 §2 step 11. The pool is a filter, not a ranking — and the one thing it must never do is
/// silently pass a food the user cannot eat.

function food(over: Partial<EngineFood> = {}): EngineFood {
  return {
    id: 'f1',
    name: 'Dal',
    kcal: 120,
    proteinG: 8,
    fatG: 3,
    carbG: 16,
    fibreG: 4,
    sodiumMg: 200,
    addedSugarG: 0,
    saturatedFatG: 1,
    tags: [],
    suitableFor: ['veg', 'vegan', 'non_veg', 'eggetarian'],
    allergens: [],
    costTier: 'low',
    measures: [{ label: 'katori', grams: 150 }],
    ...over,
  };
}

const INPUT = {
  foodPreference: 'veg',
  foodAllergies: [],
} as unknown as EngineInput;

const NO_CONSTRAINTS = {
  excludeTags: [],
  preferTags: [],
} as unknown as Constraints;

describe('buildPool', () => {
  it('should keep a food the person can eat when nothing excludes it', () => {
    const pool = buildPool([food()], INPUT, NO_CONSTRAINTS);

    expect(pool.foods).toHaveLength(1);
  });

  it('should drop a food outside the diet preference when the preference is veg', () => {
    const chicken = food({ id: 'f2', suitableFor: ['non_veg'] });

    const pool = buildPool([chicken], INPUT, NO_CONSTRAINTS);

    expect(pool.foods).toHaveLength(0);
    expect(pool.rejected.food_preference).toBe(1);
  });

  /// The user's own allergies are not a pack concern and nothing may override them.
  it('should drop a food carrying a declared allergen when the user declared it', () => {
    const peanutty = food({ id: 'f3', allergens: ['peanut'] });

    const pool = buildPool(
      [peanutty],
      { ...INPUT, foodAllergies: ['peanut'] } as EngineInput,
      NO_CONSTRAINTS,
    );

    expect(pool.foods).toHaveLength(0);
    expect(pool.rejected.allergy).toBe(1);
  });

  it('should drop a food carrying an excluded tag when the pack excludes it', () => {
    const fried = food({ id: 'f4', tags: ['attr:deep_fried'] });

    const pool = buildPool([fried], INPUT, {
      ...NO_CONSTRAINTS,
      excludeTags: ['attr:deep_fried'],
    } as Constraints);

    expect(pool.foods).toHaveLength(0);
    expect(pool.rejected.excluded_tag).toBe(1);
  });

  /// The failure this translation exists to prevent. A pack writes `allergen:peanut`; the food
  /// table keeps allergens in their own column and the tag vocabulary forbids that prefix. Matched
  /// against `tags` the exclusion hits nothing, and a peanut allergy filters no peanuts.
  it('should resolve an allergen-prefixed exclusion against the allergens column', () => {
    const peanutty = food({ id: 'f5', allergens: ['peanut'], tags: [] });

    const pool = buildPool([peanutty], INPUT, {
      ...NO_CONSTRAINTS,
      excludeTags: ['allergen:peanut'],
    } as Constraints);

    expect(pool.foods).toHaveLength(0);
  });

  /// v1.0.0 writes `group:egg`, `group:fish`, `group:meat`: food CATEGORIES to exclude, not diet
  /// groups to require. Read as a requirement they reject every food that is not an egg — 250 of
  /// 281 for a vegetarian, which empties the pool and ships a plan with no food in it.
  it('should exclude a group-tagged food when the pack names that group', () => {
    const eggy = food({ id: 'f6', tags: ['group:egg'] });
    const plain = food({ id: 'f7', tags: [] });

    const pool = buildPool([eggy, plain], INPUT, {
      ...NO_CONSTRAINTS,
      excludeTags: ['group:egg'],
    } as Constraints);

    expect(pool.foods.map((f) => f.id)).toEqual(['f7']);
  });

  /// The same exclusion against seed data that carries no such tag. It must match NOTHING — the
  /// pack names groups the 281-food seed never tagged (D-134's data debt), and an exclusion that
  /// cannot find its target has to be inert, not total.
  it('should match nothing when the group tag is absent from every food', () => {
    const pool = buildPool([food({ id: 'f8' }), food({ id: 'f9' })], INPUT, {
      ...NO_CONSTRAINTS,
      excludeTags: ['group:egg', 'group:fish', 'group:meat'],
    } as Constraints);

    expect(pool.foods).toHaveLength(2);
  });

  /// preferTags says what to reach for first, which is step 13's decision. Applied as a filter it
  /// would shrink the pool until the fill cannot reach the target at all.
  it('should not filter on preferred tags when the pack expresses a preference', () => {
    const plain = food({ id: 'f8', tags: [] });

    const pool = buildPool([plain], INPUT, {
      ...NO_CONSTRAINTS,
      preferTags: ['attr:high_fibre'],
    } as Constraints);

    expect(pool.foods).toHaveLength(1);
  });

  it('should count every rejection reason when several foods fail for different reasons', () => {
    const pool = buildPool(
      [
        food({ id: 'a', suitableFor: ['non_veg'] }),
        food({ id: 'b', allergens: ['peanut'] }),
        food({ id: 'c' }),
      ],
      { ...INPUT, foodAllergies: ['peanut'] } as EngineInput,
      NO_CONSTRAINTS,
    );

    expect(pool.foods.map((f) => f.id)).toEqual(['c']);
    expect(pool.rejected).toEqual({ food_preference: 1, allergy: 1 });
  });
});
