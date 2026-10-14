import {
  ACTIVE_SHARE,
  activeKcalForSteps,
  kcalPer1000Steps,
} from '../src/measurements/walking-energy';
import { burnedFromSteps } from '../src/logs/logs.service';

/// D-267: Home's "burned" is the ACTIVE kcal of the day's steps at the person's own weight — the
/// resting part removed, because the plan's TDEE already counts it.
describe('active kcal from steps', () => {
  const rateFor = (weightKg: number) =>
    kcalPer1000Steps({ weightKg, heightCm: 170, days: [] })!;

  it('should keep only the share above resting at the default pace', () => {
    // MET at 80 m/min = (0.1 × 80 + 3.5) / 3.5 ≈ 3.29; active share = 2.29 / 3.29.
    expect(ACTIVE_SHARE).toBeCloseTo(2.2857 / 3.2857, 4);
  });

  it('should rise with body weight for the same steps', () => {
    const light = activeKcalForSteps(10834, rateFor(55));
    const heavy = activeKcalForSteps(10834, rateFor(95));
    expect(heavy).toBeGreaterThan(light);
  });

  it('should give a plausible figure for a 75 kg person walking 10,834 steps', () => {
    const kcal = activeKcalForSteps(10834, rateFor(75));
    expect(kcal).toBeGreaterThan(250);
    expect(kcal).toBeLessThan(320);
  });

  it('should be nought for no steps', () => {
    expect(activeKcalForSteps(0, rateFor(75))).toBe(0);
  });
});

describe('burnedFromSteps', () => {
  const rate = kcalPer1000Steps({ weightKg: 75, heightCm: 170, days: [] })!;

  it("should ignore the phone's figure when steps and a weight are known", () => {
    expect(burnedFromSteps(10834, rate, 875)).toBe(
      activeKcalForSteps(10834, rate),
    );
  });

  it("should keep the phone's figure when there is no weight", () => {
    expect(burnedFromSteps(10834, null, 875)).toBe(875);
  });

  it('should keep a typed figure on a day with no steps', () => {
    expect(burnedFromSteps(null, rate, 200)).toBe(200);
    expect(burnedFromSteps(0, rate, null)).toBeNull();
  });
});
