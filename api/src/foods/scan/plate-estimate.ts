import { z } from 'zod';
import type { NutritionView } from '../../logs/nutrition-for';

/// D-240. What a vision model says one photographed plate holds: each item, its weight, and its
/// nutrition for that weight. An ESTIMATE — labelled as one wherever it is shown.

export type EstimatedItem = NutritionView & { name: string };

export type PlateEstimate = {
  isFood: boolean;
  dishName: string;
  /// How sure the model says it is, 0–1. Informational: a high number is not a correct answer.
  confidence: number;
  items: EstimatedItem[];
};

export const NOT_FOOD: PlateEstimate = {
  isFood: false,
  dishName: '',
  confidence: 0,
  items: [],
};

/// A plate rarely holds more; a longer list is a model listing garnishes.
const MAX_ITEMS = 8;

/// Sanity bounds for ONE item. Not nutrition rules — the edges past which a number is a model
/// error, not a meal. An answer outside them is refused whole rather than logged.
const item = z.object({
  name: z.string().trim().min(1).max(60),
  grams: z.number().min(1).max(2000),
  kcal: z.number().min(0).max(3000),
  protein_g: z.number().min(0).max(300),
  carb_g: z.number().min(0).max(500),
  fat_g: z.number().min(0).max(300),
  fibre_g: z.number().min(0).max(100),
  sodium_mg: z.number().min(0).max(10000),
  added_sugar_g: z.number().min(0).max(300),
  saturated_fat_g: z.number().min(0).max(200),
});

const answer = z.object({
  is_food: z.boolean(),
  dish_name: z.string().trim().max(80),
  confidence: z.number().min(0).max(1),
  items: z.array(item).max(MAX_ITEMS),
});

/// For providers that take a schema (Claude's structured output).
export const ANSWER_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['is_food', 'dish_name', 'confidence', 'items'],
  properties: {
    is_food: { type: 'boolean' },
    dish_name: { type: 'string' },
    confidence: { type: 'number' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'name',
          'grams',
          'kcal',
          'protein_g',
          'carb_g',
          'fat_g',
          'fibre_g',
          'sodium_mg',
          'added_sugar_g',
          'saturated_fat_g',
        ],
        properties: {
          name: { type: 'string' },
          grams: { type: 'number' },
          kcal: { type: 'number' },
          protein_g: { type: 'number' },
          carb_g: { type: 'number' },
          fat_g: { type: 'number' },
          fibre_g: { type: 'number' },
          sodium_mg: { type: 'number' },
          added_sugar_g: { type: 'number' },
          saturated_fat_g: { type: 'number' },
        },
      },
    },
  },
} as const;

/// The same instructions for every provider, so switching vendor changes who looks at the photo,
/// never what it is asked to answer.
export const ESTIMATE_PROMPT = `You estimate the nutrition of a meal from a photo, for an Indian nutrition diary.

List each distinct food on the plate (at most ${MAX_ITEMS}). For each, estimate the cooked, edible
weight in grams from the plate, bowl, katori and cutlery in the photo, and its nutrition FOR THAT
WEIGHT, using typical Indian home recipes (IFCT 2017 values where you know them). Name items the way
an Indian user would ("Dal tadka", "Jeera rice", "Aloo gobhi"). dish_name is a short name for the
whole plate ("Rice with dal tadka").

Fields per item: name, grams, kcal, protein_g, carb_g, fat_g, fibre_g, sodium_mg, added_sugar_g,
saturated_fat_g. confidence is 0 to 1 for the whole answer.

If the photo is not food, answer is_food false, dish_name "", confidence 0 and an empty items list.
Give numbers only — no advice, no health claims.`;

/// For providers that need an example of the JSON shape rather than a schema (DeepSeek).
export const ESTIMATE_JSON_EXAMPLE = `

Answer in json only, exactly this shape:
{"is_food": true, "dish_name": "Rice with dal tadka", "confidence": 0.8, "items": [{"name": "Rice (cooked white)", "grams": 200, "kcal": 252, "protein_g": 5.4, "carb_g": 56, "fat_g": 0.6, "fibre_g": 0.8, "sodium_mg": 2, "added_sugar_g": 0, "saturated_fat_g": 0.2}]}`;

const round1 = (n: number): number => Number(n.toFixed(1));

/// A provider's raw text, checked against the schema and bounds. Null when it is not a valid
/// answer — model output is untrusted input like any other.
export function parseEstimate(
  text: string | null | undefined,
): PlateEstimate | null {
  let json: unknown;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
  const parsed = answer.safeParse(json);
  if (!parsed.success) return null;
  const { is_food, dish_name, confidence, items } = parsed.data;
  if (!is_food || items.length === 0) return NOT_FOOD;
  return {
    isFood: true,
    dishName: dish_name || items.map((i) => i.name).join(' + '),
    confidence,
    items: items.map((i) => ({
      name: i.name,
      grams: round1(i.grams),
      kcal: round1(i.kcal),
      protein_g: round1(i.protein_g),
      carb_g: round1(i.carb_g),
      fat_g: round1(i.fat_g),
      fibre_g: round1(i.fibre_g),
      sodium_mg: round1(i.sodium_mg),
      added_sugar_g: round1(i.added_sugar_g),
      saturated_fat_g: round1(i.saturated_fat_g),
    })),
  };
}

/// The plate's totals for the items kept — the ONE sum, used for what the scan shows and for what
/// "yes" logs, so the two cannot disagree.
export function sumItems(items: readonly NutritionView[]): NutritionView {
  const total = (pick: (i: NutritionView) => number) =>
    round1(items.reduce((sum, i) => sum + pick(i), 0));
  return {
    grams: total((i) => i.grams),
    kcal: total((i) => i.kcal),
    protein_g: total((i) => i.protein_g),
    carb_g: total((i) => i.carb_g),
    fat_g: total((i) => i.fat_g),
    fibre_g: total((i) => i.fibre_g),
    sodium_mg: total((i) => i.sodium_mg),
    added_sugar_g: total((i) => i.added_sugar_g),
    saturated_fat_g: total((i) => i.saturated_fat_g),
  };
}
