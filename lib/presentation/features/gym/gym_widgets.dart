import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The small shared pieces of the Gym screens. Everything takes its colour from the theme.

/// An icon on the quiet tinted disc the rest of the app uses beside a row.
class GymIconDisc extends StatelessWidget {
  const GymIconDisc({
    required this.icon,
    super.key,
    this.size = AppSizes.choiceDisc + AppSpacing.md,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Icon(icon, color: scheme.onSecondaryContainer, size: size * 0.55),
      ),
    );
  }
}

/// A horizontally scrolling row of single-select chips. Scrolls rather than wraps so 200 % text
/// never pushes the list below it off screen.
class GymChipRow<T> extends StatelessWidget {
  const GymChipRow({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    super.key,
  });

  final List<T> options;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(label(option)),
                selected: option == selected,
                onSelected: (_) => onSelected(option),
              ),
            ),
        ],
      ),
    );
  }
}

/// − value + with 48 dp buttons. Tapping the value opens a field to type it (rule 12: every
/// target is a finger, not a stylus).
class GymStepper extends StatelessWidget {
  const GymStepper({
    required this.label,
    required this.value,
    required this.step,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 999,
    this.decimal = false,
  });

  final String label;
  final double value;
  final double step;
  final double min;
  final double max;
  final bool decimal;
  final ValueChanged<double> onChanged;

  double _clamp(double v) => ((v.clamp(min, max) * 100).roundToDouble()) / 100;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final shown = decimal ? GymLabels.kg(value) : value.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: '−${decimal ? GymLabels.kg(step) : step.round()}',
              onPressed: value <= min ? null : () => onChanged(_clamp(value - step)),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label: l.gymEditValue(label),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () async {
                    final typed = await _typeValue(context, label, value, decimal: decimal);
                    if (typed != null) onChanged(_clamp(typed));
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          shown,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: '+${decimal ? GymLabels.kg(step) : step.round()}',
              onPressed: value >= max ? null : () => onChanged(_clamp(value + step)),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

/// A number typed in a dialog. Accepts "," as a decimal point, the way many keyboards type it.
Future<double?> _typeValue(
  BuildContext context,
  String label,
  double current, {
  required bool decimal,
}) {
  final l = AppLocalizations.of(context);
  final field = TextEditingController(
    text: decimal ? GymLabels.kg(current) : current.round().toString(),
  );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: field,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? '[0-9.,]' : '[0-9]'))],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.gymCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(field.text.replaceAll(',', '.').replaceAll(RegExp('[^0-9.]'), '')),
          ),
          child: Text(l.gymDone),
        ),
      ],
    ),
  );
}

/// One finished workout in a list.
class WorkoutTile extends StatelessWidget {
  const WorkoutTile({required this.workout, required this.onTap, super.key});

  final WorkoutSummary workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kcal = workout.energyKcal;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: const GymIconDisc(icon: Icons.fitness_center),
      title: Text(
        workout.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          l.gymWorkoutMeta(
            GymLabels.day(context, workout.diaryDate),
            (workout.durationSec / Duration.secondsPerMinute).round(),
            workout.setsDone,
          ),
          if (kcal != null) l.gymKcalValue(kcal),
          if (workout.prCount > 0) l.gymRecordCount(workout.prCount),
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// Asks a yes/no question. True only on the confirming button.
Future<bool> confirmGym(
  BuildContext context, {
  required String title,
  required String confirm,
  String? body,
  bool destructive = false,
}) async {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.gymCancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// A section heading inside a card or list.
class GymHeading extends StatelessWidget {
  const GymHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
