import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// One macro: label, figure, and a bar. docs/05 §6 again — the bar keeps one colour whether the
/// value is under or over target, and it clamps rather than overflowing its track.
///
/// `target` null means no plan: the track is drawn unfilled and the figure shows the amount with
/// no comparison. The screen says "No plan yet" and offers to make one, which is what stops an
/// unfilled bar reading as failure.
class MacroBar extends StatelessWidget {
  const MacroBar({
    required this.label,
    required this.value,
    super.key,
    this.target,
    this.unit = 'g',
    this.delay = Duration.zero,
    this.color,
  });

  final String label;
  final double value;
  final double? target;
  final String unit;

  /// The macro's own colour — `AppColors.macroProtein` and friends, the same three the rings on
  /// Home use. Null keeps the brand green, which is right for a bar that is not one of the three.
  final Color? color;

  /// Staggers a row of bars. Kept small — the guidance is 30–50 ms per item, and anything longer
  /// turns a summary into a performance.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = color ?? (isDark ? AppColors.accentBright : theme.colorScheme.primary);
    final animate = AppMotion.enabled(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wraps rather than clipping at large text sizes (rule 12).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.sm,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                target == null
                    ? '${value.round()} $unit'
                    : '${value.round()} / ${target!.round()} $unit',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fill,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TweenAnimationBuilder<double>(
            duration: animate ? AppMotion.normal + delay : Duration.zero,
            curve: AppMotion.enter,
            tween: Tween(
              begin: 0,
              end: target == null || target == 0 ? 0.0 : (value / target!).clamp(0.0, 1.0),
            ),
            builder: (context, filled, _) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: filled,
                minHeight: AppSizes.barHeight,
                color: fill,
                backgroundColor: fill.withValues(alpha: isDark ? 0.2 : 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small figure with a caption, used either side of the calorie gauge.
class GaugeSideStat extends StatelessWidget {
  const GaugeSideStat({required this.value, required this.label, required this.icon, super.key});

  /// Null renders as an em dash. There is no placeholder zero — a fabricated number is worse than
  /// a visible gap (D-43).
  final int? value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSpacing.lg, color: theme.colorScheme.onSurfaceVariant),
        Text(
          value == null ? '—' : '$value',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
