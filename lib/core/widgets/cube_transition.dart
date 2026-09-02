import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// One face of a rotating cube: the page transition the `walking_animation` prototype used, so a
/// tab change reads as turning to another side of the same object rather than a cut.
///
/// [turn] is where the face is standing, in quarter-turns: 0 faces the viewer, -1 has swung away
/// through the TOP edge, +1 has swung away through the BOTTOM edge. The face hinges on the edge it
/// is leaving through, and fades as it goes — the fade is what keeps the far edge from reading as a
/// hard seam over the page underneath.
///
/// The cube turns vertically (D-69). It turned sideways until then, which put every incoming page
/// on a path in from the bottom of the screen.
class CubeTransition extends StatelessWidget {
  const CubeTransition({required this.turn, required this.child, super.key});

  final double turn;
  final Widget child;

  /// Depth of the perspective. Small enough that a full-screen face does not visibly balloon as it
  /// swings; large enough that the turn is not mistaken for a horizontal squash.
  static const _perspective = 0.003;

  @override
  Widget build(BuildContext context) {
    final t = turn.clamp(-1.0, 1.0);
    final opacity = lerpDouble(1, 0, t.abs())!.clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform(
        // Hinge on the edge the face swings around: leaving upward pivots on the top edge.
        alignment: t <= 0 ? Alignment.topCenter : Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          // Negated so a negative turn tips the far edge AWAY through the top, like a garage door
          // hinged at its top rail, rather than swinging it toward the viewer.
          ..rotateX(-t * math.pi / 2),
        child: child,
      ),
    );
  }
}
