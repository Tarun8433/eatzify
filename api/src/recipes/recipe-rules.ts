import { MEAL_SLOTS } from '../logs/dto/log-food.dto';
import { nutritionFor, type NutritionView } from '../logs/nutrition-for';

/// What a recipe's numbers are made of: one food row (per 100 g, as stored) and how many grams of
/// it go into the WHOLE recipe.
export type IngredientFood = {
  kcal: string;
  proteinG: string;
  carbG: string;
  fatG: string;
  fibreG: string;
  sodiumMg: string;
  addedSugarG: string;
  saturatedFatG: string;
  suitableFor: string[];
  allergens: string[];
};

export type Ingredient = { food: IngredientFood; grams: number };

/// One serving's nutrition: the sum of every ingredient's own `nutritionFor`, divided by servings.
/// The same scaling code a diary entry uses, so a logged recipe adds up to what this card showed.
export function perServing(
  ingredients: Ingredient[],
  servings: number,
): NutritionView {
  const total = ingredients
    .map((i) => nutritionFor(i.food, i.grams))
    .reduce(
      (sum, n) => ({
        grams: sum.grams + n.grams,
        kcal: sum.kcal + n.kcal,
        protein_g: sum.protein_g + n.protein_g,
        carb_g: sum.carb_g + n.carb_g,
        fat_g: sum.fat_g + n.fat_g,
        fibre_g: sum.fibre_g + n.fibre_g,
        sodium_mg: sum.sodium_mg + n.sodium_mg,
        added_sugar_g: sum.added_sugar_g + n.added_sugar_g,
        saturated_fat_g: sum.saturated_fat_g + n.saturated_fat_g,
      }),
      ZERO,
    );
  const each = (v: number) => Math.round((v / servings) * 10) / 10;
  return {
    grams: each(total.grams),
    kcal: each(total.kcal),
    protein_g: each(total.protein_g),
    carb_g: each(total.carb_g),
    fat_g: each(total.fat_g),
    fibre_g: each(total.fibre_g),
    sodium_mg: each(total.sodium_mg),
    added_sugar_g: each(total.added_sugar_g),
    saturated_fat_g: each(total.saturated_fat_g),
  };
}

const ZERO: NutritionView = {
  grams: 0,
  kcal: 0,
  protein_g: 0,
  carb_g: 0,
  fat_g: 0,
  fibre_g: 0,
  sodium_mg: 0,
  added_sugar_g: 0,
  saturated_fat_g: 0,
};

/// Which food preferences a recipe suits: only those EVERY ingredient suits. Derived, never typed:
/// a hand-set "veg" on a dish with egg in it is exactly the mistake this cannot make.
export function suitableFor(ingredients: Ingredient[]): string[] {
  if (ingredients.length === 0) return [];
  return ingredients
    .map((i) => i.food.suitableFor)
    .reduce((acc, prefs) => acc.filter((p) => prefs.includes(p)));
}

/// Every allergen any ingredient carries.
export function allergens(ingredients: Ingredient[]): string[] {
  return [...new Set(ingredients.flatMap((i) => i.food.allergens))].sort();
}

/// The limits a recipe draft is held to. Not nutrition constants (api rule 1) — form bounds.
export const RECIPE_LIMITS = {
  maxServings: 20,
  maxIngredients: 30,
  maxIngredientGrams: 5000,
  maxSteps: 30,
} as const;

export type RecipeDraftInput = {
  name: string;
  servings: number;
  slots: string[];
  steps: string[];
  ingredients: { foodId: string; grams: number }[];
};

/// Problems with a draft, as `field: message` lines — empty means it may be saved.
export function recipeProblems(input: RecipeDraftInput): string[] {
  const problems: string[] = [];
  if (input.name.trim() === '') problems.push('name: a name is required');
  if (
    !Number.isInteger(input.servings) ||
    input.servings < 1 ||
    input.servings > RECIPE_LIMITS.maxServings
  ) {
    problems.push(
      `servings: must be a whole number from 1 to ${RECIPE_LIMITS.maxServings}`,
    );
  }
  if (input.slots.length === 0)
    problems.push('slots: choose at least one meal');
  for (const slot of input.slots) {
    if (!(MEAL_SLOTS as readonly string[]).includes(slot)) {
      problems.push(`slots: "${slot}" is not a meal`);
    }
  }
  if (input.ingredients.length === 0) {
    problems.push('ingredients: add at least one food');
  }
  if (input.ingredients.length > RECIPE_LIMITS.maxIngredients) {
    problems.push(`ingredients: at most ${RECIPE_LIMITS.maxIngredients} foods`);
  }
  const seen = new Set<string>();
  for (const { foodId, grams } of input.ingredients) {
    if (seen.has(foodId)) problems.push('ingredients: a food is listed twice');
    seen.add(foodId);
    if (!(grams > 0) || grams > RECIPE_LIMITS.maxIngredientGrams) {
      problems.push(
        `ingredients: grams must be above 0 and at most ${RECIPE_LIMITS.maxIngredientGrams}`,
      );
    }
  }
  if (input.steps.length > RECIPE_LIMITS.maxSteps) {
    problems.push(`steps: at most ${RECIPE_LIMITS.maxSteps} steps`);
  }
  return problems;
}
