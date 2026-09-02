import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A number that counts up to its value instead of appearing (D-100).
///
/// The teardown's cheapest win and the truest one: a figure that ticks up reads as something the
/// app worked out, where the same figure printed instantly reads as something it stored. Every
/// headline number on Home, Progress and the plan result is a computed one.
///
/// It animates on ARRIVAL and on CHANGE, so logging a meal rolls the calories up rather than
/// snapping them — which is also the only feedback the number itself gives that the log landed.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    required this.value,
    super.key,
    this.style,
    this.fractionDigits = 0,
    this.prefix = '',
    this.suffix = '',
    this.semanticsLabel,
  });

  final double value;
  final TextStyle? style;

  /// Weight wants one decimal; kcal and steps want none. Formatting stays here so a counting
  /// number and a settled one are never written differently.
  final int fractionDigits;

  final String prefix;
  final String suffix;

  /// What a screen reader hears. Without it the reader announces every intermediate frame.
  final String? semanticsLabel;

  /// Long enough to read as counting, short enough that nobody waits for it. The teardown's 800ms.
  static const _duration = Duration(milliseconds: 800);

  String _format(double v) => '$prefix${v.toStringAsFixed(fractionDigits)}$suffix';

  /// Tabular figures. Without them each digit has its own width, so a counting number jitters
  /// sideways the whole way up and reads as broken rather than alive. It also stops a settled
  /// figure from reflowing its neighbours when 9 becomes 10.
  static const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final settled = _format(value);

    // Reduce motion means the number is simply there (rule 12), and the semantics below mean an
    // assistive reader was never counting anyway.
    final numeric = (style ?? const TextStyle()).merge(_tabular);

    if (!AppMotion.enabled(context)) {
      return Text(settled, style: numeric);
    }

    return Semantics(
      label: semanticsLabel ?? settled,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        // Keyed on the target so a NEW value tweens from the one on screen rather than from zero —
        // logging 200 kcal should nudge the total, not replay the whole count.
        tween: Tween(begin: 0, end: value),
        duration: _duration,
        curve: AppMotion.enter,
        builder: (context, v, _) => Text(_format(v), style: numeric),
      ),
    );
  }
}
