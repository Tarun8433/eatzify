/**
 * D-235 — composition pricing in the fill. The rules here are TEST fixtures, not nutrition:
 * the real ones arrive only by a reviewed pack diff (the pack directory is deny-listed).
 */
import { fillMeals } from '../src/fill';
import type { EngineFood } from '../src/foods';
import type { RulePack } from '../src/pack';
import type { Constraints, MealTarget } from '../src/types';

const NO_CONSTRAINTS = {} as unknown as Constraints;

function pack(composition?: RulePack['composition']): RulePack {
  return {
    meals: { fill_max_iterations: 50 },
    rounding: { household_increments: [0.5, 1.0] },
    validation: { kcal_tolerance_pct: 0.03 },
    composition,
  } as unknown as RulePack;
}

function food(over: Partial<EngineFood>): EngineFood {
  return {
    id: 'f',
    name: 'f',
    kcal: 100,
    proteinG: 3,
    fatG: 2,
    carbG: 15,
    fibreG: 1,
    sodiumMg: 5,
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

const LUNCH: MealTarget = { slot: 'lunch', pct: 1, kcal: 400, minProteinG: 0, optional: false };

function fill(pool: EngineFood[], p: RulePack) {
  return fillMeals({
    mealTargets: [LUNCH],
    pool,
    pack: p,
    constraints: NO_CONSTRAINTS,
    proteinTargetG: 12,
    sodiumMaxMg: 1e6,
    addedSugarMaxG: 1e6,
    fatMaxG: 1e6,
    fibreTargetG: 0,
    saturatedFatMaxG: 1e6,
  });
}

describe('composition (D-235)', () => {
  // Identical nutrition, different groups: only composition can tell them apart.
  const sweet = food({ id: 'a-sweet', name: 'sweet', tags: ['group:sugar'] });
  const roti = food({ id: 'b-roti', name: 'roti', tags: ['group:cereal'] });

  const wantCereal: RulePack['composition'] = {
    rules: [{ slots: ['lunch'], require_one_of: [['group:cereal']] }],
  };

  it('prices nothing when the pack carries no block — output unchanged', () => {
    const [meal] = fill([sweet, roti], pack());
    // Nutritionally tied; the deterministic tiebreak picks the lower id.
    expect(meal!.items[0]!.foodId).toBe('a-sweet');
  });

  it('a required group wins an otherwise-tied meal', () => {
    const [meal] = fill([sweet, roti], pack(wantCereal));
    expect(meal!.items.map((i) => i.foodId)).toContain('b-roti');
  });

  it('a three-part rule assembles a three-part meal over a single equal food', () => {
    const trio = [
      food({ id: 'c-rice', tags: ['group:cereal'], kcal: 130 }),
      food({ id: 'd-dal', tags: ['group:pulse'], kcal: 130, proteinG: 8 }),
      food({ id: 'e-sabzi', tags: ['group:veg'], kcal: 130 }),
      // One food that lands the target alone — cheaper on items, structurally empty.
      food({ id: 'a-bar', tags: [], kcal: 400, proteinG: 12 }),
    ];
    const rule: RulePack['composition'] = {
      rules: [
        {
          slots: ['lunch'],
          require_one_of: [['group:cereal'], ['group:pulse'], ['group:veg']],
        },
      ],
    };

    const [plain] = fill(trio, pack());
    expect(plain!.items.map((i) => i.foodId)).toEqual(['a-bar']);

    const [composed] = fill(trio, pack(rule));
    const served = composed!.items.map((i) => i.foodId);
    expect(served).toEqual(expect.arrayContaining(['c-rice', 'd-dal', 'e-sabzi']));
  });

  it('rules for other slots do not touch this one', () => {
    const dinnerOnly: RulePack['composition'] = {
      rules: [{ slots: ['dinner'], require_one_of: [['group:cereal']] }],
    };
    const [meal] = fill([sweet, roti], pack(dinnerOnly));
    expect(meal!.items[0]!.foodId).toBe('a-sweet');
  });
});
