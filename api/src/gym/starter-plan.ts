import type { RoutineExercise } from './gym-types';

/// A push / pull / legs week for someone starting from nothing. Every weight starts at 0: the first
/// session sets each baseline, and progression takes it from there. Ids are library exercises.

const lift = (
  exercise_id: string,
  sets: number,
  reps: number,
): RoutineExercise => ({
  exercise_id,
  mode: 'reps',
  sets,
  reps,
  weight_kg: 0,
});

export const STARTER_PLAN: {
  name: string;
  icon: string;
  weekday: string;
  exercises: RoutineExercise[];
}[] = [
  {
    name: 'Push Day',
    icon: 'strength',
    weekday: '1',
    exercises: [
      lift('0025', 4, 8), // barbell bench press
      lift('0047', 3, 10), // barbell incline bench press
      lift('0426', 3, 10), // dumbbell standing overhead press
      lift('0334', 3, 12), // dumbbell lateral raise
      lift('0241', 3, 12), // cable triceps pushdown (v-bar)
      lift('0251', 3, 10), // chest dip
    ],
  },
  {
    name: 'Pull Day',
    icon: 'rowing',
    weekday: '3',
    exercises: [
      lift('2330', 4, 10), // cable lat pulldown
      lift('0027', 4, 8), // barbell bent over row
      lift('1323', 3, 10), // cable rope seated row
      lift('0031', 3, 10), // barbell curl
      lift('0313', 3, 12), // dumbbell hammer curl
    ],
  },
  {
    name: 'Leg Day',
    icon: 'gymnastics',
    weekday: '5',
    exercises: [
      lift('0043', 4, 8), // barbell full squat
      lift('0085', 3, 10), // barbell romanian deadlift
      lift('0739', 3, 12), // sled 45° leg press
      lift('0585', 3, 12), // lever leg extension
      lift('0586', 3, 12), // lever lying leg curl
      lift('0605', 4, 15), // lever standing calf raise
    ],
  },
];
