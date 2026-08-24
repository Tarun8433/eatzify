"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EngineAssertionError = exports.round1 = exports.round0 = void 0;
exports.roundTargets = roundTargets;
exports.assertTargetsCoherent = assertTargetsCoherent;
exports.assertMealsCoherent = assertMealsCoherent;
const macros_1 = require("./macros");
const round0 = (n) => Math.round(n);
exports.round0 = round0;
const round1 = (n) => Math.round(n * 10) / 10;
exports.round1 = round1;
function roundTargets(raw) {
    return {
        kcal: (0, exports.round0)(raw.kcal),
        proteinG: (0, exports.round0)(raw.proteinG),
        fatG: (0, exports.round0)(raw.fatG),
        carbG: (0, exports.round0)(raw.carbG),
        fibreG: (0, exports.round0)(raw.fibreG),
        sodiumMaxMg: (0, exports.round0)(raw.sodiumMaxMg),
        addedSugarMaxG: (0, exports.round0)(raw.addedSugarMaxG),
        saturatedFatMaxG: (0, exports.round0)(raw.saturatedFatMaxG),
        waterMl: (0, exports.round0)(raw.waterMl),
    };
}
class EngineAssertionError extends Error {
    constructor(message) {
        super(message);
        this.name = 'EngineAssertionError';
    }
}
exports.EngineAssertionError = EngineAssertionError;
function assertTargetsCoherent(targets, pack) {
    const fromMacros = targets.proteinG * macros_1.ENERGY_PER_G.protein +
        targets.carbG * macros_1.ENERGY_PER_G.carb +
        targets.fatG * macros_1.ENERGY_PER_G.fat;
    const drift = Math.abs(fromMacros - targets.kcal) / targets.kcal;
    if (drift > pack.validation.kcal_tolerance_pct) {
        throw new EngineAssertionError(`macro energy ${fromMacros.toFixed(0)} drifts ${(drift * 100).toFixed(1)}% from target ${targets.kcal}`);
    }
    if (targets.carbG < pack.macros.carbs.min_g) {
        throw new EngineAssertionError(`carb floor breached: ${targets.carbG} < ${pack.macros.carbs.min_g}`);
    }
}
function assertMealsCoherent(meals, targetKcal, pack) {
    const sum = meals.reduce((acc, m) => acc + m.kcal, 0);
    const drift = Math.abs(sum - targetKcal) / targetKcal;
    if (drift > pack.validation.kcal_tolerance_pct) {
        throw new EngineAssertionError(`meal kcal sum ${sum.toFixed(0)} drifts ${(drift * 100).toFixed(1)}% from target ${targetKcal}`);
    }
}
//# sourceMappingURL=output.js.map