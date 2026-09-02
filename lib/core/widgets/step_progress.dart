import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// One continuous bar that fills as the funnel advances (D-104).
///
/// It was thirteen separate dashes (D-88). At thirteen they are too thin to read as progress and
/// too many to count — the reference uses a single bar with a filled portion, which says the same
/// thing at a glance and gets quieter, not busier, as steps are added.
///
/// Still no "Step 9 of 13": a number to dread is what made the old build feel like paperwork.
class StepProgress extends StatelessWidget {
  const StepProgress({required this.step, required this.total, super.key});

  /// 1-based, so `step == total` is the last screen rather than one past it.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      // The dashes carry no text, so a screen reader gets the count the label used to give.
      label: 'Step $step of $total',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Container(
                height: AppSpacing.xs,
                width: constraints.maxWidth,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.enter,
                height: AppSpacing.xs,
                width: constraints.maxWidth * (step / total).clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child in, [index] places down a list (D-88).
///
/// The reference lands its options one after another rather than all at once, which is what makes
/// a screen of chips feel like it arrived rather than like it was already there. Built on
/// `TweenAnimationBuilder` rather than a package: it is six lines and a curve.
class StaggeredIn extends StatelessWidget {
  const StaggeredIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  /// Gap between neighbours. Small — a long list must not take a second to finish arriving.
  static const _stepDelay = Duration(milliseconds: 40);

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;

    return TweenAnimationBuilder<double>(
      // The key restarts the tween when the step changes, so each screen animates in rather than
      // only the first one the widget was built for.
      key: ValueKey(index),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.normal + _stepDelay * index,
      curve: Interval(
        // Later children start later, and everything finishes together.
        (index * 0.06).clamp(0.0, 0.6),
        1,
        curve: AppMotion.enter,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * AppSpacing.md), child: child),
      ),
      child: child,
    );
  }
}
