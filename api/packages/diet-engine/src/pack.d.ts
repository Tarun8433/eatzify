export interface BmrCoefficients {
    readonly weight: number;
    readonly height: number;
    readonly age: number;
    readonly constant: number;
}
export interface GoalAdjustment {
    readonly pct: number;
    readonly abs_cap_kcal: number;
}
export interface ProteinRate {
    readonly default: number;
    readonly min: number;
    readonly max: number;
}
export interface MealSlotSpec {
    readonly slot: string;
    readonly pct: number;
    readonly optional?: boolean;
}
export interface RulePack {
    readonly version: string;
    readonly energy: {
        readonly bmr: {
            readonly formula: string;
            readonly male: BmrCoefficients;
            readonly female: BmrCoefficients;
        };
        readonly activity_multipliers: Readonly<Record<string, number>>;
        readonly goal_adjustment: Readonly<Record<string, GoalAdjustment>>;
    };
    readonly safety: {
        readonly floor_kcal: {
            readonly male: number;
            readonly female: number;
        };
        readonly never_below_bmr_multiple: number;
        readonly max_deficit_pct_default: number;
        readonly max_deficit_pct_reduced: number;
        readonly reduced_deficit_age: number;
        readonly reduced_deficit_conditions: readonly string[];
        readonly no_deficit_below_bmi: number;
        readonly force_maintenance_below_bmi: number;
        readonly weekly_loss_pct_min: number;
        readonly weekly_loss_pct_max: number;
        readonly kcal_per_kg_body_fat: number;
        readonly blocking_gates: {
            readonly conditions: readonly string[];
            readonly min_age: number;
            readonly min_bmi: number;
        };
        readonly clinician_gated: {
            readonly conditions: readonly string[];
            readonly min_age: number;
            readonly min_bmi: number;
        };
    };
    readonly macros: {
        readonly ibw_bmi_reference: number;
        readonly abw_excess_fraction: number;
        readonly protein: {
            readonly rate_g_per_kg_abw: Readonly<Record<string, ProteinRate>>;
            readonly max_g_per_kg_abw: number;
            readonly max_pct_energy: number;
            readonly min_g_per_kg_actual: number;
            readonly renal_caution_rate: number;
        };
        readonly fat: {
            readonly pct_default: number;
            readonly pct_by_condition: Readonly<Record<string, number>>;
            readonly pct_by_goal: Readonly<Record<string, number>>;
            readonly min_pct_energy: number;
            readonly min_g_per_kg_abw: number;
            readonly saturated_max_pct_default: number;
            readonly saturated_max_pct_tightened: number;
        };
        readonly carbs: {
            readonly min_g: number;
        };
        readonly fibre: {
            readonly g_per_1000_kcal: number;
            readonly min_g: number;
            readonly max_g: number;
        };
        readonly sodium: {
            readonly max_mg_default: number;
            readonly max_mg_hypertension: number;
        };
        readonly added_sugar: {
            readonly max_pct_energy: number;
            readonly max_g_absolute: number;
        };
        readonly water: {
            readonly ml_per_kg: number;
            readonly min_ml: number;
            readonly max_ml: number;
        };
    };
    readonly meals: {
        readonly patterns: Readonly<Record<string, readonly MealSlotSpec[]>>;
        readonly tolerance_pp: number;
        readonly min_protein_g_per_meal: number;
        readonly min_protein_g_per_kg_abw_per_meal: number;
        readonly snack_pct_threshold: number;
        readonly snack_min_protein_g: number;
        readonly max_pct_daily_protein_per_meal_gain: number;
        readonly max_carb_g_per_occasion_diabetes: number;
        readonly min_eating_occasions_diabetes: number;
        readonly fill_max_iterations: number;
    };
    readonly validation: {
        readonly kcal_tolerance_pct: number;
        readonly protein_tolerance_g: number;
    };
}
