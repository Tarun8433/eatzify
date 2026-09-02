import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

/// Where the walker stands on one tab: a corner of the body, and how tall he is there as a
/// fraction of it. Fractions rather than pixels so he lands in the same place on a 320 pt phone and
/// on a tablet, and so 200 % font scale — which changes the content, not the body — never moves him.
@immutable
class WalkAnchor {
  const WalkAnchor(this.align, this.heightFactor);

  /// The anchor [t] of the way from [a] to [b].
  factory WalkAnchor.lerp(WalkAnchor a, WalkAnchor b, double t) => WalkAnchor(
    Alignment.lerp(a.align, b.align, t)!,
    lerpDouble(a.heightFactor, b.heightFactor, t)!,
  );

  final Alignment align;
  final double heightFactor;
}

/// The walker who travels with you across the shell (D-56).
///
/// The ONLY walker in the app (D-60). Drawn over the pages and deaf to pointers, so he can never
/// take a tap meant for the content he is standing in front of. Home draws the rings he stands on
/// and You draws the frame he stands in, but neither draws him: two instances handed off at a tab
/// boundary meant Home→Plan and Progress→You cross-faded between two figures at different sizes,
/// which is exactly the transition that did not look smooth. One figure cannot be handed off.
///
/// His stride is continuous across a tab change: the sequence is never rebuilt, so he does not
/// restart mid-transition. Reduced motion is handled inside [FrameSequence]: one still frame, and
/// the shell moves him without animating.
class WalkingMan extends StatelessWidget {
  const WalkingMan({
    required this.fromAnchor,
    required this.fromVisible,
    required this.to,
    required this.t,
    super.key,
  });

  /// Where this leg of the walk STARTS, and whether that start was on screen.
  ///
  /// An anchor rather than a tab (D-74) for two reasons. A fractional tab index cannot tell
  /// Home→You apart from Home→Plan→Progress→You — both run 0 to 3, and only one of them should keep
  /// him on screen. And a bare tab cannot express "carry on from where he actually is", which is
  /// what stops a second tap mid-walk from snapping him back to the anchor he had already left.
  final WalkAnchor fromAnchor;
  final bool fromVisible;

  final ClientTab to;
  final double t;

  /// One anchor per [ClientTab], in the same order.
  ///
  /// They are deliberately a tight cluster (D-61). Corner-to-corner anchors made the tab change
  /// read as the walker being flung across the screen; in the reference he holds his ground, at
  /// roughly one size, and the screen moves behind him. The drift that is left is what keeps him
  /// on the hero's rings and inside the profile frame's circle — those two tabs draw a setting he
  /// has to land in. Alignment is -1 left/top to +1 right/bottom.
  static const anchors = <WalkAnchor>[
    // Home: small and high-right, standing on the stage's podium (D-138, shrunk in D-139 — at
    // 0.52 of the body he was a giant who trampled the tiles the moment the page scrolled).
    WalkAnchor(Alignment(0.72, -0.62), 0.28),
    WalkAnchor(Alignment(0.52, -0.32), 0.54), // plan — he is not shown here, see [showsWalker]
    WalkAnchor(Alignment(0.58, -0.32), 0.54), // progress — likewise
    // You — inside the profile frame's oval. Pushed to the top-right corner and shrunk
    // (D-146..D-150): the mock's blob is a compact setting BESIDE the heading, not half the
    // hero — and at 0.85 the oval's rim was clipped by the screen edge.
    WalkAnchor(Alignment(0.72, -0.8), 0.25),
  ];

  /// The tabs he appears on (D-74).
  ///
  /// Home draws the rings he stands on and You the circle he stands in — both are settings built
  /// around him. Plan and Progress are lists; he had nowhere to stand and covered the content, so
  /// he walks off the bottom of those and waits there.
  static bool showsWalker(ClientTab tab) => tab == ClientTab.home || tab == ClientTab.you;

  /// Exactly where he is in a body of [body], part-way through a tab change.
  ///
  /// The build below places him with this and nothing else, so anything that has to line up with
  /// him — the macro rings he stands on, the circle he stands in — can ask rather than guess. Two
  /// widgets each computing a position from the same tokens is how the rings ended up at his waist
  /// (D-63): the numbers agreed and the layouts did not.
  ///
  /// Four cases (D-74), and the asymmetry is deliberate: he leaves through the bottom and returns
  /// through the top, the way someone walking a loop would.
  static Rect boundsIn(
    Size body,
    WalkAnchor fromAnchor,
    ClientTab to,
    double t, {
    required bool fromVisible,
  }) {
    final progress = t.clamp(0.0, 1.0);
    final arriving = showsWalker(to);

    if (fromVisible && arriving) {
      // Home↔You. He crosses the screen directly rather than by way of anchors he is never shown at.
      return _rectFor(body, WalkAnchor.lerp(fromAnchor, anchorFor(to), progress));
    }

    if (fromVisible) {
      // Walking off the bottom, straight down from wherever he was standing.
      final start = _rectFor(body, fromAnchor);
      return start.translate(0, (body.height - start.top) * progress);
    }

    if (arriving) {
      // Walking in from above, down to where he belongs on the arriving tab.
      final end = _rectFor(body, anchorFor(to));
      return end.translate(0, -end.bottom * (1 - progress));
    }

    // Plan→Progress: already off the bottom, and staying there.
    return _rectFor(body, fromAnchor).translate(0, body.height);
  }

  /// Where he stands once a tab has settled — what the rings and the profile frame ask for.
  static Rect boundsAt(Size body, ClientTab tab) =>
      boundsIn(body, anchorFor(tab), tab, 1, fromVisible: showsWalker(tab));

  static WalkAnchor anchorFor(ClientTab tab) => anchors[tab.index];

  static Rect _rectFor(Size body, WalkAnchor anchor) {
    final height = body.height * anchor.heightFactor;
    final width = height * AppSizes.walkerAspect;
    // How Align resolves an alignment, in the one place that resolves it.
    return Rect.fromLTWH(
      (body.width - width) * (1 + anchor.align.x) / 2,
      (body.height - height) * (1 + anchor.align.y) / 2,
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    // No fade, ever. He is always the same figure at the same size — the whole reason a tab change
    // reads as him walking rather than as two pictures swapping.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final body = constraints.biggest;
          final rect = boundsIn(body, fromAnchor, to, t, fromVisible: fromVisible);

          // Off the bottom: nothing is drawn, which is also what stops the stride. `FrameSequence`
          // has no pause, and an invisible figure that keeps ticking is a timer nobody can see.
          if (rect.top >= body.height) return const SizedBox.shrink();

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: const FrameSequence(
                  frameCount: AppAssets.walkFrameCount,
                  frame: AppAssets.walkFrame,
                  cycle: AppMotion.walkCycle,
                  cycles: null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
