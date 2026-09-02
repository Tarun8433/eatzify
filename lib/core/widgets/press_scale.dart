import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// Shrinks its child slightly while held (D-100, D-103).
///
/// A tappable thing that does not move under the finger is the difference between an interface
/// that feels made and one that feels rendered. Scale rather than a ripple: the surfaces this
/// wraps have shadows and rounded edges, and a ripple inside one fights its own boundary.
///
/// It scales rather than moving anything around it, so nothing reflows and no sibling shifts —
/// `Transform` paints, it does not lay out.
///
/// Shared by `AppCard` and `ChoiceTile` deliberately. A card and an option that press differently
/// is the kind of drift nobody reports and everybody feels.
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    required this.onTap,
    required this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  /// Enough to feel under a thumb, not enough to look like the card is collapsing.
  static const _pressedScale = 0.975;

  @override
  State<PressScale> createState() => PressScaleState();
}

class PressScaleState extends State<PressScale> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    // The OS "reduce motion" setting is a request, not a preference to override (rule 12).
    final animate = AppMotion.enabled(context);

    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        // Dragging off the card must release it, or a cancelled tap leaves it stuck small.
        onTapCancel: () => _set(false),
        child: AnimatedScale(
          scale: _down && animate ? PressScale._pressedScale : 1,
          // Down fast, back slower: the press should feel immediate and the release unhurried.
          duration: _down ? AppMotion.fast : AppMotion.normal,
          curve: AppMotion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}
