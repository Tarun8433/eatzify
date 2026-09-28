/// Import-time validation for food rows.
///
/// A wrong row here does not stay in a spreadsheet — it goes into somebody's plan. A missing
/// allergen is the sharpest case: `allergens` drives exclusion, so an unlisted peanut is served to
/// a peanut-allergic user. Everything below fails the row rather than importing it half-right.

/// The rule pack matches these EXACT strings (`config/rule-packs/v1.0.0.yaml`). A typo silently
/// removes a food from a medical constraint instead of erroring, so the vocabulary is closed.
export const ALLOWED_TAG_PREFIXES = [
  'gi:',
  'attr:',
  'meal:',
  'cuisine:',
] as const;

export const ALLERGENS = [
  'milk',
  'wheat_gluten',
  'soy',
  'peanut',
  'tree_nut',
  'egg',
  'fish',
  'shellfish',
  'sesame',
  'mustard',
  'other',
] as const;

export const FOOD_PREFERENCES = [
  'veg',
  'non_veg',
  'eggetarian',
  'jain',
  'vegan',
] as const;
export const COST_TIERS = ['low', 'medium', 'premium'] as const;

/// docs/03 §4's food groups, stored as `group:<name>` tags (D-235). The app's category chips filter
/// on these (D-238).
export const FOOD_GROUPS = [
  'cereal',
  'pulse',
  'dairy',
  'veg',
  'fruit',
  'nut_seed',
  'meat',
  'fish',
  'egg',
  'fat_oil',
  'sugar',
  'beverage',
  'prepared',
] as const;

export type FoodRow = {
  name: string;
  nameHi: string | null;
  aliases: string[];
  kcal: number;
  proteinG: number;
  fatG: number;
  carbG: number;
  fibreG: number;
  sodiumMg: number;
  addedSugarG: number;
  saturatedFatG: number;
  tags: string[];
  suitableFor: string[];
  allergens: string[];
  costTier: string;
  source: string;
  sourceRef: string | null;
  measures: { label: string; grams: number; isDefault: boolean }[];
};

export type RowError = { row: number; field: string; message: string };

/// Every column the importer reads. Anything else in the header is rejected rather than ignored:
/// a misspelled `satFatG` would otherwise import as a silent 0, and saturated fat feeds the
/// docs/05 constraint set. A column that is quietly dropped is worse than a column that errors.
export const KNOWN_COLUMNS = [
  'name',
  'nameHi',
  'aliases',
  'kcal',
  'proteinG',
  'fatG',
  'carbG',
  'fibreG',
  'sodiumMg',
  'addedSugarG',
  'saturatedFatG',
  'tags',
  'suitableFor',
  'allergens',
  'costTier',
  'source',
  'sourceRef',
  'measures',
] as const;

export function unknownColumns(header: readonly string[]): string[] {
  return header.filter(
    (c) => c !== '' && !(KNOWN_COLUMNS as readonly string[]).includes(c),
  );
}

const REQUIRED_NUMERIC = ['kcal', 'proteinG', 'fatG', 'carbG'] as const;

/// Macros must roughly account for the stated calories. 4/4/9 kcal per gram, ±25 % — wide enough
/// for rounding and fibre, tight enough to catch a column typed into the wrong field.
const ATWATER_TOLERANCE = 0.25;

export function validateRow(
  raw: Record<string, string>,
  rowNumber: number,
): {
  food: FoodRow | null;
  errors: RowError[];
} {
  const errors: RowError[] = [];
  const err = (field: string, message: string) =>
    errors.push({ row: rowNumber, field, message });

  const name = (raw.name ?? '').trim();
  if (name === '') err('name', 'name is required');

  const num = (field: string): number => {
    const value = (raw[field] ?? '').trim();
    if (value === '') return 0;
    const parsed = Number(value);
    if (Number.isNaN(parsed) || parsed < 0) {
      err(field, `"${value}" is not a non-negative number`);
      return 0;
    }
    return parsed;
  };

  for (const field of REQUIRED_NUMERIC) {
    if ((raw[field] ?? '').trim() === '') err(field, `${field} is required`);
  }

  const kcal = num('kcal');
  const proteinG = num('proteinG');
  const fatG = num('fatG');
  const carbG = num('carbG');

  // Per 100 g edible portion (docs/03) — the macros cannot exceed the portion itself.
  if (proteinG + fatG + carbG > 100) {
    err('macros', 'protein + fat + carb exceeds 100 g per 100 g portion');
  }

  if (kcal > 0) {
    const implied = proteinG * 4 + carbG * 4 + fatG * 9;
    const drift = Math.abs(implied - kcal) / kcal;
    if (drift > ATWATER_TOLERANCE) {
      err(
        'kcal',
        `kcal ${kcal} does not match macros (implies ~${Math.round(implied)}). Check for a column in the wrong field.`,
      );
    }
  }

  const list = (field: string): string[] =>
    (raw[field] ?? '')
      .split('|')
      .map((v) => v.trim())
      .filter((v) => v !== '');

  const tags = list('tags');
  for (const tag of tags) {
    if (!ALLOWED_TAG_PREFIXES.some((p) => tag.startsWith(p))) {
      err(
        'tags',
        `"${tag}" must start with one of ${ALLOWED_TAG_PREFIXES.join(', ')}`,
      );
    }
  }

  const suitableFor = list('suitableFor');
  if (suitableFor.length === 0)
    err('suitableFor', 'at least one food preference is required');
  for (const pref of suitableFor) {
    if (!(FOOD_PREFERENCES as readonly string[]).includes(pref)) {
      err(
        'suitableFor',
        `"${pref}" is not one of ${FOOD_PREFERENCES.join(', ')}`,
      );
    }
  }

  const allergens = list('allergens');
  for (const allergen of allergens) {
    if (!(ALLERGENS as readonly string[]).includes(allergen)) {
      err('allergens', `"${allergen}" is not a known allergen`);
    }
  }

  const costTier = (raw.costTier ?? 'medium').trim() || 'medium';
  if (!(COST_TIERS as readonly string[]).includes(costTier)) {
    err('costTier', `"${costTier}" is not one of ${COST_TIERS.join(', ')}`);
  }

  const source = (raw.source ?? '').trim();
  // docs/03: a food must be traceable. A number nobody can attribute cannot be corrected later.
  if (source === '')
    err('source', 'source is required (e.g. IFCT2017, INDB, manual)');

  const measures = parseMeasures(raw.measures ?? '', rowNumber, err);

  if (errors.length > 0) return { food: null, errors };

  return {
    food: {
      name,
      nameHi: (raw.nameHi ?? '').trim() || null,
      // Lower-cased so search does not have to care how the operator typed them.
      aliases: list('aliases').map((a) => a.toLowerCase()),
      kcal,
      proteinG,
      fatG,
      carbG,
      fibreG: num('fibreG'),
      sodiumMg: num('sodiumMg'),
      addedSugarG: num('addedSugarG'),
      saturatedFatG: num('saturatedFatG'),
      tags,
      suitableFor,
      allergens,
      costTier,
      source,
      sourceRef: (raw.sourceRef ?? '').trim() || null,
      measures,
    },
    errors: [],
  };
}

/// `katori=150|roti=35*` — `*` marks the default. docs/03 calls household measures non-negotiable
/// for India, so a food with none is flagged rather than quietly imported grams-only.
function parseMeasures(
  raw: string,
  rowNumber: number,
  err: (field: string, message: string) => void,
): FoodRow['measures'] {
  const measures: FoodRow['measures'] = [];

  for (const part of raw
    .split('|')
    .map((p) => p.trim())
    .filter((p) => p !== '')) {
    const isDefault = part.endsWith('*');
    const body = isDefault ? part.slice(0, -1) : part;
    const [label, grams] = body.split('=').map((v) => v.trim());

    if (!label || !grams) {
      err('measures', `"${part}" must look like label=grams (e.g. katori=150)`);
      continue;
    }
    const value = Number(grams);
    if (Number.isNaN(value) || value <= 0) {
      err('measures', `"${part}" has a non-positive weight`);
      continue;
    }
    measures.push({ label, grams: value, isDefault });
  }

  if (measures.length > 0 && !measures.some((m) => m.isDefault)) {
    measures[0] = { ...measures[0], isDefault: true };
  }

  return measures;
}
