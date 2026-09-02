/// How a weight is SHOWN. What is stored is always kilograms — the server's `weight` kind is
/// bounded in kg and refuses any other unit (docs/09 §4), so pounds are a display choice and never
/// a wire value.
///
/// The conversion lives here rather than in the widget for the reason every constant in this app
/// does: one definition, one test, and no screen quietly rounding differently from another.
enum WeightUnit {
  kg('kg', 1),

  /// The international avoirdupois pound, exactly 0.45359237 kg by definition since 1959.
  lb('lb', 0.45359237);

  const WeightUnit(this.label, this.kgPerUnit);

  /// What the user reads beside the number.
  final String label;

  final double kgPerUnit;

  /// A figure the user typed, in kilograms for the wire.
  double toKg(double shown) => shown * kgPerUnit;

  /// A stored weight, in whatever the user is reading.
  double fromKg(double kg) => kg / kgPerUnit;

  /// The smallest step the unit is entered in: a tenth of a kilogram, and a tenth of a pound.
  /// A bathroom scale reads to one decimal in both, so a finer notch would be false precision.
  double get notch => 0.1;
}
