import {
  windowedTrendChange,
  BOUNDS,
  MEASUREMENT_KINDS,
  canOverwrite,
  isSuspectDelta,
  isWithinBounds,
  movingAverage,
  trendChange,
} from '../src/measurements/measurement-rules';

/// docs/16 §GV worked example: "delta 30 kg in 1 day → is_suspect true → excluded from MA7 and from
/// the adjuster", and "Change readout computed from MA7, never from min/max. Assert change ≠ −30.0."
/// These tests encode that example directly — it is the defect docs/15 recorded in the old build.
describe('measurement rules', () => {
  describe('the delta rule', () => {
    it('flags a 30 kg jump in one day (docs/16 worked example)', () => {
      expect(
        isSuspectDelta(
          'weight',
          45,
          { value: 75, diaryDate: '2026-08-24' },
          '2026-08-25',
        ),
      ).toBe(true);
    });

    it('accepts a normal day-to-day fluctuation', () => {
      expect(
        isSuspectDelta(
          'weight',
          74.8,
          { value: 74.5, diaryDate: '2026-08-24' },
          '2026-08-25',
        ),
      ).toBe(false);
    });

    it('scales by elapsed days — 4 kg over three weeks is not suspect', () => {
      expect(
        isSuspectDelta(
          'weight',
          70.5,
          { value: 74.5, diaryDate: '2026-08-04' },
          '2026-08-25',
        ),
      ).toBe(false);
    });

    it('the same 4 kg overnight IS suspect', () => {
      expect(
        isSuspectDelta(
          'weight',
          70.5,
          { value: 74.5, diaryDate: '2026-08-24' },
          '2026-08-25',
        ),
      ).toBe(true);
    });

    it('a first reading is never suspect — there is no delta to judge it by', () => {
      expect(isSuspectDelta('weight', 45, null, '2026-08-25')).toBe(false);
    });

    it('kinds with no delta limit are never flagged', () => {
      expect(
        isSuspectDelta(
          'hba1c',
          12,
          { value: 5, diaryDate: '2026-08-24' },
          '2026-08-25',
        ),
      ).toBe(false);
    });
  });

  describe('bounds', () => {
    it('refuses impossible values outright', () => {
      expect(isWithinBounds('weight', 5)).toBe(false);
      expect(isWithinBounds('weight', 400)).toBe(false);
      expect(isWithinBounds('weight', 74.5)).toBe(true);
    });
  });

  describe('the change readout', () => {
    it('excludes suspect points from the average', () => {
      const withTypo = movingAverage([
        { value: 74, isSuspect: false },
        { value: 74.2, isSuspect: false },
        { value: 44, isSuspect: true },
      ]);

      // The 44 must not drag the average down.
      expect(withTypo).toBeCloseTo(74.1, 1);
    });

    it('never reports the old build’s −30.0 from one bad reading', () => {
      const change = trendChange([
        { value: 75, isSuspect: false },
        { value: 74.8, isSuspect: false },
        { value: 45, isSuspect: true },
        { value: 74.6, isSuspect: false },
        { value: 74.5, isSuspect: false },
      ]);

      expect(change).not.toBeNull();
      expect(Math.abs(change!)).toBeLessThan(1);
    });

    it('returns null with fewer than two usable readings — no trend is not zero trend', () => {
      expect(trendChange([{ value: 74, isSuspect: false }])).toBeNull();
      expect(trendChange([])).toBeNull();
    });

    it('reports a real loss over time', () => {
      const change = trendChange([
        { value: 80, isSuspect: false },
        { value: 79.5, isSuspect: false },
        { value: 78, isSuspect: false },
        { value: 77.5, isSuspect: false },
      ]);

      expect(change).toBeLessThan(0);
    });

    it('averages only the last N points', () => {
      const points = Array.from({ length: 20 }, (_, i) => ({
        value: i < 13 ? 100 : 70,
        isSuspect: false,
      }));

      expect(movingAverage(points, 7)).toBe(70);
    });
  });

  /// D-96: `steps` allowed 100000 while the column was numeric(7,2) — max 99999.99. The value
  /// passed every check here and then threw at the INSERT, so the user was told the number was
  /// fine and then handed a 500. A bound the storage cannot hold is not a bound.
  describe('the windowed change readout (docs/21 §3)', () => {
    const day = (d: number) =>
      `2026-08-${String(d).padStart(2, '0')}`;

    it('ignores readings older than the window', () => {
      // A month of loss long past, then a stable fortnight: since-start says "down", the last
      // 30 days say "about the same" — the windowed figure is the honest recent one.
      const points = [
        { value: 90, isSuspect: false, diaryDate: '2026-06-01' },
        { value: 80, isSuspect: false, diaryDate: '2026-06-20' },
        { value: 74, isSuspect: false, diaryDate: day(1) },
        { value: 74.2, isSuspect: false, diaryDate: day(15) },
        { value: 74, isSuspect: false, diaryDate: day(29) },
      ];
      expect(windowedTrendChange(points, 30)).toBeCloseTo(0, 0);
    });

    it('has no trend when the window holds one reading', () => {
      const points = [
        { value: 80, isSuspect: false, diaryDate: '2026-06-01' },
        { value: 74, isSuspect: false, diaryDate: day(29) },
      ];
      expect(windowedTrendChange(points, 30)).toBeNull();
    });

    it('is null on no readings at all', () => {
      expect(windowedTrendChange([], 30)).toBeNull();
    });
  });

  describe('every bound fits the column it is stored in', () => {
    // numeric(10,2): eight digits before the point.
    const COLUMN_MAX = 99999999.99;

    it.each(MEASUREMENT_KINDS)('%s max is storable', (kind) => {
      expect(BOUNDS[kind].max).toBeLessThanOrEqual(COLUMN_MAX);
    });

    it('accepts the largest legal step count', () => {
      expect(isWithinBounds('steps', 100000)).toBe(true);
    });

    it('still refuses one past it', () => {
      expect(isWithinBounds('steps', 100001)).toBe(false);
    });
  });

  /// D-97. One row per kind per diary day means every write is an overwrite, so "who wins" is a
  /// rule the storage forces us to have rather than one we chose to add.
  describe('a correction outranks a device (canOverwrite)', () => {
    it('lets a sync fill a day nobody has recorded', () => {
      expect(canOverwrite(null, 'apple_health')).toBe(true);
      expect(canOverwrite(null, 'health_connect')).toBe(true);
    });

    it('refuses to let a sync overwrite a hand-typed figure', () => {
      // The whole point: someone corrects 9,500 steps to 8,000, and the next foreground sync must
      // not silently put 9,500 back. It leaves no trace, so they would never know.
      expect(canOverwrite('manual', 'apple_health')).toBe(false);
      expect(canOverwrite('manual', 'health_connect')).toBe(false);
    });

    it('lets a person overwrite a device, which is what the field is for', () => {
      expect(canOverwrite('apple_health', 'manual')).toBe(true);
      expect(canOverwrite('health_connect', 'manual')).toBe(true);
    });

    it('lets a person overwrite their own earlier entry', () => {
      expect(canOverwrite('manual', 'manual')).toBe(true);
    });

    it('lets a later sync refresh an earlier one', () => {
      // A step count grows through the day; the 9pm reading must replace the 9am one.
      expect(canOverwrite('apple_health', 'apple_health')).toBe(true);
      // And a phone that changed platforms is still not a person.
      expect(canOverwrite('apple_health', 'health_connect')).toBe(true);
    });
  });
});
