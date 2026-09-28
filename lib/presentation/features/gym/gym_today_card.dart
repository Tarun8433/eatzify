import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_page.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_launcher.dart';
import 'package:health_pro/presentation/features/gym/workout_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Home's way into the Gym (D-241): today's routine with a one-tap Start, the workout in progress
/// with Resume, or the way in to plan one. Draws nothing where no Gym is registered, so a screen
/// that is not about training carries none.
class GymTodayCard extends StatelessWidget {
  const GymTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<GymController>()) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = Get.find<GymController>();

    return Obx(() {
      final overview = switch (c.overview.value) {
        Ready<GymOverview>(:final data) => data,
        _ => null,
      };
      final active = c.active.value;
      final routine = overview?.todaysRoutine;
      final rest = overview?.today.source == DaySource.restOverride;
      final subtitle = active != null
          ? l.gymResumeBody(active.name, active.doneSets, active.totalSets)
          : routine != null
          ? l.gymExerciseCount(routine.items.length)
          : null;

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppCard(
          onTap: GymPage.open,
          child: Stack(
            children: [
              // A watermark of the day's icon, not an illustration: it costs no asset, tints itself
              // in dark mode, and never competes with the text on top of it.
              PositionedDirectional(
                end: -AppSpacing.md,
                bottom: -AppSpacing.md,
                child: ExcludeSemantics(
                  child: Icon(
                    routine == null ? Icons.fitness_center : GymLabels.iconFor(routine.icon),
                    size: AppSizes.ringSmall * 1.6,
                    color: theme.colorScheme.primary.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GymIconDisc(
                        icon: routine == null
                            ? Icons.fitness_center
                            : GymLabels.iconFor(routine.icon),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.gymHomeCardTitle, style: theme.textTheme.bodySmall),
                            Text(
                              active?.name ??
                                  routine?.name ??
                                  (overview == null
                                      ? l.gymTitle
                                      : rest
                                      ? l.gymRestDay
                                      : l.gymNothingPlanned),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subtitle != null) Text(subtitle, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      // The way in to the plan, kept quiet beside the action that matters.
                      TextButton(
                        onPressed: GymPage.open,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(l.gymOpen)),
                            const Icon(Icons.chevron_right, size: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // One full-width action: starting is what this card is for.
                  if (active != null)
                    FilledButton.icon(
                      onPressed: () => WorkoutPage.open(active),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.gymResume),
                    )
                  else if (routine != null)
                    FilledButton.icon(
                      onPressed: () => WorkoutLauncher.start(context, routine: routine),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.gymStart),
                    )
                  else if (overview != null)
                    FilledButton.icon(
                      onPressed: () => WorkoutLauncher.start(context, chooseFirst: true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.gymStartWorkout),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
