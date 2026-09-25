import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/wheel_picker.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// [WheelPicker] turned on its side: the reference draws the age sheet as a horizontal carousel —
/// a recessed track, the chosen number in a tinted chip with a pointer and a caption under it,
/// and a chevron stepper at each end for picking without a fling.
///
/// The same contract as the wheel: only legal values exist on the track, changes are reported
/// live, and the chip always shows the number Done would commit.
class CarouselPicker extends StatefulWidget {
  const CarouselPicker({
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    super.key,
    this.step = 1,
    this.caption,
  });

  final num min;
  final num max;
  final num step;

  /// Null means nothing chosen yet — the track opens mid-range, same as the wheel.
  final num? value;

  final ValueChanged<num> onChanged;

  /// Read back under the chosen value — "Years old". A unit written as words, where the wheel's
  /// suffix sits beside the number.
  final String? caption;

  /// Cell width and track height at the default text size, both scaled with the text (rule 12).
  static const _itemWidth = 80.0;
  static const _rowHeight = 72.0;

  @override
  State<CarouselPicker> createState() => _CarouselPickerState();
}

class _CarouselPickerState extends State<CarouselPicker> {
  late final FixedExtentScrollController _controller = FixedExtentScrollController(
    initialItem: _indexOf(widget.value ?? _midpoint),
  );

  int get _count => ((widget.max - widget.min) / widget.step).round() + 1;
  num get _midpoint => widget.min + (widget.max - widget.min) / 2;

  num _valueAt(int index) => widget.min + index * widget.step;
  int _indexOf(num value) => ((value - widget.min) / widget.step).round().clamp(0, _count - 1);

  void _stepBy(int delta) {
    final target = (_controller.selectedItem + delta).clamp(0, _count - 1);
    _controller.animateToItem(target, duration: AppMotion.fast, curve: AppMotion.enter);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final selected = widget.value;
    final scaler = MediaQuery.textScalerOf(context);
    final itemWidth = scaler.scale(CarouselPicker._itemWidth);
    final rowHeight = scaler.scale(CarouselPicker._rowHeight);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        // The page's own colour, so the track reads as recessed into the white sheet.
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                StepCircleButton(
                  icon: Icons.chevron_left,
                  label: l.pickerPrev,
                  onTap: () => _stepBy(-1),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The chip the chosen value rides on. Static at the centre, like the
                      // wheel's lane — the physics land the selected item exactly here.
                      Container(
                        width: itemWidth - AppSpacing.xs,
                        height: rowHeight,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                      // A vertical wheel turned a quarter left, its items turned a quarter
                      // right to stand upright again — which keeps the fixed-extent physics,
                      // the haptic notches and the controller instead of reimplementing them
                      // on a horizontal list.
                      RotatedBox(
                        quarterTurns: 3,
                        child: ListWheelScrollView.useDelegate(
                          controller: _controller,
                          itemExtent: itemWidth,
                          // Flatter than the vertical wheel: a row of numbers should read as a
                          // ruler, and visible barrel distortion reads as a broken layout.
                          diameterRatio: 3,
                          perspective: 0.0015,
                          overAndUnderCenterOpacity: 0.65,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: (index) {
                            HapticFeedback.selectionClick();
                            widget.onChanged(_valueAt(index));
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: _count,
                            builder: (context, index) {
                              final value = _valueAt(index);
                              final isSelected = selected != null && _indexOf(selected) == index;

                              return RotatedBox(
                                quarterTurns: 1,
                                child: Center(
                                  child: Text(
                                    WheelPicker.formatValue(value),
                                    style:
                                        (isSelected
                                                ? theme.textTheme.headlineMedium
                                                : theme.textTheme.titleLarge)
                                            ?.copyWith(
                                              color: isSelected
                                                  ? scheme.primary
                                                  : scheme.onSurfaceVariant,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                            ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                StepCircleButton(
                  icon: Icons.chevron_right,
                  label: l.pickerNext,
                  onTap: () => _stepBy(1),
                ),
              ],
            ),
          ),
          // The pointer hanging off the chip, aiming at the caption below it.
          ExcludeSemantics(child: Icon(Icons.arrow_drop_down, color: scheme.primary)),
          if (widget.caption != null)
            Text(
              widget.caption!,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// One chevron stepper: a white circle riding the track, stepping the carousel a single notch —
/// the precise path for a hand that finds flinging a row of numbers fiddly.
class StepCircleButton extends StatelessWidget {
  const StepCircleButton({required this.icon, required this.label, required this.onTap, super.key});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onTap,
      // Icon-only, so it needs a name a screen reader can read out (rule 12).
      tooltip: label,
      icon: Icon(icon, color: scheme.onSurfaceVariant),
      style: IconButton.styleFrom(
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
      ),
    );
  }
}
