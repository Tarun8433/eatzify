import type { RulePack } from './pack';
import type { Constraints, EngineInput } from './types';

/**
 * docs/04 §6 — ordered medical overrides. The table lives in the rule pack; this file is only the
 * evaluator. Constraints INTERSECT: each rule may tighten what came before, never loosen it.
 */

export interface OverrideCondition {
  readonly conditions_any?: readonly string[];
  readonly food_preference?: string;
  readonly budget_tier?: string;
  readonly lifestyle?: string;
}

export interface OverrideConstraintSpec {
  readonly max_deficit_pct?: number;
  readonly sodium_max_mg?: number;
  readonly added_sugar_max_g?: number;
  readonly min_low_gi_carb_fraction?: number;
  readonly max_carb_g_per_occasion?: number;
  readonly min_eating_occasions?: number;
  readonly max_carb_pct_energy?: number;
  readonly saturated_max_pct_energy?: number;
  readonly exclude_tags?: readonly string[];
  readonly prefer_tags?: readonly string[];
  readonly cost_low_fraction?: number;
  readonly max_prep_minutes?: number;
  readonly min_portable_meals?: number;
  readonly shift_meal_windows?: boolean;
  readonly separate_from_medication_hours?: number;
  readonly separate_tags?: readonly string[];
}

export interface OverrideRule {
  readonly priority: number;
  readonly when: OverrideCondition;
  readonly constraints: OverrideConstraintSpec;
}

export type PackWithOverrides = RulePack & {
  readonly overrides?: readonly OverrideRule[];
};

function matches(rule: OverrideRule, input: EngineInput): boolean {
  const w = rule.when;
  if (w.conditions_any !== undefined) {
    return input.conditions.some((c) => w.conditions_any!.includes(c));
  }
  if (w.food_preference !== undefined) return input.foodPreference === w.food_preference;
  if (w.budget_tier !== undefined) return input.budgetTier === w.budget_tier;
  if (w.lifestyle !== undefined) return input.lifestyle === w.lifestyle;
  return false;
}

const tighterMin = (current: number | undefined, next: number | undefined): number | undefined =>
  next === undefined ? current : current === undefined ? next : Math.min(current, next);

const tighterMax = (current: number | undefined, next: number | undefined): number | undefined =>
  next === undefined ? current : current === undefined ? next : Math.max(current, next);

/** Allergen tags are hard excludes and are added outside the table (priority 9, docs/04 §6). */
function allergenTags(input: EngineInput): readonly string[] {
  return input.foodAllergies.flatMap((a) => [`allergen:${a}`, `may_contain:${a}`]);
}

/** Diet preference is a hard exclude (priority 10). Jain's root-veg rule comes from the table. */
function preferenceExcludeTags(input: EngineInput): readonly string[] {
  const incompatible: Record<string, readonly string[]> = {
    veg: ['group:meat', 'group:fish', 'group:egg'],
    eggetarian: ['group:meat', 'group:fish'],
    vegan: ['group:meat', 'group:fish', 'group:egg', 'group:dairy'],
    jain: ['group:meat', 'group:fish', 'group:egg'],
    non_veg: [],
  };
  return incompatible[input.foodPreference] ?? [];
}

export interface OverrideResult {
  readonly constraints: Constraints;
  readonly appliedPriorities: readonly number[];
}

export function applyOverrides(
  input: EngineInput,
  targetKcal: number,
  baseMaxDeficitPct: number,
  baseSodiumMaxMg: number,
  baseAddedSugarMaxG: number,
  pack: PackWithOverrides,
): OverrideResult {
  const rules = [...(pack.overrides ?? [])].sort((a, b) => a.priority - b.priority);
  const applied: number[] = [];

  let maxDeficitPct = baseMaxDeficitPct;
  let sodiumMaxMg = baseSodiumMaxMg;
  let addedSugarMaxG = baseAddedSugarMaxG;
  let minLowGiCarbFraction: number | undefined;
  let maxCarbGPerOccasion: number | undefined;
  let minEatingOccasions: number | undefined;
  let maxCarbPctEnergy: number | undefined;
  let costLowFraction: number | undefined;
  let maxPrepMinutes: number | undefined;
  let minPortableMeals: number | undefined;
  let requireEasyDigest = false;
  const excludeTags = new Set<string>([...allergenTags(input), ...preferenceExcludeTags(input)]);
  const preferTags = new Set<string>();

  for (const rule of rules) {
    if (!matches(rule, input)) continue;
    applied.push(rule.priority);
    const c = rule.constraints;

    if (c.max_deficit_pct !== undefined) maxDeficitPct = Math.min(maxDeficitPct, c.max_deficit_pct);
    if (c.sodium_max_mg !== undefined) sodiumMaxMg = Math.min(sodiumMaxMg, c.sodium_max_mg);
    if (c.added_sugar_max_g !== undefined) addedSugarMaxG = Math.min(addedSugarMaxG, c.added_sugar_max_g);

    minLowGiCarbFraction = tighterMax(minLowGiCarbFraction, c.min_low_gi_carb_fraction);
    minEatingOccasions = tighterMax(minEatingOccasions, c.min_eating_occasions);
    minPortableMeals = tighterMax(minPortableMeals, c.min_portable_meals);
    costLowFraction = tighterMax(costLowFraction, c.cost_low_fraction);

    maxCarbGPerOccasion = tighterMin(maxCarbGPerOccasion, c.max_carb_g_per_occasion);
    maxCarbPctEnergy = tighterMin(maxCarbPctEnergy, c.max_carb_pct_energy);
    maxPrepMinutes = tighterMin(maxPrepMinutes, c.max_prep_minutes);

    for (const t of c.exclude_tags ?? []) excludeTags.add(t);
    for (const t of c.prefer_tags ?? []) preferTags.add(t);
  }

  // docs/04 §6 priority 3 — an unlocked post_surgery plan is easy-digest only, with no deficit.
  if (input.conditions.includes('post_surgery') && input.clinicianAttestation === true) {
    requireEasyDigest = true;
    maxDeficitPct = 0;
  }

  const constraints: Constraints = {
    maxDeficitPct,
    sodiumMaxMg,
    addedSugarMaxG,
    excludeTags: [...excludeTags].sort(),
    preferTags: [...preferTags].sort(),
    requireEasyDigest,
    ...(minLowGiCarbFraction !== undefined ? { minLowGiCarbFraction } : {}),
    ...(maxCarbGPerOccasion !== undefined ? { maxCarbGPerOccasion } : {}),
    ...(minEatingOccasions !== undefined ? { minEatingOccasions } : {}),
    ...(maxCarbPctEnergy !== undefined ? { maxCarbPctEnergy } : {}),
    ...(costLowFraction !== undefined ? { costLowFraction } : {}),
    ...(maxPrepMinutes !== undefined ? { maxPrepMinutes } : {}),
    ...(minPortableMeals !== undefined ? { minPortableMeals } : {}),
  };

  return { constraints, appliedPriorities: applied };
}
