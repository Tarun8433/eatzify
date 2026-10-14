/// The "Add food" form's two pieces of logic, kept out of the component so they are tested.
/// The API (`validateRow` in api/src/foods/food-validation.ts) is the judge of a valid food; this
/// file only turns the form into the importer's column set and the refusal into readable lines.

/// Mirrors the API's lists. The API re-checks every value, so a stale copy here fails loudly there.
export const FOOD_PREFERENCES = ['veg', 'non_veg', 'eggetarian', 'jain', 'vegan'] as const;
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
export const COST_TIERS = ['low', 'medium', 'premium'] as const;

export interface FoodForm {
  name: string;
  nameHi: string;
  aliases: string;
  kcal: string;
  proteinG: string;
  fatG: string;
  carbG: string;
  fibreG: string;
  suitableFor: string[];
  allergens: string[];
  measures: string;
  costTier: (typeof COST_TIERS)[number];
  source: string;
}

export const EMPTY_FOOD: FoodForm = {
  name: '',
  nameHi: '',
  aliases: '',
  kcal: '',
  proteinG: '',
  fatG: '',
  carbG: '',
  fibreG: '',
  suitableFor: [],
  allergens: [],
  measures: '',
  costTier: 'medium',
  source: 'manual',
};

/// The CSV importer's row: every value a string, lists joined with `|`. Aliases are typed with
/// commas, the natural way in a form field.
export function toFoodRow(form: FoodForm): Record<string, string> {
  const aliases = form.aliases
    .split(',')
    .map((a) => a.trim())
    .filter((a) => a !== '');
  return {
    name: form.name.trim(),
    nameHi: form.nameHi.trim(),
    aliases: aliases.join('|'),
    kcal: form.kcal.trim(),
    proteinG: form.proteinG.trim(),
    fatG: form.fatG.trim(),
    carbG: form.carbG.trim(),
    fibreG: form.fibreG.trim(),
    suitableFor: form.suitableFor.join('|'),
    allergens: form.allergens.join('|'),
    measures: form.measures.trim(),
    costTier: form.costTier,
    source: form.source.trim(),
  };
}

/// What the API said, as lines to show. A `FOOD_INVALID` refusal carries one line per problem;
/// anything else falls back to its `user_message`, then to a plain sentence.
export function foodErrorLines(body: unknown): string[] {
  const error = (body as { error?: unknown } | null)?.error;
  if (typeof error === 'string') return [error];
  const e = error as
    | { user_message?: string; details?: { errors?: { field: string; message: string }[] } }
    | undefined;
  const problems = e?.details?.errors ?? [];
  if (problems.length > 0) return problems.map((p) => `${p.field}: ${p.message}`);
  return [e?.user_message ?? 'The food could not be saved.'];
}
