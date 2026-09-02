/// Legal values for the onboarding fields added after the first release. docs/03 §2 is still the
/// governing list for the original contract; everything here extends it and must be added there
/// when the doc is next revised.
///
/// Kept in one file so the DTO, the entity columns and the Swagger examples cannot drift apart.

/// docs/03 §2 plus the four the product asked for. NONE of the new four gates a plan — docs/05 §3
/// decides that, and a clinical classification for cholesterol / fatty liver / heart / digestive
/// is not ours to invent. They are stored as declared conditions and are visible to a coach.
export const CONDITIONS = [
  'none',
  'type2_diabetes',
  'prediabetes',
  'hypertension',
  'hypothyroid',
  'hyperthyroid',
  'pcos',
  'post_surgery',
  'ckd',
  'pregnancy',
  'lactation',
  'high_cholesterol',
  'fatty_liver',
  'heart_problem',
  'digestive_issue',
  'other_declared',
] as const;

/// docs/03 §2. Food allergies only — never environmental. FR-1.6.
export const ALLERGIES = [
  'milk',
  'wheat_gluten',
  'soy',
  'peanut',
  'tree_nut',
  'egg',
  'fish',
  'shellfish',
  'sesame',
  'mustard',
  'other',
] as const;

/// What the user picked from the goal list, verbatim. The engine's `goal` (fat_loss | muscle_gain |
/// maintenance) stays the only thing that drives calorie direction — docs/04's rule pack has no
/// semantics for "general fitness", and inventing a target here would be the client computing a
/// target (CLAUDE.md rule 2). This field exists so the coach and a later rule pack can tell the
/// difference between someone chasing a number and someone who wants to feel better.
export const GOAL_DECLARED = [
  'weight_loss',
  'weight_gain',
  'fat_loss',
  'muscle_gain',
  'general_fitness',
  'medical_support',
  'other',
] as const;

/// Digestive symptoms. Distinct from the `digestive_issue` condition: that is a diagnosis, these
/// are symptoms the user reports without one.
export const DIGESTIVE_SYMPTOMS = [
  'none',
  'gas',
  'acidity',
  'bloating',
  'constipation',
  'loose_motion',
  'ibs',
] as const;

/// Musculoskeletal limits. They do not change a diet plan, but an activity recommendation that
/// ignores a knee injury is worse than no recommendation.
export const INJURY_AREAS = [
  'none',
  'back_pain',
  'knee_pain',
  'joint_pain',
  'other_injury',
] as const;

/// FR-1.3 keeps these behind `sex_at_birth === 'female'`. Asking a man about periods is a health
/// field with no clinical purpose, which docs/13 forbids collecting.
export const MENSTRUAL_REGULARITY = [
  'regular',
  'irregular',
  'not_applicable',
] as const;

/// `none` clears every other selection in the same set. Applied server-side as well as in the app
/// so a hand-rolled request cannot store "none plus diabetes".
export function applyNoneExclusivity<T extends string>(
  values: T[],
  noneValue: T,
): T[] {
  if (values.includes(noneValue)) return [noneValue];
  return [...new Set(values)];
}
