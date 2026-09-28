import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "How to", numbered. Shared by the exercise sheet and the workout screen so the two never drift.
class HowToSteps extends StatelessWidget {
  const HowToSteps({required this.steps, super.key, this.description});

  final List<String> steps;

  /// A custom exercise's own words, which stand in for steps.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (description != null && description!.isNotEmpty) {
      return Text(description!, style: theme.textTheme.bodyMedium);
    }
    if (steps.isEmpty) return Text(l.gymNoSteps, style: theme.textTheme.bodySmall);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: AppSpacing.md,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the exercise works and how to do it, under the sets on the workout screen. Everything here
/// travels with the session plan, so it reads the same with no signal.
class ExerciseAbout extends StatelessWidget {
  const ExerciseAbout({required this.entry, super.key});

  final SessionEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = entry.stepsFor(Localizations.localeOf(context).languageCode);
    if (entry.muscles.isEmpty && steps.isEmpty) return const SizedBox.shrink();
    final figure = Get.isRegistered<GymController>()
        ? Get.find<GymController>().ready?.settings.bodyFigure ?? BodyFigure.male
        : BodyFigure.male;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entry.muscles.isNotEmpty) ...[
          GymHeading(l.gymWorks),
          BodyMap(
            female: figure == BodyFigure.female,
            levels: {for (final m in entry.muscles) m.muscle: m.isPrimary ? 4 : 2},
            semanticsLabel: l.gymMuscleMapLabel(
              entry.muscles.map((m) => GymLabels.muscle(l, m.muscle)).join(', '),
            ),
          ),
        ],
        if (steps.isNotEmpty) ...[GymHeading(l.gymHowTo), HowToSteps(steps: steps)],
      ],
    );
  }
}
