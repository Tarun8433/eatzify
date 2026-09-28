import type { FoodEntity } from '../foods/entities/food.entity';

/// What a portion of a food carries, per the WHOLE portion (not per 100 g).
export type NutritionView = {
  grams: number;
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  fibre_g: number;
  sodium_mg: number;
  added_sugar_g: number;
  saturated_fat_g: number;
};

type Per100g = Pick<
  FoodEntity,
  | 'kcal'
  | 'proteinG'
  | 'carbG'
  | 'fatG'
  | 'fibreG'
  | 'sodiumMg'
  | 'addedSugarG'
  | 'saturatedFatG'
>;

/// One decimal, rounded once — the precision a diary row stores (D-42).
const round1 = (n: number): number => Number(n.toFixed(1));

/// Food rows are per 100 g edible portion (docs/03). The ONE place a portion is scaled, so the add
/// sheet's preview and the diary row it becomes can never disagree (D-238, CLAUDE.md rule 2).
export function nutritionFor(food: Per100g, grams: number): NutritionView {
  const scale = (per100g: string | number) =>
    round1((Number(per100g) * grams) / 100);

  return {
    grams: round1(grams),
    kcal: scale(food.kcal),
    protein_g: scale(food.proteinG),
    carb_g: scale(food.carbG),
    fat_g: scale(food.fatG),
    fibre_g: scale(food.fibreG),
    sodium_mg: scale(food.sodiumMg),
    added_sugar_g: scale(food.addedSugarG),
    saturated_fat_g: scale(food.saturatedFatG),
  };
}
