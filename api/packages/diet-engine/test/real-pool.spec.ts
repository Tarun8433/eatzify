import { generatePlan } from '../src/index';
import { buildPool } from '../src/foods';
import { input, loadPack, seedFoods } from './helpers';
import type { EngineInput } from '../src/types';

/**
 * docs/04 §8 against the real 281 foods.
 *
 * Every fixture-based test in this package passes while `assertFilledDayCoherent` throws for an
 * ordinary person, because a five-food fixture cannot contain the better-scoring wrong answer that
 * breaks the fill. D-167 found all of this by hand; this file is that run, automated, so the next
 * change to the search either holds or says so.
 */

const PACK = loadPack();
const FOODS = seedFoods();

/// Four people who between them exercise the corners the fill actually has to survive: a small
/// energy target, a large one, a vegan pool (no dairy, which is where most of the protein is), and
/// diabetes (a carbohydrate cap per eating occasion).
const PEOPLE: [string, Partial<EngineInput>][] = [
  ['a 30-year-old man maintaining', {}],
  [
    'a 45-year-old woman losing weight',
    {
      sexAtBirth: 'female',
      ageYears: 45,
      heightCm: 158,
      weightKg: 72,
      goal: 'fat_loss',
      activityLevel: 'light',
    },
  ],
  ['a vegan', { foodPreference: 'vegan' }],
  ['somebody with type 2 diabetes', { conditions: ['type2_diabetes'] }],
];

function plan(overrides: Partial<EngineInput>) {
  const person = input(overrides);
  const first = generatePlan(person, PACK);
  const pool = buildPool(FOODS, person, first.constraints!);
  return generatePlan(person, PACK, pool.foods);
}

describe.each(PEOPLE)('a day for %s', (_who, overrides) => {
  it('should be generated at all — the assertions are the plan, not a warning', () => {
    expect(() => plan(overrides)).not.toThrow();
  });

  it('should put food in every meal the pattern asks for', () => {
    const out = plan(overrides);

    expect(out.meals).toHaveLength(out.mealTargets.length);
    for (const meal of out.meals) {
      expect(meal.items.length).toBeGreaterThan(0);
    }
  });

  /**
   * Either the day lands, or it says why it could not. The second case is real: v1.0.0 caps a
   * diabetic eating occasion at 55 g of carbohydrate and asks for four of them, which is 220 g
   * against a 394 g carbohydrate target. No search satisfies both, so the plan comes back short
   * and carries `carb_cap_limits_energy` (D-231). What it must never do is breach the cap, or
   * quietly serve the missing 700 kcal as ghee.
   */
  it('should land the day within the pack tolerances, or say why not', () => {
    const out = plan(overrides);
    const targets = out.targets!;
    const sum = (pick: (m: (typeof out.meals)[number]) => number) =>
      out.meals.reduce((acc, m) => acc + pick(m), 0);

    if (out.warnings.includes('carb_cap_limits_energy')) {
      // Short, and short for the stated reason: every meal is against the cap.
      expect(sum((m) => m.kcal)).toBeLessThan(targets.kcal);
      for (const meal of out.meals) {
        expect(meal.carbG).toBeLessThanOrEqual(
          out.constraints!.maxCarbGPerOccasion!,
        );
      }
      return;
    }

    const kcal = sum((m) => m.kcal);
    const protein = sum((m) => m.proteinG);

    expect(Math.abs(kcal - targets.kcal) / targets.kcal).toBeLessThanOrEqual(
      PACK.validation.kcal_tolerance_pct,
    );
    expect(Math.abs(protein - targets.proteinG)).toBeLessThanOrEqual(
      PACK.validation.protein_tolerance_g,
    );
  });

  /// docs/04 §8 asserts the sodium cap; the added-sugar cap is what keeps cola out of breakfast
  /// without anybody having to tag a food as a breakfast food (D-167).
  it('should stay under the day ceilings', () => {
    const out = plan(overrides);
    const targets = out.targets!;
    const sodium = out.meals.reduce((acc, m) => acc + m.sodiumMg, 0);

    expect(sodium).toBeLessThanOrEqual(targets.sodiumMaxMg);
  });

  /// docs/04 §5 computes a fibre target and, until D-231, nothing aimed at it — which is how a day
  /// of cola, ghee and bhature could satisfy every other number.
  it('should reach the fibre target', () => {
    const out = plan(overrides);
    const fibre = out.meals.reduce((acc, m) => acc + m.fibreG, 0);

    expect(fibre).toBeGreaterThanOrEqual(out.targets!.fibreG * 0.8);
  });

  /// docs/04 §7: "every meal ≥ 20 g protein … except snacks < 10 % of target, which need ≥ 10 g".
  /// Held where the day still has protein to give — a meal cannot be asked for what is not left.
  it('should carry real protein into the first meals of the day', () => {
    const out = plan(overrides);
    const [first] = out.meals;

    expect(first!.proteinG).toBeGreaterThanOrEqual(
      Math.min(out.mealTargets[0]!.minProteinG, out.targets!.proteinG) * 0.9,
    );
  });

  /// A plan nobody can eat is not a plan: whey powder four times, or nineteen cups of tea.
  it('should not ask anybody to eat the same thing all day', () => {
    const out = plan(overrides);
    const ids = out.meals.flatMap((m) => m.items.map((i) => i.foodId));

    expect(new Set(ids).size).toBeGreaterThan(2);
    for (const meal of out.meals) {
      for (const item of meal.items) {
        expect(item.quantity).toBeLessThanOrEqual(6);
      }
    }
  });

  /// Rule 2: same input, same pack, byte-identical output. The search must not be order-dependent
  /// on anything but the pool it was handed.
  it('should produce the same day twice', () => {
    expect(JSON.stringify(plan(overrides).meals)).toBe(
      JSON.stringify(plan(overrides).meals),
    );
  });
});

/// docs/08 §4's food table holds ingredients as well as dishes, and a plan is made of dishes.
describe('what a plan may be made of (D-231)', () => {
  it('should never serve an ingredient on its own', () => {
    const out = plan({});
    const served = out.meals.flatMap((m) => m.items.map((i) => i.name));

    for (const ingredient of [
      'Wheat flour (atta)',
      'Maida (refined flour)',
      'Besan (gram flour)',
      'Suji / rava (raw)',
    ]) {
      expect(served).not.toContain(ingredient);
    }
  });
});

/// The conflict itself, named once so it cannot be "fixed" by loosening a tolerance.
describe('the diabetic carbohydrate cap (D-231)', () => {
  it('should refuse to choose between the cap and the split, and say so', () => {
    const out = plan({ conditions: ['type2_diabetes'] });

    expect(out.warnings).toContain('carb_cap_limits_energy');
    expect(out.constraints!.maxCarbGPerOccasion).toBe(55);
    // 4 occasions × 55 g is 220 g of carbohydrate; the split asks for far more.
    expect(out.constraints!.maxCarbGPerOccasion! * out.mealTargets.length).
      toBeLessThan(out.targets!.carbG);
  });

  it('should not warn for somebody without the cap', () => {
    expect(plan({}).warnings).not.toContain('carb_cap_limits_energy');
  });
});
