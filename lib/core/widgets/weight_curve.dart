import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// The journey from a starting weight to a target, drawn left to right (D-101).
///
/// The teardown's best moment and the cheapest to earn: a curve that DRAWS reads as a projection
/// the app worked out, where the same curve painted instantly reads as a stock illustration. It is
/// the one place in onboarding where the user sees their own numbers turn into something.
///
/// **It projects nothing.** The two endpoints are the weights the user typed, and the shape
/// between them is easing, not a forecast — no rate, no date, no "you will reach this by". Drawing
/// a predicted week-by-week line would be the app making a clinical claim it has no basis for, and
/// CLAUDE.md rule 2 puts that on the server anyway. The label says what they told us, in a shape
/// that reads as downhill.
class WeightCurve extends StatelessWidget {
  const WeightCurve({
    required this.startKg,
    required this.targetKg,
    super.key,
    this.height = AppSizes.chartHeight,
    this.markerAt,
  });

  final double startKg;
  final double targetKg;
  final double height;

  /// Where along the curve to put a solid node, 0-1, or null for none.
  ///
  /// It is an ANCHOR, not a milestone: the caller hangs a note off it, and the note says something
  /// about the target as a whole rather than about that point. The curve projects nothing (see the
  /// class doc), so a dot two thirds along cannot mean "by here you will weigh this".
  final double? markerAt;

  /// Long enough to watch, short enough not to hold anyone up. The teardown's 1200ms.
  static const _draw = Duration(milliseconds: 1200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          // Reduce motion gets the finished curve immediately rather than no curve (rule 12): the
          // shape is the information, only the drawing of it is decoration.
          duration: AppMotion.enabled(context) ? _draw : Duration.zero,
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _CurvePainter(
              progress: t,
              markerAt: markerAt,
              line: scheme.primary,
              fill: scheme.primary.withValues(alpha: 0.12),
              node: scheme.primary,
              onNode: scheme.onPrimary,
              track: scheme.outline,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// A dashed run between two points. Flutter has no dashed stroke, and a `PathMetric` walk is
/// fewer lines than the package that would otherwise arrive to draw four dotted rules.
void _dashedLine(Canvas canvas, Offset from, Offset to, Color color) {
  const dash = 4.0;
  const gap = 4.0;
  final total = (to - from).distance;
  if (total <= 0) return;
  final step = (to - from) / total;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;

  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(from + step * d, from + step * (d + dash).clamp(0, total), paint);
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.progress,
    required this.markerAt,
    required this.line,
    required this.fill,
    required this.node,
    required this.onNode,
    required this.track,
  });

  final double progress;
  final double? markerAt;
  final Color line;
  final Color fill;
  final Color node;
  final Color onNode;
  final Color track;

  /// Where the curve sits inside its box, so the end node and its ring are never clipped.
  static const _inset = AppSpacing.xl;

  @override
  void paint(Canvas canvas, Size size) {
    const left = _inset;
    const top = _inset;
    final right = size.width - _inset;
    final bottom = size.height - _inset;

    // A single ease-out descent: steep at first, flattening towards the target. That is the shape
    // of the thing, not a prediction of the rate — see the class doc.
    final path = Path()..moveTo(left, top);
    const steps = 64;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final eased = Curves.easeInOutCubic.transform(t);
      path.lineTo(left + (right - left) * t, top + (bottom - top) * eased);
    }

    // The full journey, faint: without it the drawn line has nothing to travel along and the
    // animation reads as the chart still loading.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppSizes.barHeight / 4
        ..color = track,
    );

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);

    // The area under the drawn part, which is what gives the line weight on a pale page.
    final area = Path.from(drawn)
      ..lineTo(left + (right - left) * progress, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas
      ..drawPath(area, Paint()..color = fill)
      ..drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppSizes.barHeight / 2
          ..strokeCap = StrokeCap.round
          ..color = line,
      );

    // The floor the journey lands on, dashed so it reads as a reference rather than as a second
    // line of data.
    _dashedLine(canvas, Offset(left, bottom), Offset(right, bottom), track);

    // Where the journey starts. Solid, against the target's open ring: one is a fact already
    // recorded, the other is somewhere nobody has been yet.
    canvas.drawCircle(const Offset(left, top), AppSpacing.sm * 0.75, Paint()..color = line);

    // The anchor the caller's note hangs from, and the leader up to it.
    final marker = markerAt;
    if (marker != null && progress >= marker) {
      final at = metric.getTangentForOffset(metric.length * marker)?.position;
      if (at != null) {
        _dashedLine(canvas, Offset(at.dx, top), at, track);
        canvas.drawCircle(at, AppSpacing.sm * 0.75, Paint()..color = line);
      }
    }

    // The head of the line, so the eye has something to follow.
    final tip = metric.getTangentForOffset(metric.length * progress)?.position;
    if (tip != null) {
      canvas
        ..drawCircle(tip, AppSpacing.sm, Paint()..color = onNode)
        ..drawCircle(
          tip,
          AppSpacing.sm,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = AppSizes.barHeight / 3
            ..color = node,
        );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.progress != progress || old.line != line;
}
