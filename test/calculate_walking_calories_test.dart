import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/usecases/calculate_walking_calories.dart';

void main() {
  group('CalculateWalkingCalories', () {
    test('calculates 0 kcal for 0 or negative steps', () {
      expect(CalculateWalkingCalories.calculate(steps: 0), 0);
      expect(CalculateWalkingCalories.calculate(steps: -100), 0);
    });

    test('calculates ~35 kcal per 1,000 steps for default 70 kg, 170 cm', () {
      expect(CalculateWalkingCalories.calculate(steps: 1000), 35);
      expect(CalculateWalkingCalories.calculate(steps: 5000), 177);
      expect(CalculateWalkingCalories.calculate(steps: 10000), 354);
    });

    test('uses ratePer1000Steps when provided', () {
      expect(CalculateWalkingCalories.calculate(steps: 2500, ratePer1000Steps: 40), 100);
      expect(CalculateWalkingCalories.calculate(steps: 5000, ratePer1000Steps: 45), 225);
    });

    test('scales with weight and height', () {
      final heavier = CalculateWalkingCalories.calculate(
        steps: 10000,
        weightKg: 100,
        heightCm: 170,
      );
      final lighter = CalculateWalkingCalories.calculate(steps: 10000, weightKg: 50, heightCm: 170);
      expect(heavier > lighter, isTrue);
      // 100 kg is roughly double 50 kg
      expect((heavier / lighter).round(), 2);
    });
  });
}
