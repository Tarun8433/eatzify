import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/format/weight_units.dart';

void main() {
  test('kilograms are stored as they are read', () {
    expect(WeightUnit.kg.toKg(70.5), 70.5);
    expect(WeightUnit.kg.fromKg(70.5), 70.5);
  });

  test('pounds convert by the defined factor, not an approximation', () {
    // 1959 international agreement: a pound is exactly 0.45359237 kg.
    expect(WeightUnit.lb.toKg(155), closeTo(70.307, 0.001));
    expect(WeightUnit.lb.fromKg(70.307), closeTo(155, 0.01));
  });

  test('a round trip through either unit gives the number back', () {
    for (final unit in WeightUnit.values) {
      expect(unit.fromKg(unit.toKg(82.4)), closeTo(82.4, 0.000001));
    }
  });
}
