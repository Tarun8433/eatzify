import type { RulePack } from './pack';
import type { Constraints, EngineInput } from './types';
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
export interface OverrideResult {
    readonly constraints: Constraints;
    readonly appliedPriorities: readonly number[];
}
export declare function applyOverrides(input: EngineInput, targetKcal: number, baseMaxDeficitPct: number, baseSodiumMaxMg: number, baseAddedSugarMaxG: number, pack: PackWithOverrides): OverrideResult;
