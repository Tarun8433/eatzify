/// Which drawn muscles an exercise works, and how much. The drawable set is MuscleMap's outline set
/// (MIT, D-244) minus its sub-group overlays; the app draws exactly these keys.
///
/// The dataset spells one muscle several ways ('lats', 'latissimus dorsi', 'upper back'), so every
/// spelling folds onto one drawn muscle here — on the server, so the app never maps a string.

export const BODY_MUSCLES = [
  'trapezius',
  'deltoids',
  'chest',
  'upper-back',
  'serratus',
  'biceps',
  'triceps',
  'forearm',
  'abs',
  'obliques',
  'lower-back',
  'gluteal',
  'quadriceps',
  'hamstring',
  'adductors',
  'hip-flexors',
  'calves',
  'tibialis',
] as const;
export type BodyMuscle = (typeof BODY_MUSCLES)[number];

/// A target counts in full; a secondary muscle is a supporting role.
export const PRIMARY_WEIGHT = 1;
export const SECONDARY_WEIGHT = 0.4;

const SPELLINGS: Record<string, BodyMuscle> = {
  abs: 'abs',
  abdominals: 'abs',
  'lower abs': 'abs',
  core: 'abs',
  obliques: 'obliques',
  pectorals: 'chest',
  chest: 'chest',
  'upper chest': 'chest',
  lats: 'upper-back',
  'latissimus dorsi': 'upper-back',
  'upper back': 'upper-back',
  back: 'upper-back',
  rhomboids: 'upper-back',
  spine: 'lower-back',
  'lower back': 'lower-back',
  traps: 'trapezius',
  trapezius: 'trapezius',
  'levator scapulae': 'trapezius',
  sternocleidomastoid: 'trapezius',
  delts: 'deltoids',
  deltoids: 'deltoids',
  shoulders: 'deltoids',
  'rear deltoids': 'deltoids',
  'rotator cuff': 'deltoids',
  biceps: 'biceps',
  brachialis: 'biceps',
  triceps: 'triceps',
  forearms: 'forearm',
  'grip muscles': 'forearm',
  'wrist extensors': 'forearm',
  'wrist flexors': 'forearm',
  wrists: 'forearm',
  glutes: 'gluteal',
  abductors: 'gluteal',
  quads: 'quadriceps',
  quadriceps: 'quadriceps',
  hamstrings: 'hamstring',
  adductors: 'adductors',
  'inner thighs': 'adductors',
  groin: 'adductors',
  'hip flexors': 'hip-flexors',
  calves: 'calves',
  soleus: 'calves',
  shins: 'tibialis',
  'serratus anterior': 'serratus',
};

/// When nothing in an exercise's muscles is drawable (a custom exercise, or "cardiovascular
/// system"), its body part stands in, split the way that body part's work usually splits.
const BODY_PART_SPLIT: Record<string, [BodyMuscle, number][]> = {
  back: [
    ['upper-back', 0.75],
    ['lower-back', 0.25],
  ],
  'upper arms': [
    ['biceps', 0.5],
    ['triceps', 0.5],
  ],
  waist: [
    ['abs', 0.7],
    ['obliques', 0.3],
  ],
  'upper legs': [
    ['quadriceps', 0.4],
    ['hamstring', 0.35],
    ['gluteal', 0.25],
  ],
  'lower legs': [
    ['calves', 0.8],
    ['tibialis', 0.2],
  ],
  chest: [['chest', 1]],
  shoulders: [['deltoids', 1]],
  neck: [['trapezius', 1]],
  'lower arms': [['forearm', 1]],
};

export function muscleFor(spelling: string): BodyMuscle | null {
  return SPELLINGS[spelling.trim().toLowerCase()] ?? null;
}

export type MuscleShare = { muscle: BodyMuscle; weight: number };

/// Each drawn muscle once, at the highest weight any of its spellings earned — a muscle named as
/// both target and secondary is worked as a target, not 1.4 times.
export function musclesOf(e: {
  target: string;
  secondaryMuscles: string[];
  bodyPart: string;
}): MuscleShare[] {
  const weights = new Map<BodyMuscle, number>();
  const credit = (spelling: string, weight: number) => {
    const muscle = muscleFor(spelling);
    if (muscle && weight > (weights.get(muscle) ?? 0))
      weights.set(muscle, weight);
  };
  credit(e.target, PRIMARY_WEIGHT);
  e.secondaryMuscles.forEach((s) => credit(s, SECONDARY_WEIGHT));

  if (weights.size === 0) {
    for (const [muscle, weight] of BODY_PART_SPLIT[e.bodyPart] ?? [])
      weights.set(muscle, weight);
  }
  return [...weights].map(([muscle, weight]) => ({ muscle, weight }));
}
