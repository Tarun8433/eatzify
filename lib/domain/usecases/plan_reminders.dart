import 'dart:async';

import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';

/// When the phone should remind, for the next week (D-222). Pure: settings, the person's day and
/// the time in, a list of times out.
///
/// One-time reminders rather than daily repeating ones, because only a one-time reminder can be
/// dropped for today alone — once the water target is met, or a meal is already logged. The list
/// is rebuilt on every open and every log, so it only runs out for someone who has not opened the
/// app for a week, and a week of silence is the right answer to them.
abstract final class PlanReminders {
  /// iOS keeps at most 64 pending; a few spare.
  static const maxPending = 60;
  static const days = 7;

  /// A meal reminder comes this long after the meal's time — after eating, not before.
  static const afterMealMinutes = 30;

  /// The day-end reminder comes this long before bed…
  static const dayEndBeforeSleepMinutes = 60;

  /// …unless the app was open this recently: someone who was just in it has nothing to add.
  static const dayEndQuiet = Duration(hours: 2);

  static List<PlannedReminder> plan({
    required ReminderSettings settings,
    required ReminderRoutine routine,
    required DateTime now,
    ReminderDay? today,
    Map<int, String> workoutWeek = const {},
  }) {
    if (!settings.anyOn) return const [];

    final wake = routine.wakeOrDefault;
    var sleep = routine.sleepOrDefault;
    // Up at 08:00 and asleep at 01:00 is a day that ends after midnight.
    if (sleep <= wake) sleep += Duration.minutesPerDay;

    final all = <PlannedReminder>[
      // From yesterday: a day that ends after midnight still has reminders left in it.
      for (var day = -1; day < days; day++) ...[
        if (settings.water)
          for (
            var minute = wake + settings.waterEveryMinutes;
            minute < sleep;
            minute += settings.waterEveryMinutes
          )
            (kind: ReminderKind.water, at: _at(now, day, minute), meal: null),
        if (settings.meals)
          for (final meal in reminderMeals)
            if (routine.meals[meal] case final time?)
              (kind: ReminderKind.meal, at: _at(now, day, time + afterMealMinutes), meal: meal),
        if (settings.dayEnd)
          (
            kind: ReminderKind.dayEnd,
            at: _at(now, day, sleep - dayEndBeforeSleepMinutes),
            meal: null,
          ),
        // ponytail: the WEEKLY plan only — a one-off change to a single date is not reflected.
        // Resolve per date from the overview's week_days if that ever matters.
        if (settings.workout)
          if (workoutWeek[_at(now, day, 0).weekday] case final routine?)
            (
              kind: ReminderKind.workout,
              at: _at(now, day, settings.workoutAtMinutes),
              meal: routine,
            ),
      ],
    ];

    // What the server said about today, while it is still today.
    final current = today != null && today.end.isAfter(now) ? today : null;

    bool keep(PlannedReminder reminder) {
      if (!reminder.at.isAfter(now)) return false;
      if (reminder.kind == ReminderKind.dayEnd && reminder.at.difference(now) < dayEndQuiet) {
        return false;
      }
      if (current == null || !reminder.at.isBefore(current.end)) return true;
      return switch (reminder.kind) {
        ReminderKind.water => !(settings.stopWhenMet && current.waterMet),
        ReminderKind.meal => !current.mealsLogged.contains(reminder.meal),
        ReminderKind.dayEnd || ReminderKind.workout => true,
      };
    }

    // Soonest first, so the cap drops the furthest days.
    return (all.where(keep).toList()..sort((a, b) => a.at.compareTo(b.at)))
        .take(maxPending)
        .toList();
  }

  /// [minute] past midnight, [day] days from today, on the phone's clock. DateTime carries minutes
  /// past 1440 into the next day.
  static DateTime _at(DateTime now, int day, int minute) =>
      DateTime(now.year, now.month, now.day + day, 0, minute);
}

/// Stores what changed and schedules the week that follows from it (D-222).
///
/// Called on every open, every log, and every settings change. Anything not passed is taken from
/// what was stored, so a background glass can re-plan with nothing but the new water total.
class RefreshReminders {
  RefreshReminders(this.reminders, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ReminderRepository reminders;
  final DateTime Function() _now;

  /// One at a time: a load and a resume arriving together would otherwise interleave a cancel of
  /// one with the schedule of the other.
  Future<void> _last = Future.value();

  Future<void> call({
    ReminderSettings? settings,
    ReminderRoutine? routine,
    ReminderDay? today,
    Map<int, String>? workoutWeek,
  }) {
    final next = _last.then(
      (_) => _refresh(settings: settings, routine: routine, today: today, workoutWeek: workoutWeek),
    );
    // A failed refresh must not stop the next one from running.
    _last = next.catchError((Object _) {});
    return next;
  }

  /// A glass logged away from the app — the widget, or the reminder's own button.
  Future<void> waterLogged(int totalMl) async {
    final day = (await reminders.readState()).day;
    await call(today: day?.withWater(totalMl));
  }

  Future<void> _refresh({
    ReminderSettings? settings,
    ReminderRoutine? routine,
    ReminderDay? today,
    Map<int, String>? workoutWeek,
  }) async {
    final stored = await reminders.readState();
    final state = ReminderState(
      settings: settings ?? stored.settings,
      routine: routine ?? stored.routine,
      day: today ?? stored.day,
      workoutWeek: workoutWeek ?? stored.workoutWeek,
    );
    await reminders.writeState(state);

    if (!state.settings.anyOn || await reminders.permission() != ReminderPermission.granted) {
      return reminders.cancelAll();
    }
    await reminders.replaceAll(
      PlanReminders.plan(
        settings: state.settings,
        routine: state.routine ?? const ReminderRoutine(),
        today: state.day,
        now: _now(),
        workoutWeek: state.workoutWeek,
      ),
    );
  }
}
