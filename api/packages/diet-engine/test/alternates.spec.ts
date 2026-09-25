/** D-235 — step 14. Swaps stay in-group, in-tolerance, in household increments, deterministic. */
import { pickAlternates } from '../src/alternates';
import type { Meal } from '../src/fill';
import type { EngineFood } from '../src/foods';
import type { RulePack } from '../src/pack';

function pack(alternates?: RulePack['alternates']): RulePack {
  return {
    rounding: { household_increments: [0.5, 1.0] },
    alternates,
  } as unknown as RulePack;
}

const RULES = { kcal_tolerance_pct: 0.1, protein_tolerance_g: 5, max_per_item: 2 };

function food(over: Partial<EngineFood>): EngineFood {
  return {
    id: 'f',
    name: 'f',
    kcal: 300,
    proteinG: 9,
    fatG: 3,
    carbG: 55,
    fibreG: 5,
    sodiumMg: 5,
    addedSugarG: 0,
    saturatedFatG: 0.5,
    tags: ['group:cereal'],
    suitableFor: ['veg'],
    allergens: [],
    costTier: 'low',
    measures: [{ label: 'roti', grams: 100 }],
    ...over,
  };
}

const roti = food({ id: 'roti', name: 'Roti' });

const MEAL: Meal = {
  slot: 'lunch',
  items: [
    {
      foodId: 'roti',
      name: 'Roti',
      measureLabel: 'roti',
      quantity: 1,
      grams: 100,
      kcal: 300,
      proteinG: 9,
      fatG: 3,
      carbG: 55,
      fibreG: 5,
      sodiumMg: 5,
    },
  ],
  kcal: 300,
  proteinG: 9,
  fatG: 3,
  carbG: 55,
  fibreG: 5,
  sodiumMg: 5,
  residualKcal: 0,
  approximated: false,
};

describe('alternates (D-235)', () => {
  const bajra = food({ id: 'bajra', name: 'Bajra roti', kcal: 290, proteinG: 10 });
  const rice = food({ id: 'rice', name: 'Rice', kcal: 150, proteinG: 3, measures: [{ label: 'katori', grams: 100 }] });
  const sweet = food({ id: 'sweet', name: 'Gulab jamun', tags: ['group:sugar'] });
  const distant = food({ id: 'distant', name: 'Khakhra', kcal: 1200 });

  it('offers same-group foods inside both tolerances, in household portions', () => {
    const out = pickAlternates([MEAL], [roti, bajra, rice, sweet], pack(RULES));
    expect(out).toHaveLength(1);
    const options = out[0]!.alternates;
    // Two katori of rice land EXACTLY on 300 kcal, so rice sorts before bajra's 290.
    expect(options.map((o) => o.foodId)).toEqual(['rice', 'bajra']);
    // The portion is fitted, not copied.
    expect(options[0]!.quantity).toBe(2);
    for (const o of options) {
      expect(Math.abs(o.kcal - 300)).toBeLessThanOrEqual(30);
    }
  });

  it('never crosses groups, and drops portions outside tolerance', () => {
    const out = pickAlternates([MEAL], [roti, sweet, distant], pack(RULES));
    // sweet is another group; distant cannot make 300 kcal inside 10 % on half-serving steps.
    expect(out).toHaveLength(0);
  });

  it('a pack without the block offers nothing', () => {
    expect(pickAlternates([MEAL], [roti, bajra], pack())).toEqual([]);
  });

  it('caps at max_per_item and is deterministic', () => {
    const third = food({ id: 'jowar', name: 'Jowar roti', kcal: 305 });
    const out = pickAlternates([MEAL], [roti, bajra, rice, third], pack(RULES));
    expect(out[0]!.alternates.map((o) => o.foodId)).toEqual(['rice', 'jowar']);
  });
});
