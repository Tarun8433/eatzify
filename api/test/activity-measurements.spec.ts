import {
  BOUNDS,
  MEASUREMENT_KINDS,
  MEASUREMENT_UNITS,
  isWithinBounds,
  unitFor,
} from '../src/measurements/measurement-rules';

/// Manual activity entry (D-80). Steps and calories burned are measurement KINDS rather than a new
/// module: one row per user per kind per diary day is exactly what a day's step count is.
describe('activity measurement kinds', () => {
  it('are part of the closed list', () => {
    expect(MEASUREMENT_KINDS).toContain('steps');
    expect(MEASUREMENT_KINDS).toContain('energy_burned_kcal');
  });

  it('accept a real day and refuse an impossible one', () => {
    expect(isWithinBounds('steps', 0)).toBe(true);
    expect(isWithinBounds('steps', 8432)).toBe(true);
    expect(isWithinBounds('steps', 100001)).toBe(false);
    expect(isWithinBounds('steps', -1)).toBe(false);

    expect(isWithinBounds('energy_burned_kcal', 410)).toBe(true);
    expect(isWithinBounds('energy_burned_kcal', 8001)).toBe(false);
  });

  it('carry their own units', () => {
    expect(unitFor('steps')).toBe('steps');
    expect(unitFor('energy_burned_kcal')).toBe('kcal');
  });
});

describe('the legal unit list is derived, not written twice', () => {
  /// The bug this guards: the DTO carried its own hardcoded list, so a kind added to BOUNDS passed
  /// every rule here and then 422'd at the boundary on a unit nobody had remembered to allow.
  it('covers every unit any kind is measured in', () => {
    for (const kind of MEASUREMENT_KINDS) {
      expect(MEASUREMENT_UNITS).toContain(BOUNDS[kind].unit);
    }
  });

  it('has no duplicates', () => {
    expect(MEASUREMENT_UNITS).toHaveLength(new Set(MEASUREMENT_UNITS).size);
  });
});

describe('a fast-changing count is never flagged as suspect', () => {
  /// A rest day after a marathon is a real 40,000-step swing. Flagging it would exclude a true
  /// reading from the trend (docs/16), which is the opposite of what the rule is for.
  it('has no daily delta rule for steps or energy burned', async () => {
    const { isSuspectDelta } =
      await import('../src/measurements/measurement-rules');
    expect(
      isSuspectDelta(
        'steps',
        2000,
        { value: 42000, diaryDate: '2026-08-28' },
        '2026-08-29',
      ),
    ).toBe(false);

    // The rule still applies where it belongs: a 30 kg overnight weight change is not real.
    expect(
      isSuspectDelta(
        'weight',
        50,
        { value: 80, diaryDate: '2026-08-28' },
        '2026-08-29',
      ),
    ).toBe(true);
  });

  it('water is a kind too, in millilitres (D-86)', () => {
    expect(MEASUREMENT_KINDS).toContain('water_ml');
    expect(unitFor('water_ml')).toBe('ml');
    expect(isWithinBounds('water_ml', 2640)).toBe(true);
    expect(isWithinBounds('water_ml', 0)).toBe(true);
    // Past what anyone drinks in a day, and past the point it stops being safe.
    expect(isWithinBounds('water_ml', 10001)).toBe(false);
  });
});
