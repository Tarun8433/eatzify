import { evaluateGates, bmiOf } from '../src/profile/screening';

const base = {
  ageYears: 32,
  heightCm: 172,
  weightKg: 74.5,
  conditions: [] as string[],
};

describe('screening — docs/05 §3 gates, enforced server-side', () => {
  it('lets a healthy adult through with no gates', () => {
    expect(evaluateGates(base)).toEqual({ blocked: [], clinicianGated: [] });
  });

  it.each(['ckd', 'pregnancy', 'lactation', 'hyperthyroid', 'post_surgery'])(
    'blocks on %s',
    (condition) => {
      expect(
        evaluateGates({ ...base, conditions: [condition] }).blocked,
      ).toContain(condition);
    },
  );

  it('does not block the plan-with-constraints conditions (docs/05 §3)', () => {
    const gates = evaluateGates({
      ...base,
      conditions: [
        'type2_diabetes',
        'prediabetes',
        'hypertension',
        'pcos',
        'hypothyroid',
      ],
    });

    expect(gates.blocked).toEqual([]);
  });

  it('blocks on declared insulin use or kidney disease (§4 Q2)', () => {
    expect(
      evaluateGates({ ...base, screenedInsulinOrKidney: true }).blocked,
    ).toContain('insulin_or_kidney');
  });

  it('blocks on declared eating disorder history (§4 Q3)', () => {
    expect(
      evaluateGates({ ...base, screenedEatingDisorder: true }).blocked,
    ).toContain('eating_disorder');
  });

  it('clinician-gates a declared special diet rather than blocking it (§4 Q1)', () => {
    const gates = evaluateGates({ ...base, screenedSpecialDiet: true });

    expect(gates.blocked).toEqual([]);
    expect(gates.clinicianGated).toContain('special_diet');
  });

  /// The key is `age_ineligible`, matching both `GATE_COPY` in plan-copy.ts and the
  /// `AGE_INELIGIBLE` error code docs/09 §4 names. It was `age_below_minimum`, which no copy
  /// table had an entry for, so a minor got the generic blocking-condition string.
  it('blocks under 18 and BMI under 16', () => {
    expect(evaluateGates({ ...base, ageYears: 17 }).blocked).toContain(
      'age_ineligible',
    );
    expect(evaluateGates({ ...base, weightKg: 45 }).blocked).toContain(
      'bmi_below_16',
    );
  });

  it('clinician-gates age 70+ and BMI 40+ without blocking', () => {
    expect(evaluateGates({ ...base, ageYears: 70 }).clinicianGated).toContain(
      'age_70_plus',
    );

    const heavy = evaluateGates({ ...base, weightKg: 125 });
    expect(heavy.clinicianGated).toContain('bmi_40_plus');
    expect(heavy.blocked).toEqual([]);
  });

  it('reports every gate that fires, not just the first', () => {
    const gates = evaluateGates({
      ...base,
      ageYears: 75,
      conditions: ['ckd', 'pregnancy'],
      screenedEatingDisorder: true,
    });

    expect(gates.blocked).toEqual(
      expect.arrayContaining(['ckd', 'pregnancy', 'eating_disorder']),
    );
    expect(gates.clinicianGated).toContain('age_70_plus');
  });

  it('a "no" to a screening question is not a gate', () => {
    expect(
      evaluateGates({
        ...base,
        screenedSpecialDiet: false,
        screenedInsulinOrKidney: false,
        screenedEatingDisorder: false,
      }),
    ).toEqual({ blocked: [], clinicianGated: [] });
  });

  it('computes BMI from cm and kg', () => {
    expect(bmiOf(74.5, 172)).toBeCloseTo(25.18, 2);
  });
});
