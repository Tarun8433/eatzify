import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';

/// One macro as Home draws it: a solid disc, the figure over its target, a ring, a percentage.
///
/// Lifted out of `home_page.dart`, where it was private, so the coach's diary can show a client's
/// day in the same shape the client sees it. Two vocabularies for one number is how a coach and a
/// client end up describing the same day differently.
class MacroTile extends StatelessWidget {
  const MacroTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.eaten,
    super.key,
    this.target,
    this.unit = 'g',
  });

  final IconData icon;

  /// The macro's own colour. Identity, never judgement — the same rule the rings follow.
  final Color color;
  final String label;
  final double eaten;

  /// Null when no plan exists. The tile then shows what was eaten and no comparison at all, rather
  /// than a ring against a target of nothing (D-43).
  final double? target;
  final String unit;

  static const _disc = 36.0;
  static const _ring = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goal = target;
    final pct = goal == null || goal == 0 ? null : (eaten / goal * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        // Shadow alone, no border — an outline is the loudest thing in a row of these.
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              height: _disc,
              width: _disc,
              // Solid disc with a white glyph. The tinted version read as a smudge of the colour.
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: AppSpacing.lg, color: AppColors.lightSurface),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              // The figure in ink, not in the macro colour: the disc and the ring carry the
              // identity, the number stays a number.
              goal == null ? '${eaten.round()} $unit' : '${eaten.round()} / ${goal.round()} $unit',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ProgressRing(
            size: _ring,
            strokeWidth: 5,
            progress: goal == null || goal == 0 ? null : eaten / goal,
            color: color,
            trackColor: color.withValues(alpha: 0.18),
          ),
          if (pct != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('$pct%', style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ],
        ],
      ),
    );
  }
}
