import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// Plays a bundled PNG frame sequence: forever, or a fixed number of times before resting on
/// frame 0 (D-55, D-58).
///
/// `AppMotion.enabled` is honoured — with the OS "reduce motion" setting on, frame 0 is shown and
/// nothing ever moves. Frames are precached once so the loop never decodes on the UI thread
/// mid-cycle, which is what keeps a continuous walk from stuttering.
class FrameSequence extends StatefulWidget {
  const FrameSequence({
    required this.frameCount,
    required this.frame,
    required this.cycle,
    required this.cycles,
    super.key,
  });

  final int frameCount;

  /// Asset path for a 0-based frame index.
  final String Function(int index) frame;

  /// Duration of one pass through every frame.
  final Duration cycle;

  /// How many passes to play before resting, or null to walk for as long as the widget is on
  /// screen. A screen showing a null-cycle sequence never settles, so its tests pump a span rather
  /// than calling `pumpAndSettle` (D-58).
  final int? cycles;

  @override
  State<FrameSequence> createState() => _FrameSequenceState();
}

class _FrameSequenceState extends State<FrameSequence> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.cycle,
  );
  var _precached = false;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      for (var i = 0; i < widget.frameCount; i++) {
        precacheImage(AssetImage(widget.frame(i)), context);
      }
    }
    if (!AppMotion.enabled(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_started) {
      _started = true;
      _controller.repeat(count: widget.cycles);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Resting is always frame 0. The controller's value after a finite repeat depends on how
        // far the last tick overshot, so it is not a reliable rest pose. A looping sequence never
        // rests, so this only ever applies to reduced motion and to finite callers.
        final index = _controller.isAnimating
            ? (_controller.value * widget.frameCount).floor() % widget.frameCount
            : 0;
        return Image.asset(
          widget.frame(index),
          gaplessPlayback: true,
          fit: BoxFit.contain,
          // Decorative: the figures beside it carry every number a screen reader needs.
          excludeFromSemantics: true,
        );
      },
    );
  }
}
