import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// Three concentric floor rings around the Home walker's feet — protein, carbs and fat, outer to
/// inner (D-55).
///
/// Painted as CIRCLES and then tilted into the floor with a perspective rotateX (D-67), exactly as
/// the walking_animation reference does. Drawing squashed ellipses instead — which is what this did
/// until D-66 — keeps the stroke at full width while the gaps between rings shrink, so at the near
/// and far edges three 13 pt strokes meet across a 7 pt gap and read as one overlapping smear. A
/// rotation compresses strokes and gaps by the same amount, so the spacing holds all the way round.
///
/// One colour per macro (D-61, superseding D-46's single fill): the ring and the goal tile that
/// names it are the same colour, which is what makes three concentric rings readable without
/// counting inwards. The colour is identity, not judgement — it does not change when a macro goes
/// over target, which is the part docs/05 §6 forbids.
///
/// Otherwise as `ProgressRing`: a null progress draws only the track (no target is not a target of
/// zero, D-43), and reduced motion lands on the final value at once.
class MacroRings extends StatelessWidget {
  const MacroRings({required this.progress, required this.size, super.key});

  /// Outer to inner. Each is 0–1 (clamped) or null for "no target".
  final List<double?> progress;

  /// Diameter of the outer ring. Square: these are circles.
  final double size;

  /// Outer to inner, matching [progress] and the goal tiles on the You tab.
  static const fills = <Color>[AppColors.macroProtein, AppColors.macroCarb, AppColors.macroFat];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        duration: AppMotion.enabled(context) ? AppMotion.normal : Duration.zero,
        curve: AppMotion.enter,
        tween: Tween(begin: 0, end: 1),
        builder: (context, sweep, _) => Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, AppSizes.ringPerspective)
            ..rotateX(AppSizes.ringTilt),
          alignment: Alignment.center,
          child: CustomPaint(
            painter: MacroRingPainter(
              progress: [for (final p in progress) p == null ? null : p.clamp(0.0, 1.0) * sweep],
              fills: fills,
              // ONE faint neutral track for all three, as the reference has it — not three dimmed
              // copies of the macro colours (reversing D-48/D-62). Six saturated rings competing is
              // what stopped the group reading as a floor; a single quiet track lets the three
              // filled arcs be the only colour on it.
              track: isDark ? AppColors.darkOutline : AppColors.lightSurfaceAlt,
            ),
          ),
        ),
      ),
    );
  }
}

/// Public so a test can read exactly what was painted.
class MacroRingPainter extends CustomPainter {
  const MacroRingPainter({required this.progress, required this.fills, required this.track});

  final List<double?> progress;

  /// One per ring, outer to inner.
  final List<Color> fills;

  /// The unfilled part of every ring. One colour, not one per macro — see [MacroRings].
  final Color track;

  static const _stroke = AppSizes.ringStroke;
  static const _gap = AppSizes.ringGap;

  /// The circle ring `index` is stroked along, outermost first.
  ///
  /// Inset equally in both axes — unequal insets are what made these ellipses, and an ellipse whose
  /// rings crowd together at the sides while staying apart at the top reads as overlapping (D-66).
  /// Public so a test can assert the spacing rather than re-deriving it.
  static Rect ringRect(Size size, int index) {
    final inset = _stroke / 2 + index * (_stroke + _gap);
    return Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - inset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < progress.length; i++) {
      final trackPaint = Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke;
      final fillPaint = Paint()
        ..color = fills[i % fills.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        // Round on the fill only. A rounded cap on a full-circle track just thickens the seam.
        ..strokeCap = StrokeCap.round;
      final rect = ringRect(size, i);
      canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

      final p = progress[i];
      if (p == null || p <= 0) continue;
      // From the far edge, clockwise — the same start `ProgressRing` uses.
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * p, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(MacroRingPainter old) =>
      !listEquals(old.fills, fills) || old.track != track || !listEquals(old.progress, progress);
}
