import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';

/// One number with its label and optional target — the Calories / Protein / Carbs row.
///
/// docs/05 §6 governs the tone, and it is why there is no colour parameter: a tile cannot be made
/// red for "over" or green for "good". A number is stated, never scored. `value` and `target` are
/// pre-formatted strings because the caller owns units and l10n (CLAUDE.md rule 4).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    super.key,
    this.unit,
    this.target,
    this.icon,
    this.progress,
    this.ring = false,
  });

  final String label;
  final String value;
  final String? unit;

  /// Rendered as secondary text. Null means there is no target — NOT a target of zero, which
  /// would be a fabricated fact (D-43).
  final String? target;
  final IconData? icon;

  /// 0–1, already clamped by the caller. Null hides the indicator entirely.
  final double? progress;

  /// Draw the indicator as a ring beside the text instead of a bar beneath it.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emphasis = isDark ? AppColors.accentBright : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: ring ? _ringLayout(context, emphasis) : _stackLayout(context, emphasis),
    );
  }

  Widget _stackLayout(BuildContext context, Color emphasis) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppSpacing.xl, color: emphasis),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Wraps rather than clipping at 200 % font scale (CLAUDE.md rule 12).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: emphasis,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 2),
                child: Text(unit!, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
        if (target != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            target!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              // Same colour whether under or over target — docs/05 §6.
              color: emphasis,
            ),
          ),
        ],
      ],
    );
  }

  /// Ring on the left, label and numbers on the right — the compact form used in a row of macros.
  Widget _ringLayout(BuildContext context, Color emphasis) {
    final theme = Theme.of(context);

    return Row(
      children: [
        ProgressRing(size: AppSizes.ringSmall, strokeWidth: 5, progress: progress),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                target == null ? '$value${unit ?? ''}' : '$value${unit ?? ''} $target',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: emphasis,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
