import 'package:flutter/material.dart';
import 'package:health_pro/core/widgets/body_map/body_outlines.dart';
import 'package:path_drawing/path_drawing.dart';

/// A front-and-back body with each muscle shaded by how much work it got (ADR-013).
///
/// [levels] is the server's 0–4 per drawn muscle; 0 is untrained and drawn plain, never red — a
/// muscle not worked this week is information, not a failing (docs/05 §6). The outlines are
/// MuscleMap's (MIT, D-244). Colours come from the theme only (rule 5).
class BodyMap extends StatelessWidget {
  const BodyMap({
    required this.levels,
    required this.semanticsLabel,
    super.key,
    this.female = false,
    this.height = 220,
  });

  final Map<String, int> levels;
  final bool female;
  final double height;

  /// What the picture says, for a screen reader: the muscles it shades, in words.
  final String semanticsLabel;

  /// Shade alpha per level 1…4 on the accent.
  static const _levelAlpha = [0.3, 0.5, 0.75, 1.0];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = (
      silhouette: scheme.outlineVariant.withValues(alpha: 0.45),
      untrained: scheme.surfaceContainerHighest,
      stroke: scheme.outline.withValues(alpha: 0.7),
      shade: [for (final a in _levelAlpha) scheme.secondary.withValues(alpha: a)],
    );
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final outline in female ? [femaleFront, femaleBack] : [maleFront, maleBack])
              Expanded(
                // Size.infinite, not the default: a CustomPaint with no child is laid out at zero
                // height, so the figure had a canvas of nothing to draw on.
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _BodyPainter(outline, levels, palette),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _Palette = ({Color silhouette, Color untrained, Color stroke, List<Color> shade});

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.outline, this.levels, this.palette);

  final BodyOutline outline;
  final Map<String, int> levels;
  final _Palette palette;

  /// Parsed once per figure for the life of the app: ~100 paths each, reused on every repaint.
  static final _parsed = <BodyOutline, ({Map<String, Path> muscles, Path silhouette})>{};

  static ({Map<String, Path> muscles, Path silhouette}) _paths(BodyOutline o) =>
      _parsed.putIfAbsent(o, () {
        Path join(List<String> data) {
          final path = Path();
          for (final d in data) {
            path.addPath(parseSvgPathData(d), Offset.zero);
          }
          return path;
        }

        return (
          muscles: o.muscles.map((k, v) => MapEntry(k, join(v))),
          silhouette: join(o.silhouette),
        );
      });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = [
      size.width / outline.width,
      size.height / outline.height,
    ].reduce((a, b) => a < b ? a : b);
    canvas
      ..save()
      ..translate(
        (size.width - outline.width * scale) / 2 - outline.left * scale,
        (size.height - outline.height * scale) / 2 - outline.top * scale,
      )
      ..scale(scale);

    final paths = _paths(outline);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / scale
      ..color = palette.stroke;
    canvas.drawPath(paths.silhouette, Paint()..color = palette.silhouette);
    paths.muscles.forEach((muscle, path) {
      final level = (levels[muscle] ?? 0).clamp(0, palette.shade.length);
      canvas
        ..drawPath(path, Paint()..color = level == 0 ? palette.untrained : palette.shade[level - 1])
        ..drawPath(path, stroke);
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.outline != outline || old.levels != levels || old.palette != palette;
}
