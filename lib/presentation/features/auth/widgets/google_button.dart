import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The second way in. White and outlined rather than filled: there is one primary action on this
/// screen and it is "Send code" — two buttons of equal weight is a screen that cannot say what it
/// wants you to do.
///
/// Only drawn when `LoginController.googleEnabled` — see the data source for why.
class GoogleButton extends StatelessWidget {
  const GoogleButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSizes.primaryButton),
        backgroundColor: theme.colorScheme.surface,
        side: BorderSide(color: theme.colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _GoogleMark(size: AppSpacing.xl),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              l.loginGoogle,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google's mark, drawn rather than bundled.
///
/// It is four arcs and a bar, which is less weight than a PNG at three densities and stays sharp at
/// any text scale. Brand colours are hardcoded here and nowhere else — rule 5 is about the app's
/// own palette, and another company's logo is not ours to re-tint for the theme. It is
/// [ExcludeSemantics] because the button's label already says "Continue with Google".
class _GoogleMark extends StatelessWidget {
  const _GoogleMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _GoogleMarkPainter()),
  );
}

class _GoogleMarkPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  /// The ring's stroke, as a fraction of the mark's width — the logo's own proportion.
  static const _strokeFraction = 0.27;

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * _strokeFraction;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Clockwise from the gap on the right, which is where the crossbar comes out.
    const arcs = [
      (20.0, 80.0, _green),
      (100.0, 80.0, _yellow),
      (180.0, 90.0, _red),
      (270.0, 70.0, _blue),
    ];
    for (final (start, sweep, color) in arcs) {
      canvas.drawArc(rect, _rad(start), _rad(sweep), false, paint..color = color);
    }

    // The bar: from the centre out to the right edge, level with the gap.
    canvas.drawRect(
      Rect.fromLTRB(
        size.width / 2,
        (size.height - stroke) / 2,
        size.width,
        (size.height + stroke) / 2,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
