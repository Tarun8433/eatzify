/// Epley's one-rep-max estimate, for the calculator on an exercise (D-244).
///
/// The server uses the same formula for records (`api/src/gym/workout-records.ts`); this copy
/// exists only so the calculator answers as the steppers move, without a round trip per tap. It
/// is arithmetic on the person's own two numbers — nothing about their health goes in.
library;

/// Past this many reps the estimate stops being one.
const oneRmMaxReps = 12;
const _epleyDivisor = 30;

/// w × (1 + r/30), rounded to 0.1. A single rep is the max itself. Null outside 1–12 reps or
/// without a weight.
double? estimateOneRm(double weightKg, int reps) {
  if (reps < 1 || reps > oneRmMaxReps || weightKg <= 0) return null;
  if (reps == 1) return (weightKg * 10).roundToDouble() / 10;
  return (weightKg * (1 + reps / _epleyDivisor) * 10).roundToDouble() / 10;
}
