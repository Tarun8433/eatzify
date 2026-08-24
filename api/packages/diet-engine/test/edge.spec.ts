/**
 * Edge and failure paths the golden vectors do not reach. docs/16 §1 puts the engine floor at 95 %,
 * and every branch here is a safety rule — an untested floor is an unenforced floor.
 */
import { applyGoalAdjustment, computeBmr, computeTdee } from '../src/energy';
import {
  computeAddedSugarMaxG,
  computeBodyWeights,
  computeCarbs,
  computeFat,
  computeFibre,
  computeProtein,
  computeSaturatedFatMaxG,
  computeSodiumMaxMg,
  computeWaterMl,
} from '../src/macros';
import { distributeMeals, isWithinTolerance } from '../src/meals';
import { applyOverrides } from '../src/overrides';
import {
  EngineAssertionError,
  assertMealsCoherent,
  assertTargetsCoherent,
  roundTargets,
} from '../src/output';
import { clampTarget } from '../src/safety';
import { EngineInputError, validateInput } from '../src/validate';
import { generatePlan } from '../src';
import { input, loadPack } from './helpers';

const pack = loadPack();

describe('input validation (pipeline step 1)', () => {
  it('rejects an out-of-range height and weight', () => {
    expect(() => validateInput(input({ heightCm: 119 }))).toThrow(EngineInputError);
    expect(() => validateInput(input({ weightKg: 251 }))).toThrow(/weightKg out of range/);
  });

  it('rejects an empty condition set — "none" must be explicit', () => {
    expect(() => validateInput(input({ conditions: [] }))).toThrow(/at least "none"/);
  });

  it('rejects "none" combined with a real condition (docs/03 §2: none is exclusive)', () => {
    expect(() => validateInput(input({ conditions: ['none', 'pcos'] }))).toThrow(/exclusive/);
  });

  it('rejects a plan date that is not YYYY-MM-DD — the engine never parses a clock', () => {
    expect(() => validateInput(input({ planDate: '24-08-2026' }))).toThrow(/YYYY-MM-DD/);
  });
});

describe('BMR for intersex_prefer_not_say', () => {
  it('averages both coefficient sets and flags reduced precision', () => {
    const subject = input({ sexAtBirth: 'intersex_prefer_not_say', weightKg: 80, heightCm: 175, ageYears: 30 });
    const { bmr, reducedPrecision } = computeBmr(subject, pack);
    const male = computeBmr({ ...subject, sexAtBirth: 'male' }, pack).bmr;
    const female = computeBmr({ ...subject, sexAtBirth: 'female' }, pack).bmr;

    expect(reducedPrecision).toBe(true);
    expect(bmr).toBeCloseTo((male + female) / 2, 6);
    expect(generatePlan(subject, pack).warnings).toContain('estimate_precision_reduced');
  });
});

describe('unknown enum values fail loudly rather than defaulting', () => {
  it('throws on an activity level absent from the pack', () => {
    expect(() => computeTdee(1500, input({ activityLevel: 'athlete' as never }), pack)).toThrow(
      /unknown activity level/,
    );
  });

  it('throws on a goal absent from the pack', () => {
    expect(() => applyGoalAdjustment(2000, 'recomp' as never, pack, 0.2)).toThrow(/unknown goal/);
  });

  it('throws on a meal pattern absent from the pack', () => {
    expect(() =>
      distributeMeals({
        mealCount: '7' as never,
        targetKcal: 2000,
        proteinTargetG: 120,
        abw: 70,
        constraints: applyOverrides(input({}), 2000, 0.2, 2000, 25, pack).constraints,
        pack,
      }),
    ).toThrow(/unknown meal pattern/);
  });
});

describe('deficit ceilings (docs/05 §2)', () => {
  it('caps an absolute deficit at 750 kcal', () => {
    const out = generatePlan(
      input({
        sexAtBirth: 'male', ageYears: 25, heightCm: 185, weightKg: 120,
        activityLevel: 'heavy', goal: 'fat_loss',
      }),
      pack,
    );
    expect(out.warnings).toContain('deficit_capped_absolute');
    expect((out.derived?.tdee ?? 0) - (out.targets?.kcal ?? 0)).toBeLessThanOrEqual(751);
  });

  it('caps a muscle-gain surplus at 400 kcal', () => {
    const out = generatePlan(
      input({
        sexAtBirth: 'male', ageYears: 25, heightCm: 185, weightKg: 100,
        activityLevel: 'heavy', goal: 'muscle_gain',
      }),
      pack,
    );
    expect(out.warnings).toContain('surplus_capped_absolute');
    expect((out.targets?.kcal ?? 0) - (out.derived?.tdee ?? 0)).toBeLessThanOrEqual(401);
  });

  it('caps the deficit at 15 % from age 65 alone', () => {
    const out = generatePlan(
      input({
        sexAtBirth: 'male', ageYears: 66, heightCm: 172, weightKg: 90,
        activityLevel: 'light', goal: 'fat_loss',
      }),
      pack,
    );
    expect(out.warnings).toContain('deficit_capped_age');
  });

  /**
   * The 1.0 %/week band. Unreachable through generatePlan with plausible inputs — the 750 kcal
   * absolute cap always binds first — so it is exercised directly. It still has to work: the pack
   * is the only thing standing between a future constant change and an unbounded deficit.
   */
  it('caps the deficit at 1.0 % of body weight per week', () => {
    const result = clampTarget(1200, 1300, 2600, input({ weightKg: 50, sexAtBirth: 'male' }), pack);
    expect(result.warnings).toContain('deficit_capped_weekly_rate');
    // max daily deficit = 0.01 x 50 x 7700 / 7 = 550
    expect(result.target).toBeGreaterThanOrEqual(2600 - 550);
  });

  it('raises a sub-BMR target up to BMR', () => {
    const result = clampTarget(1400, 1800, 2200, input({ sexAtBirth: 'male' }), pack);
    expect(result.warnings).toContain('target_raised_to_bmr');
    expect(result.target).toBe(1800);
  });
});

describe('protein caps and floors (docs/04 §5)', () => {
  const weights = computeBodyWeights(input({ heightCm: 173, weightKg: 95 }), pack);

  it('honours an in-range coach override', () => {
    const subject = input({ heightCm: 173, weightKg: 95, goal: 'fat_loss', coachProteinRate: 2.0 });
    expect(computeProtein(subject, 2345, weights, 'fat_loss', pack).rate).toBe(2.0);
  });

  it('clamps a coach override to the goal range instead of obeying it', () => {
    const low = input({ heightCm: 173, weightKg: 95, goal: 'fat_loss', coachProteinRate: 0.5 });
    const high = input({ heightCm: 173, weightKg: 95, goal: 'fat_loss', coachProteinRate: 9.0 });
    expect(computeProtein(low, 2345, weights, 'fat_loss', pack).rate).toBe(1.5);
    expect(computeProtein(high, 2345, weights, 'fat_loss', pack).rate).toBe(2.0);
  });

  it('tapers to 1.0 g/kg with renal caution for age > 60 with diabetes and hypertension', () => {
    const subject = input({
      ageYears: 61, heightCm: 170, weightKg: 88,
      conditions: ['type2_diabetes', 'hypertension'], goal: 'fat_loss',
    });
    const result = computeProtein(subject, 1680, computeBodyWeights(subject, pack), 'fat_loss', pack);
    expect(result.rate).toBe(1.0);
    expect(result.warnings).toContain('renal_protein_caution');
  });

  it('never plans below the ICMR RDA of 0.83 g/kg actual weight', () => {
    const subject = input({ heightCm: 150, weightKg: 120, goal: 'maintenance' });
    const result = computeProtein(subject, 1200, computeBodyWeights(subject, pack), 'maintenance', pack);
    expect(result.grams).toBeGreaterThanOrEqual(0.83 * 120);
  });

  it('caps protein at 40 % of target energy', () => {
    const subject = input({ heightCm: 150, weightKg: 130, goal: 'fat_loss' });
    const result = computeProtein(subject, 1500, computeBodyWeights(subject, pack), 'fat_loss', pack);
    expect(result.grams * 4).toBeLessThanOrEqual(0.4 * 1500 + 0.01);
  });
});

describe('fat, fibre, sodium, sugar and water bounds', () => {
  it('never drops below 20 % of energy or 0.6 g/kg ABW', () => {
    const fat = computeFat(['none'], 'maintenance', 1200, 90, pack);
    expect(fat.grams).toBeGreaterThanOrEqual(0.6 * 90);
    expect(fat.pct).toBeGreaterThanOrEqual(0.2);
  });

  it('takes the highest declared condition percentage when several apply', () => {
    const fat = computeFat(['pcos', 'type2_diabetes'], 'muscle_gain', 2000, 70, pack);
    expect(fat.pct).toBeCloseTo(0.3, 2);
  });

  it('clamps fibre to the 25–45 g band', () => {
    expect(computeFibre(1000, pack)).toBe(25);
    expect(computeFibre(5000, pack)).toBe(45);
  });

  it('tightens saturated fat to 7 % of energy under hypertension', () => {
    const base = computeSaturatedFatMaxG(2000, ['none'], pack);
    const tight = computeSaturatedFatMaxG(2000, ['hypertension'], pack);
    expect(tight).toBeLessThan(base);
    expect(tight * 9).toBeCloseTo(0.07 * 2000, 6);
  });

  it('uses the 5 %-of-energy bound when no sugar-restricted condition is declared', () => {
    expect(computeAddedSugarMaxG(2400, ['none'], pack)).toBeCloseTo((0.05 * 2400) / 4, 6);
  });

  it('scales water to 33 ml/kg inside a 2–4 L band', () => {
    expect(computeWaterMl(40, pack)).toBe(2000);
    expect(computeWaterMl(95, pack)).toBeCloseTo(95 * 33, 6);
    expect(computeWaterMl(200, pack)).toBe(4000);
  });
});

describe('the 100 g carbohydrate floor is never breached (docs/05 §2)', () => {
  it('gives back protein before it breaches the floor', () => {
    const subject = input({ heightCm: 150, weightKg: 100, goal: 'fat_loss' });
    const result = computeCarbs(1200, 160, 40, subject, pack);
    expect(result.carbG).toBeGreaterThanOrEqual(100);
    expect(result.proteinG).toBeLessThan(160);
    expect(result.warnings).toContain('protein_reduced_for_carb_floor');
  });

  it('raises the target when protein has nothing left to give', () => {
    const subject = input({ heightCm: 150, weightKg: 60, goal: 'fat_loss' });
    const result = computeCarbs(900, 50, 60, subject, pack);
    expect(result.carbG).toBe(100);
    expect(result.targetKcal).toBeGreaterThan(900);
  });

  it('leaves an ordinary plan untouched', () => {
    const result = computeCarbs(2345, 136, 65, input({ weightKg: 95 }), pack);
    expect(result.warnings).toHaveLength(0);
    expect(result.targetKcal).toBe(2345);
  });
});

describe('override intersection (docs/04 §6)', () => {
  it('matches nothing for a plain profile', () => {
    const result = applyOverrides(input({ budgetTier: 'medium', lifestyle: 'flexible' }), 2000, 0.2, 2000, 25, pack);
    expect(result.appliedPriorities).toHaveLength(0);
  });

  it('hard-excludes allergens including cross-contamination tags', () => {
    const result = applyOverrides(
      input({ foodAllergies: ['peanut'] }), 2000, 0.2, 2000, 25, pack,
    );
    expect(result.constraints.excludeTags).toContain('allergen:peanut');
    expect(result.constraints.excludeTags).toContain('may_contain:peanut');
  });

  it('excludes animal groups by diet preference, and root veg for jain', () => {
    const vegan = applyOverrides(input({ foodPreference: 'vegan' }), 2000, 0.2, 2000, 25, pack);
    expect(vegan.constraints.excludeTags).toContain('group:dairy');

    const jain = applyOverrides(input({ foodPreference: 'jain' }), 2000, 0.2, 2000, 25, pack);
    expect(jain.constraints.excludeTags).toContain('attr:root_veg');
    expect(jain.constraints.excludeTags).toContain('group:meat');
  });

  it('applies budget and lifestyle soft filters', () => {
    const low = applyOverrides(input({ budgetTier: 'low' }), 2000, 0.2, 2000, 25, pack);
    expect(low.constraints.costLowFraction).toBe(0.8);

    const student = applyOverrides(input({ lifestyle: 'student' }), 2000, 0.2, 2000, 25, pack);
    expect(student.constraints.maxPrepMinutes).toBe(15);

    const office = applyOverrides(input({ lifestyle: 'office' }), 2000, 0.2, 2000, 25, pack);
    expect(office.constraints.minPortableMeals).toBe(2);
  });

  it('takes the tighter value when two conditions set the same constraint', () => {
    const result = applyOverrides(
      input({ conditions: ['type2_diabetes', 'hypertension'] }), 2000, 0.2, 2000, 40, pack,
    );
    expect(result.constraints.sodiumMaxMg).toBe(1500);
    expect(result.constraints.addedSugarMaxG).toBe(25);
    expect(result.constraints.maxDeficitPct).toBe(0.15);
  });

  it('forces easy-digest and zero deficit for an unlocked post_surgery plan', () => {
    const result = applyOverrides(
      input({ conditions: ['post_surgery'], clinicianAttestation: true }), 2000, 0.2, 2000, 25, pack,
    );
    expect(result.constraints.requireEasyDigest).toBe(true);
    expect(result.constraints.maxDeficitPct).toBe(0);
  });

  it('lets a clinician attestation unlock post_surgery end to end', () => {
    const out = generatePlan(
      input({ conditions: ['post_surgery'], clinicianAttestation: true, goal: 'fat_loss' }),
      pack,
    );
    expect(out.targets).not.toBeNull();
    expect(out.constraints?.requireEasyDigest).toBe(true);
  });
});

describe('meal distribution (docs/04 §7)', () => {
  const constraints = (patch: Parameters<typeof input>[0]) =>
    applyOverrides(input(patch), 2000, 0.2, 2000, 25, pack).constraints;

  it('gives the lower 10 g floor only to snacks under 10 % of target', () => {
    // docs/04 §7: the 4-meal `snack` slot is 15 % of target, so it does NOT get the exception.
    const four = distributeMeals({
      mealCount: '4', targetKcal: 2000, proteinTargetG: 120, abw: 70,
      constraints: constraints({}), pack,
    });
    expect(four.find((m) => m.slot === 'snack')?.minProteinG).toBeGreaterThanOrEqual(20);
    expect(four.find((m) => m.slot === 'lunch')?.minProteinG).toBeGreaterThanOrEqual(20);

    // The 5_6 pattern's mid-morning (8 %) and bedtime (5 %) slots do qualify.
    const six = distributeMeals({
      mealCount: '5_6', targetKcal: 2000, proteinTargetG: 120, abw: 70,
      constraints: constraints({}), pack,
    });
    expect(six.find((m) => m.slot === 'mid_morning')?.minProteinG).toBe(10);
    expect(six.find((m) => m.slot === 'bedtime')?.minProteinG).toBe(10);
    expect(six.find((m) => m.slot === 'lunch')?.minProteinG).toBeGreaterThanOrEqual(20);
  });

  it('marks the 5_6 bedtime slot optional', () => {
    const meals = distributeMeals({
      mealCount: '5_6', targetKcal: 2000, proteinTargetG: 120, abw: 70,
      constraints: constraints({}), pack,
    });
    expect(meals.find((m) => m.slot === 'bedtime')?.optional).toBe(true);
  });

  it('refuses a 3-meal pattern when diabetes requires 4 eating occasions', () => {
    expect(() =>
      distributeMeals({
        mealCount: '3', targetKcal: 2000, proteinTargetG: 120, abw: 70,
        constraints: constraints({ conditions: ['type2_diabetes'] }), pack,
      }),
    ).toThrow(/requires 4/);
  });

  it('accepts a slot inside the +/-5 pp tolerance and rejects one outside it', () => {
    expect(isWithinTolerance(500, 2000, 0.25, pack)).toBe(true);
    expect(isWithinTolerance(700, 2000, 0.25, pack)).toBe(false);
  });
});

describe('output assertions fail loudly (docs/04 §8)', () => {
  const coherent = roundTargets({
    kcal: 2345, proteinG: 136, fatG: 65, carbG: 304, fibreG: 33,
    sodiumMaxMg: 2000, addedSugarMaxG: 29, saturatedFatMaxG: 26, waterMl: 3135,
  });

  it('passes a coherent target set', () => {
    expect(() => assertTargetsCoherent(coherent, pack)).not.toThrow();
  });

  it('throws when macro energy drifts more than 3 % from the target', () => {
    expect(() => assertTargetsCoherent({ ...coherent, carbG: 500 }, pack)).toThrow(EngineAssertionError);
  });

  it('throws when the carb floor is breached', () => {
    // 60 g carbs, rebalanced so the energy sum still reconciles — only the floor is wrong.
    expect(() =>
      assertTargetsCoherent({ ...coherent, carbG: 60, fatG: 173 }, pack),
    ).toThrow(/carb floor breached/);
  });

  it('throws when the meal split does not reconstitute the target', () => {
    const meals = [{ slot: 'lunch', pct: 1, kcal: 1000, minProteinG: 20, optional: false }];
    expect(() => assertMealsCoherent(meals, 2345, pack)).toThrow(/meal kcal sum/);
  });

  it('accepts a meal split that reconstitutes the target', () => {
    const meals = distributeMeals({
      mealCount: '4', targetKcal: 2345, proteinTargetG: 136, abw: 75.4,
      constraints: applyOverrides(input({}), 2345, 0.2, 2000, 29, pack).constraints, pack,
    });
    expect(() => assertMealsCoherent(meals, 2345, pack)).not.toThrow();
  });
});

describe('defensive paths', () => {
  it('ignores an override rule whose `when` clause matches nothing known', () => {
    const malformed = { ...pack, overrides: [{ priority: 5, when: {}, constraints: { sodium_max_mg: 1 } }] };
    const result = applyOverrides(input({}), 2000, 0.2, 2000, 25, malformed);
    expect(result.appliedPriorities).toHaveLength(0);
    expect(result.constraints.sodiumMaxMg).toBe(2000);
  });

  it('throws when the pack has no protein rate for the goal', () => {
    const stripped = {
      ...pack,
      macros: { ...pack.macros, protein: { ...pack.macros.protein, rate_g_per_kg_abw: {} } },
    };
    expect(() =>
      computeProtein(input({}), 2000, computeBodyWeights(input({}), pack), 'fat_loss', stripped),
    ).toThrow(/no protein rate for goal/);
  });

  it('drops the sodium cap to 1500 mg under hypertension', () => {
    expect(computeSodiumMaxMg(['none'], pack)).toBe(2000);
    expect(computeSodiumMaxMg(['hypertension'], pack)).toBe(1500);
  });
});
