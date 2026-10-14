import {
  allergens,
  perServing,
  recipeProblems,
  suitableFor,
  type IngredientFood,
} from '../src/recipes/recipe-rules';

const food = (over: Partial<IngredientFood>): IngredientFood => ({
  kcal: '100',
  proteinG: '10',
  carbG: '10',
  fatG: '2',
  fibreG: '1',
  sodiumMg: '0',
  addedSugarG: '0',
  saturatedFatG: '0',
  suitableFor: ['veg', 'vegan', 'jain', 'eggetarian', 'non_veg'],
  allergens: [],
  ...over,
});

const draft = {
  name: 'Moong chilla',
  servings: 2,
  slots: ['breakfast'],
  steps: ['Mix', 'Cook'],
  ingredients: [{ foodId: 'a', grams: 100 }],
};

describe('recipe rules', () => {
  it('should divide the summed ingredient nutrition by servings', () => {
    const n = perServing(
      [
        { food: food({ kcal: '200', proteinG: '20' }), grams: 100 },
        { food: food({ kcal: '100', proteinG: '0' }), grams: 50 },
      ],
      2,
    );
    // (200 + 50) / 2 and (20 + 0) / 2.
    expect(n).toMatchObject({ grams: 75, kcal: 125, protein_g: 10 });
  });

  it('should suit only the preferences every ingredient suits', () => {
    const egg = food({ suitableFor: ['eggetarian', 'non_veg'] });
    const dal = food({
      suitableFor: ['veg', 'vegan', 'eggetarian', 'non_veg'],
    });
    expect(
      suitableFor([
        { food: egg, grams: 50 },
        { food: dal, grams: 100 },
      ]),
    ).toEqual(['eggetarian', 'non_veg']);
    expect(suitableFor([])).toEqual([]);
  });

  it('should carry every allergen any ingredient has, once', () => {
    expect(
      allergens([
        { food: food({ allergens: ['milk'] }), grams: 1 },
        { food: food({ allergens: ['milk', 'wheat_gluten'] }), grams: 1 },
      ]),
    ).toEqual(['milk', 'wheat_gluten']);
  });

  it('should accept a complete draft', () => {
    expect(recipeProblems(draft)).toEqual([]);
  });

  it('should list every problem with an incomplete draft', () => {
    const problems = recipeProblems({
      name: ' ',
      servings: 0,
      slots: ['brunch'],
      steps: [],
      ingredients: [
        { foodId: 'a', grams: 0 },
        { foodId: 'a', grams: 10 },
      ],
    });
    expect(problems).toEqual(
      expect.arrayContaining([
        'name: a name is required',
        expect.stringMatching(/^servings:/),
        'slots: "brunch" is not a meal',
        'ingredients: a food is listed twice',
        expect.stringMatching(/^ingredients: grams/),
      ]),
    );
  });
});
