import 'dart:math' as math;

/// Calculates calories burned from walking steps based on the ACSM walking equation (D-256).
///
/// Pure orchestration, no I/O and no Flutter.
/// Flat ground ACSM walking equation (matching api walking-energy.ts):
///   speed = 80 m/min (4.8 km/h default pace)
///   stride = 0.414 × height (m) or measured distance / steps
///   minutes = (steps × stride) / speed
///   met = (0.1 × speed + 3.5) / 3.5
///   kcal = (met × 3.5 × weight / 200) × minutes
///
/// For an average adult (70 kg, 170 cm):
///   stride = 0.7038 m
///   kcal per 1,000 steps ≈ 35.4 kcal
abstract final class CalculateWalkingCalories {
  static const double defaultWalkingSpeedMPerMin = 80;
  static const double stridePerHeight = 0.414;
  static const double restingVo2 = 3.5;
  static const double horizontalVo2PerM = 0.1;
  static const int stepsPerRate = 1000;

  static const double defaultWeightKg = 70;
  static const int defaultHeightCm = 170;

  /// Returns gross kcal per 1,000 steps based on ACSM walking equation.
  static double kcalPer1000Steps({double? weightKg, int? heightCm, double? measuredStrideM}) {
    final weight = (weightKg != null && weightKg > 0) ? weightKg : defaultWeightKg;
    final height = (heightCm != null && heightCm > 0) ? heightCm : defaultHeightCm;
    final stride = measuredStrideM ?? ((height / 100.0) * stridePerHeight);

    const speed = defaultWalkingSpeedMPerMin;
    final minutes = (stepsPerRate * stride) / speed;
    const met = (horizontalVo2PerM * speed + restingVo2) / restingVo2;
    final kcal = ((met * restingVo2 * weight) / 200.0) * minutes;
    return kcal;
  }

  /// Calculates estimated calories burned for [steps].
  static int calculate({
    required int steps,
    double? weightKg,
    int? heightCm,
    double? measuredStrideM,
    double? ratePer1000Steps,
  }) {
    if (steps <= 0) return 0;
    final rate = (ratePer1000Steps != null && ratePer1000Steps > 0)
        ? ratePer1000Steps
        : kcalPer1000Steps(
            weightKg: weightKg,
            heightCm: heightCm,
            measuredStrideM: measuredStrideM,
          );
    return math.max(0, (steps * rate / stepsPerRate).round());
  }
}
