import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A horizontal ruler you drag past a fixed marker, the way a bathroom scale's dial reads.
///
/// It spans the whole range a reading may legally take — the field above it is the fast path for a
/// number read off a scale in one go, and this is for finding one by eye. Both reach every value;
/// neither is the only way in (rule 12).
///
/// Ticks are BUILT LAZILY, one per slot, because the range is long: 20 to 300 kg at a tenth of a
/// kilogram is 2,800 notches, and painting them all onto one 25,000 pt canvas is a picture no
/// phone should be asked to hold. A viewport's worth — about forty — exists at a time.
class RulerSlider extends StatefulWidget {
  const RulerSlider({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    super.key,
    this.step = 0.1,
    this.majorEvery = 10,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// The range the reading may take. The server's bounds, not a window around the current value:
  /// a ruler that stops five kilograms from where it opened is a ruler that cannot answer the
  /// question the user came with.
  final double min;
  final double max;

  /// One notch.
  final double step;

  /// Every n-th notch is tall and carries its number.
  final int majorEvery;

  final String? semanticLabel;

  @override
  State<RulerSlider> createState() => _RulerSliderState();
}

class _RulerSliderState extends State<RulerSlider> {
  /// Gap between notches. At a tenth per notch this puts a whole kilogram at 70 pt — the spacing
  /// the reference draws, and about five of them across a phone.
  static const _tickGap = 7.0;

  static const _height = 56.0;
  static const _minorTick = 10.0;
  static const _majorTick = 20.0;

  /// How wide a label may draw beyond its own 7 pt slot. Nothing clips it — a ListView does not
  /// clip its children individually — but the box has to be allowed to overflow.
  static const _labelBox = 64.0;

  late final _scroll = ScrollController(initialScrollOffset: _offsetFor(widget.value));

  /// The last value this widget announced, so a scroll that lands back where it started does not
  /// fire a change, and the parent's rebuild does not fight the finger.
  late double _announced = widget.value;

  /// True while the ruler is being moved BY the parent rather than by a finger. A jump fires the
  /// same notifications a drag does, and announcing one of those back to the parent is a setState
  /// during its own build — which is exactly what it looks like: a crash.
  bool _programmatic = false;

  int get _ticks => ((widget.max - widget.min) / widget.step).round() + 1;

  double _offsetFor(double value) =>
      (value.clamp(widget.min, widget.max) - widget.min) / widget.step * _tickGap;

  double _valueFor(double offset) =>
      (widget.min + offset / _tickGap * widget.step).clamp(widget.min, widget.max);

  @override
  void didUpdateWidget(RulerSlider old) {
    super.didUpdateWidget(old);
    // The field was typed into, or the unit changed under it. Jump the ruler to the reading —
    // animating would race the keyboard.
    if ((widget.value - _announced).abs() > widget.step / 2 || widget.min != old.min) {
      _announced = widget.value;
      _jumpTo(widget.value);
    }
  }

  void _jumpTo(double value) {
    if (!_scroll.hasClients) return;
    _programmatic = true;
    _scroll.jumpTo(_offsetFor(value));
    WidgetsBinding.instance.addPostFrameCallback((_) => _programmatic = false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final value = _valueFor(_scroll.offset);
    // Rounded to a notch, and only announced when it actually moved one: a scroll fires far more
    // often than the number changes.
    final snapped = (value / widget.step).round() * widget.step;
    if ((snapped - _announced).abs() < widget.step / 2) return;
    _announced = snapped;
    // The same tick a picker wheel gives. Silent on a phone with haptics off, by the platform's
    // own rule rather than ours.
    unawaited(HapticFeedback.selectionClick());
    widget.onChanged(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: widget.semanticLabel,
      value: _announced.toStringAsFixed(1),
      slider: true,
      // A ruler is a drag, and a drag is not a gesture everyone can make. The field above takes the
      // same number by keyboard, so nothing here is the only way to answer (rule 12).
      excludeSemantics: true,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Half a viewport of padding at each end, so the first and last notches can reach the
            // marker in the middle.
            final half = constraints.maxWidth / 2;

            return Stack(
              alignment: Alignment.topCenter,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // A finger only. Layout and programmatic jumps send these too, and answering
                    // those would have the ruler telling the parent what the parent just said.
                    if (!_programmatic &&
                        (notification is ScrollUpdateNotification ||
                            notification is ScrollEndNotification)) {
                      _onScroll();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: half),
                    itemExtent: _tickGap,
                    itemCount: _ticks,
                    itemBuilder: (context, i) => _Tick(
                      isMajor: i % widget.majorEvery == 0,
                      // Whole units on the majors: a label per tenth is a wall of numbers.
                      label: (widget.min + i * widget.step).toStringAsFixed(0),
                      color: scheme.outline,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                // The marker does not move; the ruler does. That is what makes the number under it
                // the reading rather than one of many.
                IgnorePointer(
                  child: Container(
                    width: AppSpacing.xs,
                    height: AppSpacing.xl,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One notch, and its number if it is a whole unit.
class _Tick extends StatelessWidget {
  const _Tick({
    required this.isMajor,
    required this.label,
    required this.color,
    required this.style,
  });

  final bool isMajor;
  final String label;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 1.5,
        height: isMajor ? _RulerSliderState._majorTick : _RulerSliderState._minorTick,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      if (isMajor) ...[
        const SizedBox(height: AppSpacing.xs),
        // Wider than its slot, and allowed to be: the number belongs to the notch under it, not to
        // the seven points of ruler it happens to sit in.
        SizedBox(
          height: AppSpacing.lg,
          child: OverflowBox(
            maxWidth: _RulerSliderState._labelBox,
            child: Text(label, maxLines: 1, style: style),
          ),
        ),
      ],
    ],
  );
}
