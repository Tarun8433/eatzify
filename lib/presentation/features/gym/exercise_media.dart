import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// The exercise animation, where one is served (D-243: media is licensed separately and reaches the
/// app only when `GYM_MEDIA_BASE_URL` is set). Every screen keeps working without it: with no URL
/// this draws nothing at all, and a URL that fails to load is treated the same way rather than
/// leaving a broken frame behind.
///
/// The source art is 180 × 180, so it is drawn at [maxSide] rather than stretched across the screen.
class ExerciseMedia extends StatelessWidget {
  const ExerciseMedia({
    required this.url,
    super.key,
    this.thumbUrl,
    this.maxSide = 220,
    this.semanticsLabel,
  });

  final String? url;

  /// The still frame. Shown while the animation loads, and on its own in a list row.
  final String? thumbUrl;
  final double maxSide;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final src = url ?? thumbUrl;
    if (src == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    // A fixed square: this also sits in a ListTile's leading slot, which refuses a greedy child.
    return SizedBox(
      width: maxSide,
      height: maxSide,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Image.network(
          src,
          fit: BoxFit.contain,
          semanticLabel: semanticsLabel,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : ColoredBox(color: scheme.surfaceContainerHighest, child: child),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
