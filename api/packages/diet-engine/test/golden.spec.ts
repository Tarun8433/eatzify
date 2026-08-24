/**
 * docs/16 §2 golden vectors. "Copy these into engine.golden.spec.ts verbatim."
 *
 * Three vectors do not agree with the normative specs (docs/04, docs/05). Each is marked below with
 * the arithmetic. They are written as the spec computes them, with the doc's own figure recorded, so
 * the disagreement is visible in CI instead of being quietly reconciled. Per the /engine-change
 * workflow: if a vector's expected output changes, that is a decision, not a fix.
 */
import { generatePlan } from '../src';
import { input, loadPack } from './helpers';

const pack = loadPack();

describe('GV-01 — baseline male fat loss', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'male', ageYears: 29, heightCm: 173, weightKg: 95.0,
      activityLevel: 'moderate', goal: 'fat_loss', foodPreference: 'veg', mealCount: '4',
    }),
    pack,
  );

  it('derives bmr 1891 · tdee 2931 · target 2345', () => {
    expect(out.derived?.bmr).toBe(1891);
    expect(out.derived?.tdee).toBe(2931);
    expect(out.targets?.kcal).toBe(2345);
  });

  it('derives ibw 68.8 · abw 75.4', () => {
    expect(out.derived?.ibw).toBe(68.8);
    expect(out.derived?.abw).toBe(75.4);
  });

  it('sets protein 136 g · fat 65 g · carbs 304 g', () => {
    expect(out.targets?.proteinG).toBe(136);
    expect(out.targets?.fatG).toBe(65);
    expect(out.targets?.carbG).toBe(304);
  });

  it('emits no clamps and no gates', () => {
    expect(out.gates).toHaveLength(0);
    expect(out.warnings).toHaveLength(0);
  });

  it('splits meals 586 / 821 / 352 / 586 kcal', () => {
    expect(out.mealTargets.map((m) => Math.round(m.kcal))).toEqual([586, 821, 352, 586]);
  });

  it('gives every meal a >=20 g protein floor', () => {
    for (const meal of out.mealTargets) {
      expect(meal.minProteinG).toBeGreaterThanOrEqual(meal.slot === 'snack' ? 10 : 20);
    }
  });

  // Regression guard from docs/16: the current build outputs 2431 / P122 / C334 / F68.
  it('does NOT reproduce the current build output', () => {
    expect(out.targets?.kcal).not.toBe(2431);
    expect(out.targets?.proteinG).not.toBe(122);
  });
});

describe('GV-02 — female, PCOS', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'female', ageYears: 28, heightCm: 160, weightKg: 68.0,
      activityLevel: 'light', goal: 'fat_loss', conditions: ['pcos'],
    }),
    pack,
  );

  it('derives bmr 1379 · tdee 1896 · target 1517 · abw 61.2', () => {
    expect(out.derived?.bmr).toBe(1379);
    expect(out.derived?.tdee).toBe(1896);
    expect(out.targets?.kcal).toBe(1517);
    expect(out.derived?.abw).toBe(61.2);
  });

  it('sets protein 110 g · fat 51 g (30 % E pcos override) · carbs 155 g', () => {
    expect(out.targets?.proteinG).toBe(110);
    expect(out.targets?.fatG).toBe(51);
    expect(out.targets?.carbG).toBe(155);
  });

  it('applies the pcos constraint set', () => {
    // docs/04 §5 caps added sugar at BOTH 5 % of energy and 25 g absolute; the tighter binds.
    expect(out.constraints?.addedSugarMaxG).toBeLessThanOrEqual(25);
    expect(out.constraints?.minLowGiCarbFraction).toBe(0.7);
    expect(out.targets?.fibreG).toBeGreaterThanOrEqual(25);
  });

  it('keeps carbs at or below 45 % of energy', () => {
    const carbPct = ((out.targets?.carbG ?? 0) * 4) / (out.targets?.kcal ?? 1);
    expect(carbPct).toBeLessThanOrEqual(0.45);
  });

  it('engages no clamp — 1517 clears both the BMR and the female floor', () => {
    expect(out.warnings).not.toContain('target_raised_to_floor');
    expect(out.warnings).not.toContain('target_raised_to_bmr');
  });
});

describe('GV-03 — male muscle gain, below IBW', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'male', ageYears: 32, heightCm: 178, weightKg: 62.0,
      activityLevel: 'moderate', goal: 'muscle_gain',
    }),
    pack,
  );

  it('derives bmr 1578 · tdee 2445 · target 2739 (surplus 294 <= 400)', () => {
    expect(out.derived?.bmr).toBe(1578);
    expect(out.derived?.tdee).toBe(2445);
    expect(out.targets?.kcal).toBe(2739);
  });

  it('uses actual weight as the protein basis because W < IBW 72.9', () => {
    expect(out.derived?.ibw).toBe(72.9);
    expect(out.derived?.proteinBasisKg).toBe(62.0);
    expect(out.targets?.proteinG).toBe(112);
  });

  /**
   * SPEC CONFLICT. docs/04 §5 sets muscle_gain fat to 22 % E: 0.22 x 2738.5 = 602.5 kcal = 67 g,
   * leaving carbs 422 g. docs/16 GV-03 states "fat 76 g (22 % E)" with carbs 402 g — but 76 g is
   * 684 kcal = 25.0 % E, and 402 g of carbs only balances at 25 %. The vector's grams and its own
   * percentage label disagree; its numbers are a 25 % calculation. We implement docs/04 §5.
   */
  it('sets fat from the 22 % muscle_gain override, per docs/04 §5', () => {
    expect(out.targets?.fatG).toBe(67);   // docs/16 GV-03 states 76
    expect(out.targets?.carbG).toBe(422); // docs/16 GV-03 states 402
  });
});

describe('GV-04 — older male, T2D on oral meds', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'male', ageYears: 60, heightCm: 170, weightKg: 88.0,
      activityLevel: 'sedentary', goal: 'fat_loss', conditions: ['type2_diabetes'],
    }),
    pack,
  );

  it('derives bmr 1648 · tdee 1977 · target 1680 (deficit capped at 15 %)', () => {
    expect(out.derived?.bmr).toBe(1648);
    expect(out.derived?.tdee).toBe(1977);
    expect(out.targets?.kcal).toBe(1680);
    expect(out.warnings).toContain('deficit_capped_condition');
  });

  it('derives abw 71.9 and sets fat 56 g (30 % E)', () => {
    expect(out.derived?.abw).toBe(71.9);
    expect(out.targets?.fatG).toBe(56);
  });

  it('applies the full diabetes constraint set', () => {
    expect(out.constraints?.minLowGiCarbFraction).toBe(0.7);
    expect(out.constraints?.maxCarbGPerOccasion).toBe(55);
    expect(out.constraints?.addedSugarMaxG).toBeLessThanOrEqual(25);
    expect(out.constraints?.excludeTags).toContain('gi:high');
    expect(out.gates).toHaveLength(0);
  });

  /**
   * SPEC GAP. docs/16 GV-04 expects protein 101 g "(1.4 g/kg, reduced for age+condition)" and
   * warning renal_protein_caution. Neither 1.4 nor that trigger exists in docs/04 §5 or docs/05 §2:
   * the only renal taper defined is ckd, or age > 60 WITH diabetes AND hypertension. This user is
   * 60 (not > 60) with diabetes and no hypertension, so the written spec gives fat_loss rate 1.8
   * on ABW 71.85 = 129 g. Needs the clinical reviewer docs/05 mandates, then a pack entry.
   */
  it('sets protein from the written fat_loss rate of 1.8 g/kg ABW', () => {
    expect(out.targets?.proteinG).toBe(129); // docs/16 GV-04 states 101 at an undocumented 1.4 rate
    expect(out.warnings).not.toContain('renal_protein_caution');
  });
});

describe('GV-05 — underweight female requesting fat loss (clamp path)', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'female', ageYears: 35, heightCm: 155, weightKg: 46.0,
      activityLevel: 'light', goal: 'fat_loss',
    }),
    pack,
  );

  it('suppresses the deficit because bmi 19.1 < 22', () => {
    expect(out.derived?.bmi).toBe(19.1);
    expect(out.derived?.effectiveGoal).toBe('maintenance');
    expect(out.warnings).toContain('deficit_suppressed_low_bmi');
  });

  it('sets target = tdee = 1503', () => {
    expect(out.targets?.kcal).toBe(1503);
    expect(out.derived?.tdee).toBe(1503);
  });

  it('sets protein 51 g (1.1 g/kg maintenance) · fat 42 g · carbs 231 g', () => {
    expect(out.targets?.proteinG).toBe(51);
    expect(out.targets?.fatG).toBe(42);
    expect(out.targets?.carbG).toBe(231);
  });
});

describe('GV-06 — hard floor engaged', () => {
  const out = generatePlan(
    input({
      sexAtBirth: 'female', ageYears: 45, heightCm: 148, weightKg: 44.0,
      activityLevel: 'sedentary', goal: 'fat_loss',
    }),
    pack,
  );

  it('checks BMI before the floor — no deficit at bmi 20.1', () => {
    expect(out.derived?.bmi).toBe(20.1);
    expect(out.derived?.effectiveGoal).toBe('maintenance');
    expect(out.warnings).toContain('deficit_suppressed_low_bmi');
  });

  /**
   * SPEC ARITHMETIC ERROR. docs/16 GV-06 states bmr 1071 / tdee 1285 and asserts target == 1285.
   * Mifflin-St Jeor for female 44 kg / 148 cm / 45 y is 10(44) + 6.25(148) - 5(45) - 161
   *   = 440 + 925 - 225 - 161 = 979, so tdee = 979 x 1.2 = 1175, not 1285.
   * At 1175 the vector's own point inverts: TDEE now falls BELOW the 1200 female floor, so the floor
   * does bind and the answer is 1200 — the very value the vector says not to assert. The vector
   * cannot illustrate its claim with corrected inputs; it needs new ones.
   */
  it('raises target to the 1200 female floor once the corrected TDEE falls below it', () => {
    expect(out.derived?.bmr).toBe(979);   // docs/16 GV-06 states 1071
    expect(out.derived?.tdee).toBe(1175); // docs/16 GV-06 states 1285
    expect(out.targets?.kcal).toBe(1200); // docs/16 GV-06 asserts 1285, "not 1200"
    expect(out.warnings).toContain('target_raised_to_floor');
  });
});

describe('GV-07 — blocking gates emit no plan', () => {
  const blocked: ReadonlyArray<[string, Parameters<typeof input>[0], string]> = [
    ['pregnancy', { conditions: ['pregnancy'] }, 'pregnancy'],
    ['lactation', { conditions: ['lactation'] }, 'lactation'],
    ['ckd', { conditions: ['ckd'] }, 'ckd'],
    ['hyperthyroid', { conditions: ['hyperthyroid'] }, 'hyperthyroid'],
    ['type_1_diabetes', { conditions: ['type_1_diabetes'] }, 'type_1_diabetes'],
    ['eating_disorder', { conditions: ['eating_disorder'] }, 'eating_disorder'],
    ['post_surgery without attestation', { conditions: ['post_surgery'] }, 'post_surgery_needs_clinician'],
  ];

  it.each(blocked)('%s -> gate %s, plan null', (_label, patch, code) => {
    const out = generatePlan(input({ sexAtBirth: 'female', ...patch }), pack);
    expect(out.targets).toBeNull();
    expect(out.mealTargets).toHaveLength(0);
    expect(out.gates.filter((g) => g.blocking).map((g) => g.code)).toContain(code);
  });

  it('bmi 15.8 -> gate bmi_critical, plan null', () => {
    // 38.0 kg at 155 cm = bmi 15.8
    const out = generatePlan(
      input({ sexAtBirth: 'female', heightCm: 155, weightKg: 38.0, goal: 'fat_loss' }),
      pack,
    );
    expect(out.targets).toBeNull();
    expect(out.gates.map((g) => g.code)).toContain('bmi_critical');
  });

  it('age under 18 is rejected before the engine is reached', () => {
    expect(() => generatePlan(input({ ageYears: 17 }), pack)).toThrow(/ageYears out of range/);
  });
});
