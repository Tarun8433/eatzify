import { z } from 'zod';

/**
 * Boot-time validation for config/rule-packs/*.yaml.
 *
 * The engine package is pure and takes a pack object as an argument — it never reads a file and never
 * validates one. That job lives here, at the I/O boundary, and it runs once at startup: a malformed
 * pack must stop the process, not surface as a wrong calorie target three weeks later.
 */

const positive = z.number().positive();
const fraction = z.number().min(0).max(1);

const bmrCoefficients = z.object({
  weight: z.number(),
  height: z.number(),
  age: z.number(),
  constant: z.number(),
});

const goalAdjustment = z.object({
  pct: z.number().min(-1).max(1),
  abs_cap_kcal: z.number().min(0),
});

const proteinRate = z
  .object({ default: positive, min: positive, max: positive })
  .refine((r) => r.min <= r.default && r.default <= r.max, {
    message: 'protein rate must satisfy min <= default <= max',
  });

const mealSlot = z.object({
  slot: z.string().min(1),
  pct: fraction,
  optional: z.boolean().optional(),
});

export const rulePackSchema = z
  .object({
    version: z.string().regex(/^\d+\.\d+\.\d+$/, 'version must be semver'),
    energy: z.object({
      bmr: z.object({
        formula: z.literal('mifflin_st_jeor'),
        male: bmrCoefficients,
        female: bmrCoefficients,
      }),
      activity_multipliers: z.record(z.string(), positive),
      goal_adjustment: z.record(z.string(), goalAdjustment),
    }),
    safety: z.object({
      floor_kcal: z.object({ male: positive, female: positive }),
      never_below_bmr_multiple: positive,
      max_deficit_pct_default: fraction,
      max_deficit_pct_reduced: fraction,
      reduced_deficit_age: positive,
      reduced_deficit_conditions: z.array(z.string()),
      no_deficit_below_bmi: positive,
      force_maintenance_below_bmi: positive,
      weekly_loss_pct_min: fraction,
      weekly_loss_pct_max: fraction,
      kcal_per_kg_body_fat: positive,
      blocking_gates: z.object({
        conditions: z.array(z.string()),
        min_age: positive,
        min_bmi: positive,
      }),
      clinician_gated: z.object({
        conditions: z.array(z.string()),
        min_age: positive,
        min_bmi: positive,
      }),
    }),
    macros: z.object({
      ibw_bmi_reference: positive,
      abw_excess_fraction: fraction,
      protein: z.object({
        rate_g_per_kg_abw: z.record(z.string(), proteinRate),
        max_g_per_kg_abw: positive,
        max_pct_energy: fraction,
        min_g_per_kg_actual: positive,
        renal_caution_rate: positive,
      }),
      fat: z.object({
        pct_default: fraction,
        pct_by_condition: z.record(z.string(), fraction),
        pct_by_goal: z.record(z.string(), fraction),
        min_pct_energy: fraction,
        min_g_per_kg_abw: positive,
        saturated_max_pct_default: fraction,
        saturated_max_pct_tightened: fraction,
      }),
      carbs: z.object({ min_g: positive }),
      fibre: z.object({
        g_per_1000_kcal: positive,
        min_g: positive,
        max_g: positive,
      }),
      sodium: z.object({
        max_mg_default: positive,
        max_mg_hypertension: positive,
      }),
      added_sugar: z.object({
        max_pct_energy: fraction,
        max_g_absolute: positive,
      }),
      water: z.object({
        ml_per_kg: positive,
        min_ml: positive,
        max_ml: positive,
      }),
    }),
    meals: z.object({
      patterns: z.record(z.string(), z.array(mealSlot).min(1)),
      tolerance_pp: positive,
      min_protein_g_per_meal: positive,
      min_protein_g_per_kg_abw_per_meal: positive,
      snack_pct_threshold: fraction,
      snack_min_protein_g: positive,
      max_pct_daily_protein_per_meal_gain: fraction,
      max_carb_g_per_occasion_diabetes: positive,
      min_eating_occasions_diabetes: positive,
      fill_max_iterations: positive.int(),
    }),
    rounding: z.object({
      kcal: z.string(),
      macros_g: z.string(),
      household_increments: z.array(positive),
      quantity_ml_increment: positive,
    }),
    validation: z.object({
      kcal_tolerance_pct: fraction,
      protein_tolerance_g: positive,
    }),
    /// docs/04 §2 step 14. Optional so a pack written before alternates existed still boots —
    /// the engine treats an absent block as "offer no swaps" rather than inventing a window.
    alternates: z
      .object({
        kcal_tolerance_pct: fraction,
        protein_tolerance_g: positive,
        max_per_item: z.number().int().positive(),
      })
      .optional(),
    /// D-235. Optional like `alternates`: the block is machinery the engine can consume, and the
    /// VALUES are a dietitian's to supply via a reviewed pack diff.
    composition: z
      .object({
        rules: z.array(
          z.object({
            slots: z.array(z.string()).min(1),
            require_one_of: z.array(z.array(z.string()).min(1)).min(1),
          }),
        ),
      })
      .optional(),
    overrides: z
      .array(
        z.object({
          priority: z.number().int().positive(),
          when: z.record(z.string(), z.unknown()),
          constraints: z.record(z.string(), z.unknown()),
        }),
      )
      .optional(),
    relaxation_order: z.array(z.string()).optional(),
  })
  // Cross-field invariants. These are the ones a typo would otherwise sail straight past.
  .superRefine((pack, ctx) => {
    const fail = (message: string): void =>
      ctx.addIssue({ code: 'custom', message });

    if (
      pack.safety.max_deficit_pct_reduced > pack.safety.max_deficit_pct_default
    ) {
      fail('max_deficit_pct_reduced must not exceed max_deficit_pct_default');
    }
    if (
      pack.safety.force_maintenance_below_bmi > pack.safety.no_deficit_below_bmi
    ) {
      fail('force_maintenance_below_bmi must not exceed no_deficit_below_bmi');
    }
    if (pack.safety.weekly_loss_pct_min > pack.safety.weekly_loss_pct_max) {
      fail('weekly_loss_pct_min must not exceed weekly_loss_pct_max');
    }
    if (pack.macros.fibre.min_g > pack.macros.fibre.max_g) {
      fail('fibre min_g must not exceed max_g');
    }
    if (pack.macros.water.min_ml > pack.macros.water.max_ml) {
      fail('water min_ml must not exceed max_ml');
    }
    if (
      pack.macros.sodium.max_mg_hypertension > pack.macros.sodium.max_mg_default
    ) {
      fail('sodium max_mg_hypertension must not exceed max_mg_default');
    }
    if (
      pack.macros.fat.saturated_max_pct_tightened >
      pack.macros.fat.saturated_max_pct_default
    ) {
      fail(
        'saturated_max_pct_tightened must not exceed saturated_max_pct_default',
      );
    }

    // Every meal pattern must sum to 1.0 once optional slots are included, or the plan silently
    // under- or over-shoots the target and the §8 assertion fires at runtime instead of at boot.
    for (const [name, slots] of Object.entries(pack.meals.patterns)) {
      const total = slots.reduce((acc, s) => acc + s.pct, 0);
      if (Math.abs(total - 1) > 1e-9) {
        fail(
          `meal pattern "${name}" sums to ${total.toFixed(3)}, expected 1.000`,
        );
      }
    }
  });

export type ValidatedRulePack = z.infer<typeof rulePackSchema>;
