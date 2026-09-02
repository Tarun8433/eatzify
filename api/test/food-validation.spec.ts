import {
  KNOWN_COLUMNS,
  unknownColumns,
  validateRow,
} from '../src/foods/food-validation';

/// A bad row here reaches somebody's plan, so these are the checks that must not regress.
const valid: Record<string, string> = {
  name: 'Dal (arhar cooked)',
  kcal: '116',
  proteinG: '6.8',
  fatG: '2.7',
  carbG: '16.0',
  tags: 'gi:low|attr:high_fibre',
  suitableFor: 'veg|vegan',
  allergens: '',
  source: 'IFCT2017',
  measures: 'katori=150*',
  aliases: 'dal|toor dal|arhar',
};

const rowFrom = (overrides: Record<string, string>) =>
  validateRow({ ...valid, ...overrides }, 2);

describe('food import validation', () => {
  it('accepts a well-formed row', () => {
    const { food, errors } = rowFrom({});

    expect(errors).toEqual([]);
    expect(food?.name).toBe('Dal (arhar cooked)');
    expect(food?.measures).toEqual([
      { label: 'katori', grams: 150, isDefault: true },
    ]);
  });

  it('rejects a tag outside the rule pack vocabulary', () => {
    // The rule pack matches exact strings — a typo would silently drop this food from a
    // medical constraint rather than erroring at runtime.
    const { errors } = rowFrom({ tags: 'lowgi' });

    expect(errors.some((e) => e.field === 'tags')).toBe(true);
  });

  it('rejects an unknown allergen rather than storing it', () => {
    const { errors } = rowFrom({ allergens: 'peanuts' });

    expect(errors.some((e) => e.field === 'allergens')).toBe(true);
  });

  it('accepts the correctly spelled allergen', () => {
    expect(rowFrom({ allergens: 'peanut|milk' }).errors).toEqual([]);
  });

  it('catches a column typed into the wrong field via the calorie cross-check', () => {
    // 116 kcal cannot come from 30 g of protein — this is the most common spreadsheet error.
    const { errors } = rowFrom({ proteinG: '30' });

    expect(errors.some((e) => e.field === 'kcal')).toBe(true);
  });

  it('rejects macros exceeding the 100 g portion', () => {
    const { errors } = rowFrom({
      proteinG: '50',
      fatG: '30',
      carbG: '40',
      kcal: '630',
    });

    expect(errors.some((e) => e.field === 'macros')).toBe(true);
  });

  it('requires a source — an unattributable number cannot be corrected later', () => {
    expect(
      rowFrom({ source: '' }).errors.some((e) => e.field === 'source'),
    ).toBe(true);
  });

  it('requires at least one food preference', () => {
    expect(
      rowFrom({ suitableFor: '' }).errors.some(
        (e) => e.field === 'suitableFor',
      ),
    ).toBe(true);
  });

  it('rejects a malformed measure', () => {
    expect(
      rowFrom({ measures: 'katori' }).errors.some(
        (e) => e.field === 'measures',
      ),
    ).toBe(true);
    expect(
      rowFrom({ measures: 'katori=0' }).errors.some(
        (e) => e.field === 'measures',
      ),
    ).toBe(true);
  });

  it('makes the first measure the default when none is starred', () => {
    const { food } = rowFrom({ measures: 'katori=150|bowl=200' });

    expect(food?.measures[0].isDefault).toBe(true);
    expect(food?.measures[1].isDefault).toBe(false);
  });

  it('honours an explicitly starred default', () => {
    const { food } = rowFrom({ measures: 'katori=150|bowl=200*' });

    expect(food?.measures[1].isDefault).toBe(true);
  });

  it('reports the spreadsheet row number, not the array index', () => {
    const { errors } = validateRow({ ...valid, name: '' }, 7);

    expect(errors[0].row).toBe(7);
  });

  it('collects every problem in a row rather than stopping at the first', () => {
    const { errors } = rowFrom({ name: '', source: '', suitableFor: '' });

    expect(errors.length).toBeGreaterThanOrEqual(3);
  });
});

describe('aliases', () => {
  it('splits and lower-cases what people actually type', () => {
    // A food nobody can find is a food nobody logs, and an unlogged meal is a hole in the diary.
    const { food } = rowFrom({ aliases: 'Chapati|PHULKA|roti ' });

    expect(food?.aliases).toEqual(['chapati', 'phulka', 'roti']);
  });

  it('accepts a food with no aliases', () => {
    const { food, errors } = rowFrom({ aliases: '' });

    expect(errors).toEqual([]);
    expect(food?.aliases).toEqual([]);
  });
});

describe('unknown columns', () => {
  it('rejects a header the importer does not know', () => {
    // Real case: a seed file used `satFatG`. Unrecognised, it would import as a silent 0 — and
    // saturated fat feeds the docs/05 constraint set.
    expect(unknownColumns(['name', 'kcal', 'satFatG'])).toEqual(['satFatG']);
  });

  it('accepts the documented header', () => {
    expect(unknownColumns([...KNOWN_COLUMNS])).toEqual([]);
  });

  it('ignores a trailing empty column from a spreadsheet export', () => {
    expect(unknownColumns(['name', 'kcal', ''])).toEqual([]);
  });
});
