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
import 'package:health_pro/presentation/features/gym/workout_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Home's way into the Gym (D-241): today's routine, or the workout in progress with Resume, behind
/// one pill — the dashboard reference's "Open Gym", where today's routine starts with one tap. Draws nothing where no Gym is registered, so a screen
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
                            Text(
                              l.gymHomeCardTitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
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
                                fontSize: 18,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // One pill, as the reference has it: Resume for a workout in progress — it
                      // must never be stranded — and the way into the Gym otherwise, where today's
                      // routine starts with one tap.
                      FilledButton(
                        onPressed: active != null ? () => WorkoutPage.open(active) : GymPage.open,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, AppSpacing.xxl),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          textStyle: theme.textTheme.labelLarge,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(active != null ? l.gymResume : l.gymOpen)),
                            const Icon(Icons.chevron_right, size: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ],
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
