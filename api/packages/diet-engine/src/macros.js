"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ENERGY_PER_G = void 0;
exports.computeBodyWeights = computeBodyWeights;
exports.computeProtein = computeProtein;
exports.computeFat = computeFat;
exports.computeCarbs = computeCarbs;
exports.computeFibre = computeFibre;
exports.computeSodiumMaxMg = computeSodiumMaxMg;
exports.computeAddedSugarMaxG = computeAddedSugarMaxG;
exports.computeSaturatedFatMaxG = computeSaturatedFatMaxG;
exports.computeWaterMl = computeWaterMl;
const KCAL_PER_G_PROTEIN = 4;
const KCAL_PER_G_CARB = 4;
const KCAL_PER_G_FAT = 9;
function computeBodyWeights(input, pack) {
    const heightM = input.heightCm / 100;
    const ibw = pack.macros.ibw_bmi_reference * heightM * heightM;
    const abw = input.weightKg > ibw
        ? ibw + pack.macros.abw_excess_fraction * (input.weightKg - ibw)
        : input.weightKg;
    return { ibw, abw, proteinBasisKg: input.weightKg > ibw ? abw : input.weightKg };
}
function computeProtein(input, targetKcal, weights, goal, pack) {
    const p = pack.macros.protein;
    const warnings = [];
    const spec = p.rate_g_per_kg_abw[goal];
    if (spec === undefined)
        throw new Error(`no protein rate for goal: ${goal}`);
    let rate = spec.default;
    if (input.coachProteinRate !== undefined) {
        rate = Math.min(Math.max(input.coachProteinRate, spec.min), spec.max);
    }
    const over60WithBoth = input.ageYears > 60 &&
        input.conditions.some((c) => c === 'type2_diabetes' || c === 'prediabetes') &&
        input.conditions.includes('hypertension');
    if (input.conditions.includes('ckd') || over60WithBoth) {
        rate = Math.min(rate, p.renal_caution_rate);
        warnings.push('renal_protein_caution');
    }
    let grams = rate * weights.proteinBasisKg;
    const capByAbw = p.max_g_per_kg_abw * weights.abw;
    const capByEnergy = (p.max_pct_energy * targetKcal) / KCAL_PER_G_PROTEIN;
    grams = Math.min(grams, capByAbw, capByEnergy);
    grams = Math.max(grams, p.min_g_per_kg_actual * input.weightKg);
    return { grams, rate, warnings };
}
function computeFat(conditions, goal, targetKcal, abw, pack) {
    const f = pack.macros.fat;
    const conditionPcts = conditions
        .map((c) => f.pct_by_condition[c])
        .filter((v) => v !== undefined);
    let pct;
    if (conditionPcts.length > 0)
        pct = Math.max(...conditionPcts);
    else
        pct = f.pct_by_goal[goal] ?? f.pct_default;
    pct = Math.max(pct, f.min_pct_energy);
    let grams = (pct * targetKcal) / KCAL_PER_G_FAT;
    grams = Math.max(grams, f.min_g_per_kg_abw * abw);
    return { grams, pct: (grams * KCAL_PER_G_FAT) / targetKcal };
}
function computeCarbs(targetKcal, proteinG, fatG, input, pack) {
    const minCarbG = pack.macros.carbs.min_g;
    const proteinFloorG = pack.macros.protein.min_g_per_kg_actual * input.weightKg;
    const warnings = [];
    const remainderG = (kcal, protein) => (kcal - protein * KCAL_PER_G_PROTEIN - fatG * KCAL_PER_G_FAT) / KCAL_PER_G_CARB;
    let protein = proteinG;
    let carbG = remainderG(targetKcal, protein);
    if (carbG >= minCarbG)
        return { carbG, proteinG: protein, targetKcal, warnings };
    const deficitG = minCarbG - carbG;
    const proteinGiveG = Math.min(protein - proteinFloorG, deficitG);
    if (proteinGiveG > 0) {
        protein -= proteinGiveG;
        carbG = remainderG(targetKcal, protein);
        warnings.push('protein_reduced_for_carb_floor');
    }
    if (carbG >= minCarbG)
        return { carbG, proteinG: protein, targetKcal, warnings };
    const raisedKcal = targetKcal + (minCarbG - carbG) * KCAL_PER_G_CARB;
    return { carbG: minCarbG, proteinG: protein, targetKcal: raisedKcal, warnings };
}
function computeFibre(targetKcal, pack) {
    const f = pack.macros.fibre;
    const raw = (targetKcal / 1000) * f.g_per_1000_kcal;
    return Math.min(Math.max(raw, f.min_g), f.max_g);
}
function computeSodiumMaxMg(conditions, pack) {
    const s = pack.macros.sodium;
    return conditions.includes('hypertension') ? s.max_mg_hypertension : s.max_mg_default;
}
const SUGAR_ABSOLUTE_CONDITIONS = ['type2_diabetes', 'prediabetes', 'pcos'];
function computeAddedSugarMaxG(targetKcal, conditions, pack) {
    const s = pack.macros.added_sugar;
    const byEnergy = (s.max_pct_energy * targetKcal) / KCAL_PER_G_CARB;
    const needsAbsolute = conditions.some((c) => SUGAR_ABSOLUTE_CONDITIONS.includes(c));
    return needsAbsolute ? Math.min(byEnergy, s.max_g_absolute) : byEnergy;
}
function computeSaturatedFatMaxG(targetKcal, conditions, pack) {
    const f = pack.macros.fat;
    const tighten = conditions.includes('hypertension');
    const pct = tighten ? f.saturated_max_pct_tightened : f.saturated_max_pct_default;
    return (pct * targetKcal) / KCAL_PER_G_FAT;
}
function computeWaterMl(weightKg, pack) {
    const w = pack.macros.water;
    return Math.min(Math.max(weightKg * w.ml_per_kg, w.min_ml), w.max_ml);
}
exports.ENERGY_PER_G = {
    protein: KCAL_PER_G_PROTEIN,
    carb: KCAL_PER_G_CARB,
    fat: KCAL_PER_G_FAT,
};
//# sourceMappingURL=macros.js.map