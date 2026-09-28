import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/routine_edit_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Routines: the weekly schedule (a routine or rest per weekday) and the routines themselves.
class GymRoutinesTab extends StatelessWidget {
  const GymRoutinesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<GymController>();
    return Obx(
      () => switch (c.overview.value) {
        Loading<GymOverview>() => const LoadingView(lines: 5),
        Empty<GymOverview>() => EmptyView(title: l.gymNoRoutines),
        Failed<GymOverview>(:final failure) => FailedView(
          failure: failure,
          onRetry: c.load,
          retryLabel: l.accountRetry,
        ),
        Ready<GymOverview>(:final data) => _Routines(overview: data, controller: c),
      },
    );
  }
}

class _Routines extends StatelessWidget {
  const _Routines({required this.overview, required this.controller});

  final GymOverview overview;
  final GymController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      children: [
        GymHeading(l.gymWeekSchedule),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          // The rows draw their ink on the nearest Material, which would otherwise be the page
          // behind the card's own fill (the same reason the You tab wraps its rows).
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var weekday = 1; weekday <= DateTime.daysPerWeek; weekday++)
                  ListTile(
                    title: Text(GymLabels.weekdayName(context, weekday)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            overview.routineById(overview.week[weekday])?.name ?? l.gymRest,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      final pick = await pickRoutine(
                        context,
                        title: l.gymEveryDay(GymLabels.weekdayName(context, weekday)),
                        routines: overview.routines,
                        current: overview.week[weekday],
                      );
                      if (pick != null) await c.setWeekday(weekday, pick.routineId);
                    },
                  ),
              ],
            ),
          ),
        ),
        GymHeading(
          l.gymRoutines,
          trailing: TextButton.icon(
            onPressed: RoutineEditPage.open,
            icon: const Icon(Icons.add),
            label: Text(l.gymNewRoutine),
          ),
        ),
        if (overview.routines.isEmpty)
          EmptyView(
            title: l.gymNoRoutines,
            body: l.gymWelcomeBody,
            actionLabel: l.gymLoadStarter,
            onAction: c.loadStarterPlan,
          )
        else
          for (final r in overview.routines)
            Card(
              child: ListTile(
                leading: GymIconDisc(icon: GymLabels.iconFor(r.icon)),
                title: Text(r.name),
                subtitle: Text(
                  '${l.gymExerciseCount(r.items.length)} · ${GymLabels.rule(l, r.progression)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => RoutineEditPage.open(routine: r),
              ),
            ),
      ],
    );
  }
}

/// A routine or rest. Null means the sheet was closed without a choice.
Future<({int? routineId})?> pickRoutine(
  BuildContext context, {
  required String title,
  required List<Routine> routines,
  required int? current,
}) {
  final l = AppLocalizations.of(context);
  return showModalBottomSheet<({int? routineId})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const GymIconDisc(icon: Icons.bedtime_outlined),
            title: Text(l.gymRest),
            trailing: current == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, (routineId: null)),
          ),
          for (final r in routines)
            ListTile(
              leading: GymIconDisc(icon: GymLabels.iconFor(r.icon)),
              title: Text(r.name),
              trailing: current == r.id ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, (routineId: r.id)),
            ),
        ],
      ),
    ),
  );
}

/// One date: a different routine, rest, or back to what the week says. The weekly plan stays.
abstract final class DayPlanSheet {
  static Future<void> show(BuildContext context, PlannedDay day) async {
    final l = AppLocalizations.of(context);
    final c = Get.find<GymController>();
    final routines = c.ready?.routines ?? const <Routine>[];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l.gymPlanFor(
                  '${GymLabels.weekdayName(context, day.weekday)}, ${GymLabels.day(context, day.diaryDate)}',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(l.gymDayNote),
            ),
            for (final r in routines)
              ListTile(
                leading: GymIconDisc(icon: GymLabels.iconFor(r.icon)),
                title: Text(r.name),
                trailing: day.routineId == r.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, '${r.id}'),
              ),
            ListTile(
              leading: const GymIconDisc(icon: Icons.bedtime_outlined),
              title: Text(l.gymDayRest),
              onTap: () => Navigator.pop(context, 'rest'),
            ),
            if (day.isRescheduled)
              ListTile(
                leading: const GymIconDisc(icon: Icons.undo),
                title: Text(l.gymDayBackToWeekly),
                onTap: () => Navigator.pop(context, 'weekly'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await c.setDay(day.diaryDate, rest: choice == 'rest', routineId: int.tryParse(choice));
  }
}
