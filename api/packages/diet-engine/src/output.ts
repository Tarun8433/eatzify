import { ENERGY_PER_G } from './macros';
import type { RulePack } from './pack';
import type { MealTarget, Targets } from './types';

/** docs/04 §8 — round ONCE, at the boundary. Everything upstream stays in floating point. */

export const round0 = (n: number): number => Math.round(n);
export const round1 = (n: number): number => Math.round(n * 10) / 10;

export interface RawTargets {
  readonly kcal: number;
  readonly proteinG: number;
  readonly fatG: number;
  readonly carbG: number;
  readonly fibreG: number;
  readonly sodiumMaxMg: number;
  readonly addedSugarMaxG: number;
  readonly saturatedFatMaxG: number;
  readonly waterMl: number;
}

export function roundTargets(raw: RawTargets): Targets {
  return {
    kcal: round0(raw.kcal),
    proteinG: round0(raw.proteinG),
    fatG: round0(raw.fatG),
    carbG: round0(raw.carbG),
    fibreG: round0(raw.fibreG),
    sodiumMaxMg: round0(raw.sodiumMaxMg),
    addedSugarMaxG: round0(raw.addedSugarMaxG),
    saturatedFatMaxG: round0(raw.saturatedFatMaxG),
    waterMl: round0(raw.waterMl),
  };
}

export class EngineAssertionError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = 'EngineAssertionError';
  }
}

/**
 * docs/04 §8 — failing an assertion is a bug, not a warning. Callers in dev let this throw; in
 * production the API catches it, emits `plan_generation_failed` and serves the previous plan.
 */
export function assertTargetsCoherent(targets: Targets, pack: RulePack): void {
  const fromMacros =
    targets.proteinG * ENERGY_PER_G.protein +
    targets.carbG * ENERGY_PER_G.carb +
    targets.fatG * ENERGY_PER_G.fat;
  const drift = Math.abs(fromMacros - targets.kcal) / targets.kcal;
  if (drift > pack.validation.kcal_tolerance_pct) {
    throw new EngineAssertionError(
      `macro energy ${fromMacros.toFixed(0)} drifts ${(drift * 100).toFixed(1)}% from target ${targets.kcal}`,
    );
  }
  if (targets.carbG < pack.macros.carbs.min_g) {
    throw new EngineAssertionError(`carb floor breached: ${targets.carbG} < ${pack.macros.carbs.min_g}`);
  }
}

export function assertMealsCoherent(
  meals: readonly MealTarget[],
  targetKcal: number,
  pack: RulePack,
): void {
  const sum = meals.reduce((acc, m) => acc + m.kcal, 0);
  const drift = Math.abs(sum - targetKcal) / targetKcal;
  if (drift > pack.validation.kcal_tolerance_pct) {
    throw new EngineAssertionError(
      `meal kcal sum ${sum.toFixed(0)} drifts ${(drift * 100).toFixed(1)}% from target ${targetKcal}`,
    );
  }
}
