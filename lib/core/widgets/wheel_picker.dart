import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A number chosen by scrolling, not typing (D-88).
///
/// The reference flow asks "What is your age?" with a wheel: the neighbours fade above and below,
/// the selected value sits boxed in the middle, and no keyboard ever appears. Four number pads in
/// the basics step were four keyboards to raise and dismiss, and a keyboard is the single most
/// interruptive thing a form can do on a phone.
///
/// It cannot produce an invalid value — the wheel only holds legal ones — so there is no rejection
/// to write, no "between 30 and 250" helper to read, and nothing to validate on blur.
class WheelPicker extends StatefulWidget {
  const WheelPicker({
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    super.key,
    this.step = 1,
    this.suffix,
    this.format,
  });

  final num min;
  final num max;

  /// Distance between neighbours. 1 for age and height; 0.5 lets a weight land on 72.5.
  final num step;

  /// Null means nothing chosen yet, and the wheel opens in the middle of the range rather than
  /// pretending the first legal value is an answer.
  final num? value;

  final ValueChanged<num> onChanged;

  /// Rendered small beside the number — "kg", "cm".
  final String? suffix;

  /// How to write a value. Defaults to trimming a whole number's ".0".
  final String Function(num)? format;

  /// Row height at the default text size. Scaled with the text below — a fixed extent means the
  /// numbers overflow their own row at 200 %, which is rule 12's whole point (D-90).
  /// 52, up from 44: the reference draws the chosen value at display size, and it needs the room.
  static const _itemExtent = 52.0;
  static const _visibleRows = 5;

  /// The scroll affordances the reference draws on the lane: a dot pinned to its top edge, an
  /// open ring to its bottom edge — the "handle" that says this row slides — and the ruler ticks
  /// at its trailing edge. All decoration: none of it is announced, none of it takes a tap.
  static const _laneDot = 8.0;
  static const _laneRing = 18.0;
  static const _laneRingStroke = 3.0;
  static const _tickCount = 7;
  static const _tickLong = 16.0;
  static const _tickShort = 10.0;
  static const _tickStroke = 1.5;

  /// How a value is written, here and in the `NumberField` the wheel now fills (D-95). Shared so
  /// the two cannot disagree — a wheel reading 70.5 above a field reading 70.50 is one value
  /// looking like two.
  static String formatValue(num value) => value % 1 == 0 ? '${value.toInt()}' : '$value';

  @override
  State<WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<WheelPicker> {
  late final FixedExtentScrollController _controller = FixedExtentScrollController(
    initialItem: _indexOf(widget.value ?? _midpoint),
  );

  int get _count => ((widget.max - widget.min) / widget.step).round() + 1;
  num get _midpoint => widget.min + (widget.max - widget.min) / 2;

  num _valueAt(int index) => widget.min + index * widget.step;
  int _indexOf(num value) => ((value - widget.min) / widget.step).round().clamp(0, _count - 1);

  String _label(num value) => widget.format?.call(value) ?? WheelPicker.formatValue(value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.value;
    final extent = MediaQuery.textScalerOf(context).scale(WheelPicker._itemExtent);

    final scheme = theme.colorScheme;
    // Where the lane's edges sit inside the five-row stack: rows 0-1 above it, 2 is it.
    final laneTop = extent * (WheelPicker._visibleRows ~/ 2);
    final laneBottom = laneTop + extent;

    return SizedBox(
      height: extent * WheelPicker._visibleRows,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The reference's vertical guide, running the wheel's full height behind the lane.
          ExcludeSemantics(
            child: Container(width: 1, color: scheme.outline.withValues(alpha: 0.4)),
          ),
          // The lane the chosen value sits in. Drawn under the wheel so the number rides over it.
          Container(
            height: extent,
            // Narrow inset: at `xxl` each side the lane all but vanished inside a half-width
            // column, which is where this now lives (D-90).
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              // The brand tint, not `surfaceContainerHighest`: the beige read as a warning strip
              // next to the green sheet, and the reference draws the lane in the green wash.
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            // The ruler ticks at the lane's trailing edge — the measuring-tape motif.
            child: Align(
              alignment: Alignment.centerRight,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < WheelPicker._tickCount; i++)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xs),
                          child: Container(
                            height: WheelPicker._tickStroke,
                            width: i == WheelPicker._tickCount ~/ 2
                                ? WheelPicker._tickLong
                                : WheelPicker._tickShort,
                            color: i == WheelPicker._tickCount ~/ 2
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: extent,
            // Flat enough to read as a list rather than a fairground wheel; enough curve that the
            // neighbours read as "there is more here".
            diameterRatio: 2.2,
            // The reference fades the neighbours towards the edges; the colour below separates
            // chosen from not, this separates near from far.
            overAndUnderCenterOpacity: 0.65,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              // The click a physical dial would make. Without it the wheel feels like it is
              // sliding past numbers rather than stopping on them.
              HapticFeedback.selectionClick();
              widget.onChanged(_valueAt(index));
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _count,
              builder: (context, index) {
                final value = _valueAt(index);
                final isSelected = selected != null && _indexOf(selected) == index;

                return Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textBaseline: TextBaseline.alphabetic,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    children: [
                      Text(
                        _label(value),
                        style:
                            // Display size: the chosen number is the sheet's whole answer, and
                            // the reference draws it at several times its neighbours. Inside the
                            // row at every text scale, because the extent scales with the text
                            // (D-90).
                            (isSelected ? theme.textTheme.displaySmall : theme.textTheme.titleLarge)
                                ?.copyWith(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                ),
                      ),
                      if (widget.suffix != null && isSelected) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(widget.suffix!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          // The dot on the lane's top edge and the open-ring handle on its bottom edge — the
          // reference's way of saying the lane is a slider thumb. Over the wheel, so they sit on
          // the numbers' surface; ignoring pointers, so the wheel still takes every drag.
          Positioned(
            top: laneTop - WheelPicker._laneDot / 2,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  height: WheelPicker._laneDot,
                  width: WheelPicker._laneDot,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
          Positioned(
            top: laneBottom - WheelPicker._laneRing / 2,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  height: WheelPicker._laneRing,
                  width: WheelPicker._laneRing,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: WheelPicker._laneRingStroke),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
