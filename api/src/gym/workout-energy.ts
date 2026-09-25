import type { EnergyBasis, WorkoutEntry } from './gym-types';

/// D-242: the energy a workout burned ABOVE resting, estimated as (MET − 1) × kg × hours.
///
/// A MET is by definition 1 kcal per kg per hour, and 1 MET is sitting still — so MET − 1 is the
/// part the plan's TDEE does not already contain. Every intensity comes from `energy_reference`
/// rows (Compendium codes, admin-editable); this file holds no intensity of its own.
///
/// - Cardio sets are priced by their activity and logged speed, for their logged minutes.
/// - Everything else is priced for the session time that was not cardio, at the average intensity
///   of the sets actually done — capped at `strength_set_cap` minutes per done set, so a workout
///   left open over lunch does not turn into 800 kcal.

export type EnergyRow = {
  activity: string;
  value: number;
  unit: string;
  minSpeedKmh: number | null;
};

export const STRENGTH_ACTIVITY = 'strength';
export const SET_CAP_ACTIVITY = 'strength_set_cap';
const MINUTES_PER_HOUR = 60;
const SECONDS_PER_MINUTE = 60;
/// One MET is rest; the estimate counts only what the workout added to it.
const RESTING_MET = 1;

/// The intensity for an activity at a speed: the highest speed band at or below it, or the lowest
/// band when no speed was logged. An unknown activity is priced as general resistance training.
export function metFor(
  rows: EnergyRow[],
  activity: string,
  speedKmh?: number | null,
): number | null {
  const own = rows.filter((r) => r.activity === activity && r.unit === 'MET');
  const candidates =
    own.length > 0
      ? own
      : rows.filter(
          (r) => r.activity === STRENGTH_ACTIVITY && r.unit === 'MET',
        );
  if (candidates.length === 0) return null;
  const banded = candidates
    .filter((r) => r.minSpeedKmh !== null)
    .sort((a, b) => (a.minSpeedKmh ?? 0) - (b.minSpeedKmh ?? 0));
  if (banded.length === 0) return candidates[0].value;
  const speed = speedKmh ?? 0;
  const band =
    [...banded].reverse().find((r) => (r.minSpeedKmh ?? 0) <= speed) ??
    banded[0];
  return band.value;
}

export type EnergyInput = {
  entries: (WorkoutEntry & { energy_activity: string })[];
  durationSec: number;
  weightKg: number;
  weightSource: EnergyBasis['weight_source'];
  rows: EnergyRow[];
};

export function workoutEnergy(
  input: EnergyInput,
): { kcal: number; basis: EnergyBasis } | null {
  const { entries, weightKg, rows } = input;
  if (!(weightKg > 0)) return null;
  const netKcal = (met: number, minutes: number) =>
    (Math.max(met - RESTING_MET, 0) * weightKg * minutes) / MINUTES_PER_HOUR;

  let kcal = 0;
  let cardioMinutes = 0;
  const strengthNetMets: number[] = [];

  for (const entry of entries) {
    for (const set of entry.sets) {
      if (!set.done) continue;
      if (entry.mode === 'cardio') {
        const met = metFor(rows, entry.energy_activity, set.speed_kmh);
        const minutes = Math.max(set.minutes ?? 0, 0);
        if (met !== null) kcal += netKcal(met, minutes);
        cardioMinutes += minutes;
      } else {
        const met = metFor(rows, entry.energy_activity);
        if (met !== null) strengthNetMets.push(met);
      }
    }
  }

  const cap = rows.find((r) => r.activity === SET_CAP_ACTIVITY)?.value ?? 0;
  const openMinutes = Math.max(
    input.durationSec / SECONDS_PER_MINUTE - cardioMinutes,
    0,
  );
  const strengthMinutes = Math.min(openMinutes, strengthNetMets.length * cap);
  if (strengthNetMets.length > 0) {
    const averageMet =
      strengthNetMets.reduce((a, b) => a + b, 0) / strengthNetMets.length;
    kcal += netKcal(averageMet, strengthMinutes);
  }

  return {
    kcal: Math.round(kcal),
    basis: {
      weight_kg: weightKg,
      weight_source: input.weightSource,
      cardio_minutes: Math.round(cardioMinutes * 10) / 10,
      strength_minutes: Math.round(strengthMinutes * 10) / 10,
    },
  };
}
