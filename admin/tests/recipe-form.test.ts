import { describe, expect, it } from 'vitest';
import { EMPTY_RECIPE, matchFoods, toRecipeBody } from '../lib/recipe-form';

describe('toRecipeBody', () => {
  it('should split steps by line and send grams as numbers', () => {
    const body = toRecipeBody({
      ...EMPTY_RECIPE,
      name: ' Moong chilla ',
      servings: '2',
      slots: ['breakfast'],
      steps: 'Soak the dal\n\n  Grind it  \n',
      ingredients: [
        { foodId: 'a', name: 'Moong dal', grams: '100' },
        { foodId: 'b', name: 'Oil', grams: 'abc' },
      ],
    });

    expect(body).toMatchObject({
      name: 'Moong chilla',
      servings: 2,
      steps: ['Soak the dal', 'Grind it'],
      ingredients: [
        { food_id: 'a', grams: 100 },
        { food_id: 'b', grams: 0 },
      ],
    });
  });
});

describe('matchFoods', () => {
  const foods = [
    { id: '1', name: 'Moong dal', nameHi: 'मूंग दाल' },
    { id: '2', name: 'Masoor dal', nameHi: null },
    { id: '3', name: 'Rice', nameHi: null },
  ];

  it('should match name or Hindi name and skip foods already added', () => {
    expect(matchFoods(foods, 'DAL', ['2']).map((f) => f.id)).toEqual(['1']);
    expect(matchFoods(foods, 'मूंग', []).map((f) => f.id)).toEqual(['1']);
  });

  it('should return nothing for an empty query', () => {
    expect(matchFoods(foods, '  ', [])).toEqual([]);
  });
});
