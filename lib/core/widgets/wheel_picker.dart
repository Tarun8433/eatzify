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
  static const _itemExtent = 44.0;
  static const _visibleRows = 5;

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

    return SizedBox(
      height: extent * WheelPicker._visibleRows,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The lane the chosen value sits in. Drawn under the wheel so the number rides over it.
          Container(
            height: extent,
            // Narrow inset: at `xxl` each side the lane all but vanished inside a half-width
            // column, which is where this now lives (D-90).
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: extent,
            // Flat enough to read as a list rather than a fairground wheel; enough curve that the
            // neighbours read as "there is more here".
            diameterRatio: 2.2,
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
                            (isSelected
                                    ? theme.textTheme.headlineSmall
                                    : theme.textTheme.titleMedium)
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
        ],
      ),
    );
  }
}
