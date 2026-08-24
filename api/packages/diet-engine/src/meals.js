"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.distributeMeals = distributeMeals;
exports.isWithinTolerance = isWithinTolerance;
function distributeMeals(args) {
    const { mealCount, targetKcal, abw, constraints, pack } = args;
    const pattern = pack.meals.patterns[mealCount];
    if (pattern === undefined)
        throw new Error(`unknown meal pattern: ${mealCount}`);
    const m = pack.meals;
    const perMealFloor = Math.max(m.min_protein_g_per_meal, m.min_protein_g_per_kg_abw_per_meal * abw);
    const slots = pattern.map((spec) => {
        const isSnack = spec.pct < m.snack_pct_threshold;
        return {
            slot: spec.slot,
            pct: spec.pct,
            kcal: spec.pct * targetKcal,
            minProteinG: isSnack ? m.snack_min_protein_g : perMealFloor,
            optional: spec.optional === true,
        };
    });
    const required = constraints.minEatingOccasions;
    if (required !== undefined) {
        const available = slots.filter((s) => !s.optional).length;
        if (available < required) {
            throw new Error(`meal pattern "${mealCount}" gives ${available} eating occasions, condition requires ${required}`);
        }
    }
    return slots;
}
function isWithinTolerance(actualKcal, targetKcal, slotPct, pack) {
    const actualPp = (actualKcal / targetKcal) * 100;
    return Math.abs(actualPp - slotPct * 100) <= pack.meals.tolerance_pp;
}
//# sourceMappingURL=meals.js.map