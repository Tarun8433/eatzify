import { toEngineFoods } from '../src/plans/food-pool';
import type { FoodEntity } from '../src/foods/entities/food.entity';

/// D-164. The seam between a database row and the pure engine. Everything that can go wrong here
/// is silent: a numeric read as a string, a default measure that is not first, a food with no
/// serving at all.

function row(over: Partial<FoodEntity> = {}): FoodEntity {
  return {
    id: 'dal',
    name: 'Dal',
    kcal: '120.00',
    proteinG: '8.00',
    fatG: '3.00',
    carbG: '16.00',
    fibreG: '4.00',
    sodiumMg: '200.00',
    addedSugarG: '0.00',
    saturatedFatG: '1.00',
    tags: ['gi:low'],
    suitableFor: ['veg'],
    allergens: [],
    costTier: 'low',
    measures: [{ label: 'katori', grams: '150.0', isDefault: true }],
    ...over,
  } as unknown as FoodEntity;
}

function only<T>(xs: readonly T[]): T {
  const [first] = xs;
  if (first === undefined) throw new Error('expected at least one element');
  return first;
}

describe('toEngineFoods', () => {
  /// Postgres numeric arrives as a string. Left as one, `kcal * factor` is a string concatenation
  /// or a NaN, and every meal total downstream is wrong without anything throwing.
  it('should read numeric columns as numbers when the row carries strings', () => {
    const food = only(toEngineFoods([row()]));

    expect(food.kcal).toBe(120);
    expect(food.proteinG).toBe(8);
    expect(only(food.measures).grams).toBe(150);
  });

  /// The fill quotes `measures[0]`. A default that is not first means the plan is written in the
  /// wrong unit — "2 tablespoons of rice" where it should read "1 katori".
  it('should put the default measure first when it is not first in the row', () => {
    const food = only(
      toEngineFoods([
        row({
          measures: [
            { label: 'tablespoon', grams: '15.0', isDefault: false },
            { label: 'katori', grams: '150.0', isDefault: true },
          ],
        } as unknown as Partial<FoodEntity>),
      ]),
    );

    expect(only(food.measures).label).toBe('katori');
  });

  /// docs/04 §7: a plan speaks in household measures. A food with none cannot be quoted in one,
  /// so it never reaches the engine.
  it('should drop a food with no household measure when the row has none', () => {
    const pool = toEngineFoods([
      row({ measures: [] } as unknown as Partial<FoodEntity>),
    ]);

    expect(pool).toEqual([]);
  });

  /// Engine rule 2: same input, byte-identical output. Two measures that are both non-default
  /// must not swap places between runs.
  it('should order measures identically when two are equally default', () => {
    const measures = [
      { label: 'bowl', grams: '200.0', isDefault: false },
      { label: 'katori', grams: '150.0', isDefault: false },
    ];

    const forward = toEngineFoods([
      row({ measures } as unknown as Partial<FoodEntity>),
    ]);
    const reversed = toEngineFoods([
      row({
        measures: [...measures].reverse(),
      } as unknown as Partial<FoodEntity>),
    ]);

    expect(JSON.stringify(forward)).toBe(JSON.stringify(reversed));
  });

  /// The three columns the pool builder filters on. An undefined array there would throw inside
  /// the engine, which is the one place that must not have to defend itself.
  it('should default the tag arrays when the row omits them', () => {
    const food = only(
      toEngineFoods([
        row({
          tags: undefined,
          suitableFor: undefined,
          allergens: undefined,
        } as unknown as Partial<FoodEntity>),
      ]),
    );

    expect(food.tags).toEqual([]);
    expect(food.suitableFor).toEqual([]);
    expect(food.allergens).toEqual([]);
  });
});
