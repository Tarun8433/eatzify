/// The "Add recipe" form's logic, out of the component so it is tested. The API
/// (`recipeProblems` in api/src/recipes/recipe-rules.ts) judges a complete recipe; this only builds
/// its body. Refusals share the food importer's shape, so `foodErrorLines` reads them too.

/// Mirrors the API's `MEAL_SLOTS`; the API re-checks every value.
export const MEAL_SLOTS = [
  'breakfast',
  'mid_morning',
  'lunch',
  'snack',
  'evening',
  'dinner',
  'bedtime',
] as const;

export interface IngredientLine {
  foodId: string;
  name: string;
  grams: string;
}

export interface RecipeForm {
  name: string;
  nameHi: string;
  description: string;
  servings: string;
  slots: string[];
  /// One step per line, the way people write a method.
  steps: string;
  ingredients: IngredientLine[];
}

export const EMPTY_RECIPE: RecipeForm = {
  name: '',
  nameHi: '',
  description: '',
  servings: '1',
  slots: [],
  steps: '',
  ingredients: [],
};

/// `POST /admin/recipes`'s body. Numbers that do not parse go as NaN-free zeros, so the API's
/// "grams must be above 0" names them rather than the request failing as malformed JSON.
export function toRecipeBody(form: RecipeForm) {
  const num = (v: string) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  };
  return {
    name: form.name.trim(),
    name_hi: form.nameHi.trim(),
    description: form.description.trim(),
    servings: Math.trunc(num(form.servings)),
    slots: form.slots,
    steps: form.steps
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s !== ''),
    ingredients: form.ingredients.map((i) => ({ food_id: i.foodId, grams: num(i.grams) })),
  };
}

/// Published foods whose name or Hindi name contains [query], minus those already in the recipe.
export function matchFoods<T extends { id: string; name: string; nameHi: string | null }>(
  foods: T[],
  query: string,
  taken: string[],
  limit = 8,
): T[] {
  const q = query.trim().toLowerCase();
  if (q === '') return [];
  return foods
    .filter((f) => !taken.includes(f.id))
    .filter((f) => f.name.toLowerCase().includes(q) || (f.nameHi ?? '').includes(q))
    .slice(0, limit);
}
