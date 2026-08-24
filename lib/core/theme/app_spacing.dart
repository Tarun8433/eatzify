/// 4 pt spacing scale and the three radii. docs/14 §5.
/// A magic number in a widget is a bug — use these.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Minimum touch target. docs/14 §5 and CLAUDE.md rule 12.
  static const minTouchTarget = 48.0;
}

/// Corner radii. docs/14 §5: 12 cards, 24 sheets, 999 pills. Pick and stick.
abstract final class AppRadius {
  static const card = 12.0;
  static const sheet = 24.0;
  static const pill = 999.0;
}
