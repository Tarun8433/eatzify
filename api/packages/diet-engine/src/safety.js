"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateGates = evaluateGates;
exports.maxDeficitPct = maxDeficitPct;
exports.effectiveGoal = effectiveGoal;
exports.clampTarget = clampTarget;
function evaluateGates(input, bmi, pack) {
    const gates = [];
    const warnings = [];
    const { blocking_gates: blocking, clinician_gated: clinician } = pack.safety;
    if (input.ageYears < blocking.min_age)
        gates.push({ code: 'age_ineligible', blocking: true });
    if (bmi < blocking.min_bmi)
        gates.push({ code: 'bmi_critical', blocking: true });
    for (const condition of input.conditions) {
        if (!blocking.conditions.includes(condition))
            continue;
        if (condition === 'post_surgery') {
            if (input.clinicianAttestation !== true) {
                gates.push({ code: 'post_surgery_needs_clinician', blocking: true });
            }
            continue;
        }
        gates.push({ code: condition, blocking: true });
    }
    if (bmi >= blocking.min_bmi && bmi < pack.safety.force_maintenance_below_bmi) {
        gates.push({ code: 'underweight_review', blocking: false });
    }
    if (input.ageYears >= clinician.min_age || bmi >= clinician.min_bmi) {
        gates.push({ code: 'clinician_review_required', blocking: false });
    }
    return { gates, warnings };
}
function maxDeficitPct(input, pack) {
    const s = pack.safety;
    const warnings = [];
    let pct = s.max_deficit_pct_default;
    if (input.ageYears >= s.reduced_deficit_age) {
        pct = Math.min(pct, s.max_deficit_pct_reduced);
        warnings.push('deficit_capped_age');
    }
    if (input.conditions.some((c) => s.reduced_deficit_conditions.includes(c))) {
        pct = Math.min(pct, s.max_deficit_pct_reduced);
        warnings.push('deficit_capped_condition');
    }
    return { pct, warnings };
}
function effectiveGoal(input, bmi, pack) {
    const warnings = [];
    if (bmi < pack.safety.force_maintenance_below_bmi) {
        warnings.push('goal_forced_maintenance_low_bmi');
        return { goal: 'maintenance', warnings };
    }
    if (input.goal === 'fat_loss' && bmi < pack.safety.no_deficit_below_bmi) {
        warnings.push('deficit_suppressed_low_bmi');
        return { goal: 'maintenance', warnings };
    }
    return { goal: input.goal, warnings };
}
function clampTarget(rawTarget, bmr, tdee, input, pack) {
    const s = pack.safety;
    const warnings = [];
    let target = rawTarget;
    const deficit = tdee - target;
    if (deficit > 0) {
        const maxDailyDeficit = (s.weekly_loss_pct_max * input.weightKg * s.kcal_per_kg_body_fat) / 7;
        if (deficit > maxDailyDeficit) {
            target = tdee - maxDailyDeficit;
            warnings.push('deficit_capped_weekly_rate');
        }
    }
    const floor = input.sexAtBirth === 'female' ? s.floor_kcal.female : s.floor_kcal.male;
    if (target < floor) {
        target = floor;
        warnings.push('target_raised_to_floor');
    }
    const bmrFloor = bmr * s.never_below_bmr_multiple;
    if (target < bmrFloor) {
        target = bmrFloor;
        warnings.push('target_raised_to_bmr');
    }
    return { target, applied: warnings.length > 0, warnings };
}
//# sourceMappingURL=safety.js.map