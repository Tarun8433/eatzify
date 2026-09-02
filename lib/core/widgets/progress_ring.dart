import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A circular progress arc. Used large for the day's calories and small for each macro.
///
/// docs/05 §6 shapes two decisions here. The arc keeps ONE colour whether the value is under or
/// over target — a ring that turns red at 101 % is a failure marker on a number, which is exactly
/// what the tone rules forbid.
///
/// `progress` null means "no target": the track is drawn but nothing is filled. An unfilled ring
/// on its own would read as "you have achieved nothing", so the caller must say what the state
/// means in words next to it — a caption and a call to action. Removing the ring entirely was
/// worse: it left a hole where the screen's centrepiece belongs and made the app look broken.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.size,
    required this.progress,
    super.key,
    this.strokeWidth = 10,
    this.child,
    this.sweep = 1.0,
    this.color,
    this.trackColor,
  });

  final double size;

  /// 0–1. Values above 1 draw a full ring; null draws only the track.
  final double? progress;
  final double strokeWidth;
  final Widget? child;

  /// Fraction of the circle the ring occupies. 1.0 is a full circle; 0.75 leaves a gap at the
  /// bottom, which is what the large calorie gauge uses.
  final double sweep;

  /// Overrides for a ring on a surface the theme's defaults cannot see. The defaults paint the
  /// brand green — on the Plan header, which IS the brand green, fill and track were both
  /// invisible by construction (D-135). A caller on a dark surface passes its own pair.
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ring = TweenAnimationBuilder<double>(
      // The ring sweeping to its value is the one thing on this screen worth animating — it shows
      // the number arriving rather than just appearing. Reduced motion jumps straight to the end.
      duration: AppMotion.enabled(context) ? AppMotion.normal : Duration.zero,
      curve: AppMotion.enter,
      tween: Tween(begin: 0, end: (progress ?? 0).clamp(0.0, 1.0)),
      builder: (context, value, child) => CustomPaint(
        painter: _RingPainter(
          progress: value,
          strokeWidth: strokeWidth,
          sweep: sweep,
          // A dimmed version of the fill, not a surface colour: the track must read as the
          // unfilled part of the same ring. `surfaceContainerHighest` was 1.00:1 against the
          // emphasised card it sits on — the ring was invisible.
          // Light mode needs a heavier track: the fill is a dark green, so a faint tint of it
          // disappears against a pale card. Measured — 0.32 gave 1.85:1 there, 0.45 gives 2.47:1.
          track:
              trackColor ??
              (isDark ? AppColors.accentBright : theme.colorScheme.primary).withValues(
                alpha: isDark ? 0.32 : 0.45,
              ),
          fill: color ?? (isDark ? AppColors.accentBright : theme.colorScheme.primary),
        ),
        child: child,
      ),
      child: child == null ? null : Center(child: child),
    );

    return SizedBox(width: size, height: size, child: ring);
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.sweep,
    required this.track,
    required this.fill,
  });

  final double progress;
  final double strokeWidth;
  final double sweep;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final total = 2 * math.pi * sweep;
    // Start at the top when the ring is full, otherwise centre the gap at the bottom.
    final start = -math.pi / 2 - (total - 2 * math.pi) / 2 + (1 - sweep) * math.pi;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(inset, start, total, false, trackPaint);

    if (progress <= 0) return;

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(inset, start, total * progress.clamp(0.0, 1.0), false, fillPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.track != track ||
      old.sweep != sweep ||
      old.strokeWidth != strokeWidth;
}

/// The day's calories: a large arc with the number inside.
class CalorieGauge extends StatelessWidget {
  const CalorieGauge({
    required this.consumed,
    required this.label,
    super.key,
    this.target,
    this.caption,
  });

  final int consumed;

  /// Null when no plan exists — the ring shows an empty track and no comparison (D-43).
  final int? target;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // With a target the headline is what is LEFT, which is the number a person acts on. Without
    // one it is what was logged — there is nothing to subtract from (D-43).
    final remaining = target == null ? null : target! - consumed;
    final headline = remaining == null ? consumed : remaining.abs();

    // The ring must grow with the text inside it. Fixed at 200 the inner column overflowed by
    // 136 px at 200 % font scale — CLAUDE.md rule 12. Capped at 1.6x so it cannot swallow the
    // screen on the largest settings.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    return ProgressRing(
      size: AppSizes.gauge * scale,
      strokeWidth: 14,
      sweep: 0.78,
      progress: target == null || target == 0 ? null : consumed / target!,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$headline',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.accentBright : theme.colorScheme.primary,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (caption != null)
              Text(caption!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
