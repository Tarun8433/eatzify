"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyOverrides = applyOverrides;
function matches(rule, input) {
    const w = rule.when;
    if (w.conditions_any !== undefined) {
        return input.conditions.some((c) => w.conditions_any.includes(c));
    }
    if (w.food_preference !== undefined)
        return input.foodPreference === w.food_preference;
    if (w.budget_tier !== undefined)
        return input.budgetTier === w.budget_tier;
    if (w.lifestyle !== undefined)
        return input.lifestyle === w.lifestyle;
    return false;
}
const tighterMin = (current, next) => next === undefined ? current : current === undefined ? next : Math.min(current, next);
const tighterMax = (current, next) => next === undefined ? current : current === undefined ? next : Math.max(current, next);
function allergenTags(input) {
    return input.foodAllergies.flatMap((a) => [`allergen:${a}`, `may_contain:${a}`]);
}
function preferenceExcludeTags(input) {
    const incompatible = {
        veg: ['group:meat', 'group:fish', 'group:egg'],
        eggetarian: ['group:meat', 'group:fish'],
        vegan: ['group:meat', 'group:fish', 'group:egg', 'group:dairy'],
        jain: ['group:meat', 'group:fish', 'group:egg'],
        non_veg: [],
    };
    return incompatible[input.foodPreference] ?? [];
}
function applyOverrides(input, targetKcal, baseMaxDeficitPct, baseSodiumMaxMg, baseAddedSugarMaxG, pack) {
    const rules = [...(pack.overrides ?? [])].sort((a, b) => a.priority - b.priority);
    const applied = [];
    let maxDeficitPct = baseMaxDeficitPct;
    let sodiumMaxMg = baseSodiumMaxMg;
    let addedSugarMaxG = baseAddedSugarMaxG;
    let minLowGiCarbFraction;
    let maxCarbGPerOccasion;
    let minEatingOccasions;
    let maxCarbPctEnergy;
    let costLowFraction;
    let maxPrepMinutes;
    let minPortableMeals;
    let requireEasyDigest = false;
    const excludeTags = new Set([...allergenTags(input), ...preferenceExcludeTags(input)]);
    const preferTags = new Set();
    for (const rule of rules) {
        if (!matches(rule, input))
            continue;
        applied.push(rule.priority);
        const c = rule.constraints;
        if (c.max_deficit_pct !== undefined)
            maxDeficitPct = Math.min(maxDeficitPct, c.max_deficit_pct);
        if (c.sodium_max_mg !== undefined)
            sodiumMaxMg = Math.min(sodiumMaxMg, c.sodium_max_mg);
        if (c.added_sugar_max_g !== undefined)
            addedSugarMaxG = Math.min(addedSugarMaxG, c.added_sugar_max_g);
        minLowGiCarbFraction = tighterMax(minLowGiCarbFraction, c.min_low_gi_carb_fraction);
        minEatingOccasions = tighterMax(minEatingOccasions, c.min_eating_occasions);
        minPortableMeals = tighterMax(minPortableMeals, c.min_portable_meals);
        costLowFraction = tighterMax(costLowFraction, c.cost_low_fraction);
        maxCarbGPerOccasion = tighterMin(maxCarbGPerOccasion, c.max_carb_g_per_occasion);
        maxCarbPctEnergy = tighterMin(maxCarbPctEnergy, c.max_carb_pct_energy);
        maxPrepMinutes = tighterMin(maxPrepMinutes, c.max_prep_minutes);
        for (const t of c.exclude_tags ?? [])
            excludeTags.add(t);
        for (const t of c.prefer_tags ?? [])
            preferTags.add(t);
    }
    if (input.conditions.includes('post_surgery') && input.clinicianAttestation === true) {
        requireEasyDigest = true;
        maxDeficitPct = 0;
    }
    const constraints = {
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
//# sourceMappingURL=overrides.js.map