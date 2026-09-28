import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/presentation/features/account/reminders_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Reminders" (D-222; docs/14 §6 lists it under You). Water, meal logging and the end of the day,
/// all scheduled on the phone.
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  /// Opens the screen, with a controller that lives as long as it does.
  static Future<void>? open() => Get.to<void>(
    () => const RemindersPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(
        () => RemindersController(
          reminders: Get.find<ReminderRepository>(),
          replan: Get.find<RefreshReminders>(),
          profiles: Get.find<ProfileRepository>(),
        ),
      );
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<RemindersController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.remindersTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<RemindersView>() => const LoadingView(),
          Failed<RemindersView>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          Empty<RemindersView>() => EmptyView(title: l.remindersUnsupported),
          Ready<RemindersView>(:final data) => _Body(controller: c, view: data),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.view});

  final RemindersController controller;
  final RemindersView view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final settings = view.settings;
    final routine = view.routine;
    final hours = NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag());

    String at(int minutes) {
      // An hour before a 00:30 bedtime is 23:30, not a negative time.
      final wrapped = minutes % Duration.minutesPerDay;
      return TimeOfDayText.format(context, TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60));
    }

    // Off while the phone will not show them, whatever was chosen: a switch that reads "on" over
    // nothing scheduled is the defect docs/15 recorded.
    final live = !view.blocked;
    void change(ReminderSettings next) => controller.change(next);

    final mealTimes = [
      for (final meal in reminderMeals)
        if (routine.meals[meal] case final time?) at(time),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        HintCard(icon: Icons.notifications_none_outlined, text: l.remindersIntro),
        if (view.blocked) ...[
          const SizedBox(height: AppSpacing.md),
          HintCard(icon: Icons.notifications_off_outlined, text: l.remindersBlocked),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.water_drop_outlined),
                title: Text(l.remindersWater),
                subtitle: Text(
                  l.remindersWaterDetail(
                    l.remindersHours(hours.format(settings.waterEveryMinutes / 60)),
                    at(routine.wakeOrDefault),
                    at(routine.sleepOrDefault),
                  ),
                ),
                value: live && settings.water,
                onChanged: (on) => change(settings.copyWith(water: on)),
              ),
              if (live && settings.water) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(l.remindersEvery, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                // Chips, not a segmented bar: they wrap at 200 % text instead of overflowing.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final every in ReminderSettings.waterIntervals)
                      ChoiceChip(
                        label: Text(l.remindersHours(hours.format(every / 60))),
                        selected: settings.waterEveryMinutes == every,
                        onSelected: (_) => change(settings.copyWith(waterEveryMinutes: every)),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.remindersStopWhenMet),
                  value: settings.stopWhenMet,
                  onChanged: (on) => change(settings.copyWith(stopWhenMet: on)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.restaurant_outlined),
            title: Text(l.remindersMeals),
            subtitle: Text(
              mealTimes.isEmpty
                  ? l.remindersMealsNoTimes
                  : l.remindersMealsDetail(mealTimes.join(', ')),
            ),
            value: live && settings.meals && mealTimes.isNotEmpty,
            // Nothing to remind about without a meal time.
            onChanged: mealTimes.isEmpty ? null : (on) => change(settings.copyWith(meals: on)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.bedtime_outlined),
            title: Text(l.remindersDayEnd),
            subtitle: Text(
              l.remindersDayEndDetail(
                at(routine.sleepOrDefault - PlanReminders.dayEndBeforeSleepMinutes),
              ),
            ),
            value: live && settings.dayEnd,
            onChanged: (on) => change(settings.copyWith(dayEnd: on)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // ADR-013: a nudge on the days the Gym plan has a workout.
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.fitness_center),
                title: Text(l.gymReminder),
                subtitle: Text(l.gymReminderAt(at(settings.workoutAtMinutes))),
                value: live && settings.workout,
                onChanged: (on) => change(settings.copyWith(workout: on)),
              ),
              if (live && settings.workout)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(at(settings.workoutAtMinutes)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: settings.workoutAtMinutes ~/ 60,
                        minute: settings.workoutAtMinutes % 60,
                      ),
                    );
                    if (picked != null) {
                      change(settings.copyWith(workoutAtMinutes: picked.hour * 60 + picked.minute));
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l.remindersTimesNote, style: muted),
        const SizedBox(height: AppSpacing.sm),
        Text(l.remindersWeekNote, style: muted),
      ],
    );
  }
}

/// A card that switch rows can sit on. The rows draw their ink on the nearest [Material], which
/// would otherwise be the page behind the card's fill.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Material(type: MaterialType.transparency, child: child),
  );
}
