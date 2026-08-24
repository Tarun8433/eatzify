"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.hashSeed = exports.createPrng = exports.EngineInputError = exports.EngineAssertionError = void 0;
exports.generatePlan = generatePlan;
const energy_1 = require("./energy");
const macros_1 = require("./macros");
const meals_1 = require("./meals");
const overrides_1 = require("./overrides");
const output_1 = require("./output");
const safety_1 = require("./safety");
const validate_1 = require("./validate");
__exportStar(require("./types"), exports);
var output_2 = require("./output");
Object.defineProperty(exports, "EngineAssertionError", { enumerable: true, get: function () { return output_2.EngineAssertionError; } });
var validate_2 = require("./validate");
Object.defineProperty(exports, "EngineInputError", { enumerable: true, get: function () { return validate_2.EngineInputError; } });
var prng_1 = require("./prng");
Object.defineProperty(exports, "createPrng", { enumerable: true, get: function () { return prng_1.createPrng; } });
Object.defineProperty(exports, "hashSeed", { enumerable: true, get: function () { return prng_1.hashSeed; } });
function generatePlan(input, pack) {
    const trace = [];
    const warnings = [];
    (0, validate_1.validateInput)(input);
    const { bmr, reducedPrecision } = (0, energy_1.computeBmr)(input, pack);
    if (reducedPrecision)
        warnings.push('estimate_precision_reduced');
    const bmi = (0, energy_1.computeBmi)(input.weightKg, input.heightCm);
    trace.push({
        step: 'bmr',
        formula: pack.energy.bmr.formula,
        inputs: { w: input.weightKg, h: input.heightCm, a: input.ageYears, sex: input.sexAtBirth },
        result: Math.round(bmr),
    });
    const tdee = (0, energy_1.computeTdee)(bmr, input, pack);
    trace.push({
        step: 'tdee',
        multiplier: pack.energy.activity_multipliers[input.activityLevel],
        result: Math.round(tdee),
    });
    const deficitCeiling = (0, safety_1.maxDeficitPct)(input, pack);
    const goalResult = (0, safety_1.effectiveGoal)(input, bmi, pack);
    warnings.push(...goalResult.warnings);
    const goal = goalResult.goal;
    const adjusted = (0, energy_1.applyGoalAdjustment)(tdee, goal, pack, deficitCeiling.pct);
    if (goal !== 'maintenance')
        warnings.push(...deficitCeiling.warnings);
    warnings.push(...adjusted.warnings);
    trace.push({
        step: 'goal_adjust',
        goal,
        requested_goal: input.goal,
        pct: Math.round(adjusted.appliedPct * 1000) / 10,
        result: Math.round(adjusted.target),
    });
    const clamped = (0, safety_1.clampTarget)(adjusted.target, bmr, tdee, input, pack);
    warnings.push(...clamped.warnings);
    const floor = input.sexAtBirth === 'female' ? pack.safety.floor_kcal.female : pack.safety.floor_kcal.male;
    trace.push({
        step: 'safety_clamp',
        applied: clamped.applied,
        floor,
        bmr_floor: Math.round(bmr),
        result: Math.round(clamped.target),
    });
    const gateResult = (0, safety_1.evaluateGates)(input, bmi, pack);
    const blocking = gateResult.gates.filter((g) => g.blocking);
    trace.push({ step: 'gates', codes: gateResult.gates.map((g) => g.code), blocking: blocking.length > 0 });
    if (blocking.length > 0) {
        return {
            packVersion: pack.version,
            targets: null,
            derived: null,
            mealTargets: [],
            constraints: null,
            warnings: dedupe(warnings),
            gates: gateResult.gates,
            trace,
        };
    }
    const weights = (0, macros_1.computeBodyWeights)(input, pack);
    const protein = (0, macros_1.computeProtein)(input, clamped.target, weights, goal, pack);
    warnings.push(...protein.warnings);
    trace.push({
        step: 'protein',
        basis: input.weightKg > weights.ibw ? 'abw' : 'actual',
        ibw: (0, output_1.round1)(weights.ibw),
        abw: (0, output_1.round1)(weights.abw),
        rate: protein.rate,
        result: Math.round(protein.grams),
    });
    const fat = (0, macros_1.computeFat)(input.conditions, goal, clamped.target, weights.abw, pack);
    trace.push({ step: 'fat', pct: Math.round(fat.pct * 1000) / 10, result: Math.round(fat.grams) });
    const baseSodium = (0, macros_1.computeSodiumMaxMg)(input.conditions, pack);
    const baseSugar = (0, macros_1.computeAddedSugarMaxG)(clamped.target, input.conditions, pack);
    const carbs = (0, macros_1.computeCarbs)(clamped.target, protein.grams, fat.grams, input, pack);
    warnings.push(...carbs.warnings);
    trace.push({ step: 'carbs', result: Math.round(carbs.carbG), target_kcal: Math.round(carbs.targetKcal) });
    const overrides = (0, overrides_1.applyOverrides)(input, carbs.targetKcal, deficitCeiling.pct, baseSodium, baseSugar, pack);
    trace.push({
        step: 'override',
        rule: overrides.appliedPriorities.length === 0 ? 'none' : overrides.appliedPriorities.join(','),
    });
    const targets = (0, output_1.roundTargets)({
        kcal: carbs.targetKcal,
        proteinG: carbs.proteinG,
        fatG: fat.grams,
        carbG: carbs.carbG,
        fibreG: (0, macros_1.computeFibre)(carbs.targetKcal, pack),
        sodiumMaxMg: overrides.constraints.sodiumMaxMg,
        addedSugarMaxG: overrides.constraints.addedSugarMaxG,
        saturatedFatMaxG: (0, macros_1.computeSaturatedFatMaxG)(carbs.targetKcal, input.conditions, pack),
        waterMl: (0, macros_1.computeWaterMl)(input.weightKg, pack),
    });
    const mealTargets = (0, meals_1.distributeMeals)({
        mealCount: input.mealCount,
        targetKcal: carbs.targetKcal,
        proteinTargetG: carbs.proteinG,
        abw: weights.abw,
        constraints: overrides.constraints,
        pack,
    });
    trace.push({
        step: 'distribute',
        pattern: `${input.mealCount}_meal`,
        split: mealTargets.map((m) => Math.round(m.pct * 100)),
    });
    (0, output_1.assertTargetsCoherent)(targets, pack);
    (0, output_1.assertMealsCoherent)(mealTargets, carbs.targetKcal, pack);
    return {
        packVersion: pack.version,
        targets,
        derived: {
            bmr: Math.round(bmr),
            tdee: Math.round(tdee),
            bmi: (0, output_1.round1)(bmi),
            ibw: (0, output_1.round1)(weights.ibw),
            abw: (0, output_1.round1)(weights.abw),
            proteinBasisKg: (0, output_1.round1)(weights.proteinBasisKg),
            effectiveGoal: goal,
        },
        mealTargets,
        constraints: overrides.constraints,
        warnings: dedupe(warnings),
        gates: gateResult.gates,
        trace,
    };
}
function dedupe(warnings) {
    return [...new Set(warnings)];
}
//# sourceMappingURL=index.js.map