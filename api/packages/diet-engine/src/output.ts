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
    throw new EngineAssertionError(
      `carb floor breached: ${targets.carbG} < ${pack.macros.carbs.min_g}`,
    );
  }
}

/**
 * docs/04 §8, against the FILLED day: "|Σ meal_kcal − target| ≤ 3 %" and "|Σ protein −
 * protein_target| ≤ 5 g". A failed assertion is a bug, not a warning.
 *
 * [assertMealsCoherent] checks the SPLIT, which is arithmetic and was always right. This checks
 * the food chosen under it, which is a search and can be very wrong while every slot sits inside
 * its energy tolerance.
 *
 * Skipped entirely when no pool was supplied — there is nothing to assert about a plan that
 * deliberately carries no meals.
 *
 * **Also skipped when the fill already said it could not get there.** docs/04 §7 gives the filler
 * an explicit fallback — "fall back to the closest solution and record the residual in the trace"
 * — and a meal that took it comes back `approximated`. Asserting over that turned the documented
 * outcome into a 500: a pool that could not reach one slot's target cost the user their whole
 * plan, with `Internal server error` as the explanation.
 *
 * The assertion keeps its actual job. Its purpose, above, is a search that went wrong WHILE every
 * slot looked fine — and in that case nothing is approximated, so this still throws. The two
 * cases are different failures and only one of them is a bug:
 *
 * - every slot inside tolerance but the day is not — arithmetic contradiction, a bug, throw;
 * - a slot that announced it could not be filled — the pool's limit, recorded, return the plan.
 */
export function assertFilledDayCoherent(
  meals: readonly { kcal: number; proteinG: number; approximated?: boolean }[],
  targets: { kcal: number; proteinG: number },
  pack: RulePack,
): void {
  // The filler has already recorded why, per meal, in `residualKcal`. Re-deciding it here would
  // be a second opinion about a search this function did not run.
  if (meals.some((m) => m.approximated === true)) return;

  const kcal = meals.reduce((acc, m) => acc + m.kcal, 0);
  const drift = Math.abs(kcal - targets.kcal) / targets.kcal;
  if (drift > pack.validation.kcal_tolerance_pct) {
    throw new EngineAssertionError(
      `filled day kcal ${kcal.toFixed(0)} drifts ${(drift * 100).toFixed(1)}% from target ${targets.kcal}`,
    );
  }

  const protein = meals.reduce((acc, m) => acc + m.proteinG, 0);
  const gap = Math.abs(protein - targets.proteinG);
  if (gap > pack.validation.protein_tolerance_g) {
    throw new EngineAssertionError(
      `filled day protein ${protein.toFixed(0)} g is ${gap.toFixed(0)} g from target ${targets.proteinG} g`,
    );
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
