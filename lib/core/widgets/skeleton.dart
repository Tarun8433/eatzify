import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:shimmer/shimmer.dart';

/// The sweep over a loading skeleton (NFR-8). `shimmer` has been a dependency since the skeletons
/// were specified and was never wired up, so every loading state was a set of flat grey blocks —
/// which reads as a broken layout rather than as one that is filling in (D-162).
///
/// One sweep for the WHOLE screen, not one per block: a page of boxes each shimmering on its own
/// clock is a page of unrelated flickers. Wrap the skeleton once, at its root.
class Skeleton extends StatelessWidget {
  const Skeleton({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The highlight has to be BRIGHTER than the base in both themes, and the two schemes brighten
    // in opposite directions: white is the light page's lift, and the outline is the dark page's.
    final base = scheme.surfaceContainerHighest;
    final highlight = isDark ? scheme.outline : scheme.surface;

    // "Reduce motion" is an accessibility request, not a preference (AppMotion). The skeleton
    // still has to read as loading, so the blocks stay — only the sweep goes.
    if (!AppMotion.enabled(context)) return child;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: _period,
      child: child,
    );
  }

  /// Slower than a UI transition on purpose: a sweep at [AppMotion.normal] reads as a flash, and
  /// this one runs for as long as the network takes.
  static const _period = Duration(milliseconds: 1400);
}

/// One block of a skeleton — the grey stand-in for a card, a line of text, or a disc.
///
/// It paints the base colour itself rather than relying on the shimmer gradient, so a skeleton
/// still looks like a skeleton with the sweep switched off.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = AppSpacing.lg,
    this.radius = AppRadius.card,
  });

  /// A circle — a ring, an icon disc.
  const SkeletonBox.circle({required double size, Key? key})
    : this(width: size, height: size, radius: AppRadius.pill, key: key);

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
