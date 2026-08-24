"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeBmr = computeBmr;
exports.computeBmi = computeBmi;
exports.computeTdee = computeTdee;
exports.applyGoalAdjustment = applyGoalAdjustment;
function computeBmr(input, pack) {
    const { male, female } = pack.energy.bmr;
    const apply = (c) => c.weight * input.weightKg + c.height * input.heightCm + c.age * input.ageYears + c.constant;
    if (input.sexAtBirth === 'male')
        return { bmr: apply(male), reducedPrecision: false };
    if (input.sexAtBirth === 'female')
        return { bmr: apply(female), reducedPrecision: false };
    return { bmr: (apply(male) + apply(female)) / 2, reducedPrecision: true };
}
function computeBmi(weightKg, heightCm) {
    const heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
}
function computeTdee(bmr, input, pack) {
    const multiplier = pack.energy.activity_multipliers[input.activityLevel];
    if (multiplier === undefined)
        throw new Error(`unknown activity level: ${input.activityLevel}`);
    return bmr * multiplier;
}
function applyGoalAdjustment(tdee, goal, pack, maxDeficitPct) {
    const spec = pack.energy.goal_adjustment[goal];
    if (spec === undefined)
        throw new Error(`unknown goal: ${goal}`);
    if (spec.pct === 0)
        return { target: tdee, appliedPct: 0, warnings: [] };
    const warnings = [];
    if (spec.pct < 0) {
        let pct = Math.abs(spec.pct);
        if (pct > maxDeficitPct) {
            pct = maxDeficitPct;
            warnings.push('deficit_capped_condition');
        }
        let deficit = tdee * pct;
        if (deficit > spec.abs_cap_kcal) {
            deficit = spec.abs_cap_kcal;
            warnings.push('deficit_capped_absolute');
        }
        return { target: tdee - deficit, appliedPct: -(deficit / tdee), warnings };
    }
    let surplus = tdee * spec.pct;
    if (surplus > spec.abs_cap_kcal) {
        surplus = spec.abs_cap_kcal;
        warnings.push('surplus_capped_absolute');
    }
    return { target: tdee + surplus, appliedPct: surplus / tdee, warnings };
}
//# sourceMappingURL=energy.js.map