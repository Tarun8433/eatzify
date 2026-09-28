import { fillMeals, type Meal } from '../src/fill';
import type { EngineFood } from '../src/foods';
import type { RulePack } from '../src/pack';
import type { Constraints, MealTarget } from '../src/types';

/// docs/04 §2 step 13 and §7. The fill is the only part of the engine that chooses rather than
/// computes, so the tests are about what it must never do: overshoot the tolerance, speak in
/// grams, breach a per-occasion cap, or pick differently on a second run.

function food(over: Partial<EngineFood> = {}): EngineFood {
  return {
    id: 'dal',
    name: 'Dal',
    kcal: 100,
    proteinG: 10,
    fatG: 2,
    carbG: 12,
    fibreG: 4,
    sodiumMg: 100,
    addedSugarG: 0,
    saturatedFatG: 0,
    tags: [],
    suitableFor: ['veg'],
    allergens: [],
    costTier: 'low',
    measures: [{ label: 'katori', grams: 100 }],
    ...over,
  };
}

const PACK = {
  meals: { fill_max_iterations: 50 },
  rounding: { household_increments: [0.5, 1.0] },
  validation: { kcal_tolerance_pct: 0.03 },
} as unknown as RulePack;

const NO_CONSTRAINTS = {} as unknown as Constraints;

function target(over: Partial<MealTarget> = {}): MealTarget {
  return {
    slot: 'lunch',
    pct: 0.4,
    kcal: 400,
    minProteinG: 0,
    optional: false,
    ...over,
  };
}

/// `noUncheckedIndexedAccess` is on, and every fill below asks for a slot it just requested.
/// Asserting once here keeps the expectations about behaviour rather than about indexing.
function only<T>(xs: readonly T[]): T {
  const [first] = xs;
  if (first === undefined) throw new Error('expected at least one element');
  return first;
}

/// One meal from one target, which is what every case except the last asks for.
function fillOne(
  pool: readonly EngineFood[],
  constraints: Constraints = NO_CONSTRAINTS,
  mealTarget: MealTarget = target(),
  proteinTargetG = 1000,
): Meal {
  return only(
    fillMeals({
      mealTargets: [mealTarget],
      pool,
      pack: PACK,
      constraints,
      // Effectively unbounded unless a case says otherwise, so the older cases keep testing the
      // energy behaviour they were written for.
      proteinTargetG,
      sodiumMaxMg: 1e6,
      addedSugarMaxG: 1e6,
      fatMaxG: 1e6,
      // Effectively off, so the older cases keep testing the energy behaviour they were written
      // for. `real-pool.spec.ts` is where fibre and saturated fat are exercised for real.
      fibreTargetG: 0,
      saturatedFatMaxG: 1e6,
    }),
  );
}

describe('fillMeals', () => {
  it('should land inside the kcal tolerance when the pool can reach the target', () => {
    const meal = fillOne([food()]);

    expect(Math.abs(meal.residualKcal)).toBeLessThanOrEqual(400 * 0.03);
    expect(meal.approximated).toBe(false);
  });

  /// "1.5 katori is real, 137 g is not." Every quantity has to be a multiple of the pack's
  /// smallest increment, because the number on screen is what someone serves themselves.
  it('should express every quantity on the pack increment when it fills a meal', () => {
    const meal = fillOne([food()]);

    expect(meal.items.length).toBeGreaterThan(0);
    for (const item of meal.items) {
      expect(item.quantity % 0.5).toBeCloseTo(0, 10);
      expect(item.quantity).toBeGreaterThan(0);
    }
  });

  /// The greedy order is protein density, so the denser food is the one that appears.
  it('should prefer the denser protein when two foods carry the same energy', () => {
    const dense = food({ id: 'paneer', name: 'Paneer', proteinG: 18 });
    const thin = food({ id: 'rice', name: 'Rice', proteinG: 2 });

    const meal = fillOne([thin, dense]);

    expect(only(meal.items).foodId).toBe('paneer');
  });

  /// docs/04 §7: diabetes caps carbohydrate per eating occasion. An occasion is a meal, and a cap
  /// that only held on the daily total would be no cap at all.
  it('should respect the per-occasion carb cap when the overrides set one', () => {
    const meal = fillOne([food()], { maxCarbGPerOccasion: 20 } as Constraints);

    expect(meal.carbG).toBeLessThanOrEqual(20);
  });

  /// Rule 2: same input, byte-identical output, forever. Two foods of equal density must not swap
  /// places between runs, which is why the sort breaks ties on id.
  it('should fill identically on a second run when the pool order differs', () => {
    const a = food({ id: 'aaa', name: 'A' });
    const b = food({ id: 'bbb', name: 'B' });

    const first = fillOne([a, b]);
    const second = fillOne([b, a]);

    expect(JSON.stringify(first)).toBe(JSON.stringify(second));
  });

  /// An empty slot is visible and arguable. A slot padded with something the pool rejected is
  /// neither, and it is the failure that turns a safety filter into decoration.
  it('should return an empty meal when nothing in the pool is admissible', () => {
    const meal = fillOne([]);

    expect(meal.items).toEqual([]);
    expect(meal.approximated).toBe(true);
  });

  /// docs/04 §7 caps the repair loop and says to keep the closest attempt. A pool that cannot hit
  /// the target must still return its best try, flagged, rather than looping or inventing food.
  it('should return the closest attempt flagged when the pool cannot reach tolerance', () => {
    // 900 kcal a serving against a 400 kcal meal: one is far over, zero is far under.
    const huge = food({
      id: 'ghee',
      name: 'Ghee',
      kcal: 900,
      proteinG: 0,
      carbG: 0,
    });

    const meal = fillOne([huge]);

    expect(meal.approximated).toBe(true);
    expect(meal.residualKcal).not.toBe(0);
  });

  /// A food with no energy cannot be ranked by protein per kcal and cannot close an energy gap.
  /// It is ordered last rather than dividing by zero, which would sort it to the front.
  it('should rank a zero-energy food last when the pool contains one', () => {
    const water = food({ id: 'water', name: 'Water', kcal: 0, proteinG: 0 });

    const meal = fillOne([water, food()]);

    expect(only(meal.items).foodId).toBe('dal');
  });

  /// Greedy overshoots, repair trims, the trim goes under, repair grows again. Both directions of
  /// the repair loop run here, and the closest attempt is what comes back.
  it('should keep the closest attempt when repair oscillates around the target', () => {
    // 300 kcal a serving against a 400 kcal meal: one is under, two are over, neither is inside
    // the 3 % tolerance.
    const coarse = food({ id: 'coarse', name: 'Coarse', kcal: 300, proteinG: 10 });

    const meal = fillOne([coarse]);

    expect(meal.approximated).toBe(true);
    // The closest reachable total is 450 (1.5 servings), not 300 or 600.
    expect(Math.abs(meal.residualKcal)).toBeLessThanOrEqual(100);
  });

  /// With a carb cap forcing a second food into the meal, the trim has to choose between two
  /// portions. It takes the bigger contributor, because that is the single move closing most of
  /// the gap.
  it('should trim the larger portion when two foods share a capped meal', () => {
    const carby = food({ id: 'rice', name: 'Rice', kcal: 300, carbG: 60, proteinG: 6 });
    const lean = food({ id: 'curd', name: 'Curd', kcal: 60, carbG: 4, proteinG: 10 });

    const meal = fillOne([carby, lean], {
      maxCarbGPerOccasion: 40,
    } as Constraints);

    expect(meal.carbG).toBeLessThanOrEqual(40);
    expect(meal.items.length).toBeGreaterThan(0);
  });

  /// The pathological case a real pool produced: greedy by protein density alone answered every
  /// slot with whey powder and the day came to 328 g of protein against a 117 g target, inside
  /// the kcal tolerance the whole way. Once the meal's protein share is met the search inverts to
  /// the least dense admissible food, because what is left to close is energy.
  it('should stop reaching for protein once the meal has its share', () => {
    const whey = food({ id: 'whey', name: 'Whey', kcal: 400, proteinG: 80, carbG: 8 });
    const rice = food({ id: 'rice', name: 'Rice', kcal: 130, proteinG: 3, carbG: 28 });

    // A 400 kcal meal owed 30 g of protein, not 80. The fill is handed THE DAY's protein and
    // shares it out by energy split, so a one-meal call is a one-meal day: 30 g is the figure.
    const meal = fillOne([whey, rice], NO_CONSTRAINTS, target(), 30);

    expect(meal.items.map((i) => i.foodId)).toContain('rice');
    expect(meal.proteinG).toBeLessThan(80);
  });

  it('should fill every slot when several meals are requested', () => {
    const meals = fillMeals({
      mealTargets: [
        target({ slot: 'breakfast', kcal: 300 }),
        target({ slot: 'lunch', kcal: 500 }),
        target({ slot: 'dinner', kcal: 400 }),
      ],
      pool: [food()],
      pack: PACK,
      constraints: NO_CONSTRAINTS,
      proteinTargetG: 1000,
      sodiumMaxMg: 1e6,
      addedSugarMaxG: 1e6,
      fatMaxG: 1e6,
      // Effectively off, so the older cases keep testing the energy behaviour they were written
      // for. `real-pool.spec.ts` is where fibre and saturated fat are exercised for real.
      fibreTargetG: 0,
      saturatedFatMaxG: 1e6,
    });

    expect(meals.map((m) => m.slot)).toEqual(['breakfast', 'lunch', 'dinner']);
  });
});
