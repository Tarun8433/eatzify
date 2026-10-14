import { describe, expect, it } from 'vitest';
import { EMPTY_FOOD, foodErrorLines, toFoodRow } from '../lib/food-form';

describe('toFoodRow', () => {
  it('should send the importer column set with lists joined by |', () => {
    const row = toFoodRow({
      ...EMPTY_FOOD,
      name: ' Moong dal ',
      aliases: 'mung dal, , green gram ',
      kcal: '104',
      proteinG: '7',
      fatG: '0.4',
      carbG: '18',
      suitableFor: ['veg', 'vegan'],
      allergens: [],
      measures: 'katori=150*',
    });

    expect(row).toMatchObject({
      name: 'Moong dal',
      aliases: 'mung dal|green gram',
      suitableFor: 'veg|vegan',
      allergens: '',
      measures: 'katori=150*',
      costTier: 'medium',
      source: 'manual',
    });
  });
});

describe('foodErrorLines', () => {
  it('should list each problem when the API refuses a food as FOOD_INVALID', () => {
    const body = {
      error: {
        code: 'FOOD_INVALID',
        user_message: '2 problem(s) with this food. Nothing was saved.',
        details: {
          errors: [
            { row: 1, field: 'kcal', message: 'kcal is required' },
            { row: 1, field: 'source', message: 'source is required' },
          ],
        },
      },
    };
    expect(foodErrorLines(body)).toEqual(['kcal: kcal is required', 'source: source is required']);
  });

  it('should fall back to the user message, then a sentence, when there are no details', () => {
    expect(foodErrorLines({ error: { user_message: 'Not allowed.' } })).toEqual(['Not allowed.']);
    expect(foodErrorLines({ error: 'Session expired.' })).toEqual(['Session expired.']);
    expect(foodErrorLines(null)).toEqual(['The food could not be saved.']);
  });
});
