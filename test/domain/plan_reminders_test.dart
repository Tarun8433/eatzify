import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';

/// D-222. When the phone reminds, worked out without the phone.
void main() {
  // A Wednesday morning, on the phone's clock.
  final now = DateTime(2026, 9, 16, 6);
  // The server's end of today's diary day: 04:00 tomorrow.
  final dayEnd = DateTime(2026, 9, 17, 4);

  const routine = ReminderRoutine(
    wake: 7 * 60,
    sleep: 23 * 60,
    meals: {'breakfast': 8 * 60, 'lunch': 13 * 60 + 30, 'dinner': 20 * 60},
  );

  List<PlannedReminder> plan(
    ReminderSettings settings, {
    ReminderRoutine routine = routine,
    DateTime? at,
    ReminderDay? today,
  }) => PlanReminders.plan(settings: settings, routine: routine, now: at ?? now, today: today);

  List<DateTime> on(List<PlannedReminder> plan, DateTime date) => [
    for (final r in plan)
      if (r.at.year == date.year && r.at.month == date.month && r.at.day == date.day) r.at,
  ];

  String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  group('water', () {
    test('should remind every interval between waking and sleep, not at either end', () {
      final today = on(plan(const ReminderSettings(water: true)), now);

      expect(today.map(hhmm), ['09:00', '11:00', '13:00', '15:00', '17:00', '19:00', '21:00']);
    });

    test('should follow the chosen interval', () {
      final today = on(plan(const ReminderSettings(water: true, waterEveryMinutes: 180)), now);

      expect(today.map(hhmm), ['10:00', '13:00', '16:00', '19:00', '22:00']);
    });

    test('should use 08:00 to 22:00 when the profile has no times', () {
      final today = on(
        plan(const ReminderSettings(water: true), routine: const ReminderRoutine()),
        now,
      );

      expect(today.map(hhmm).first, '10:00');
      expect(today.map(hhmm).last, '20:00');
    });

    test('should carry a day that ends after midnight into the next date', () {
      final late = plan(
        const ReminderSettings(water: true, waterEveryMinutes: 180),
        routine: const ReminderRoutine(wake: 10 * 60, sleep: 2 * 60),
      );

      expect(on(late, DateTime(2026, 9, 17)).map(hhmm).take(2), ['01:00', '13:00']);
    });

    test('should skip what has already gone by today', () {
      final afternoon = plan(const ReminderSettings(water: true), at: DateTime(2026, 9, 16, 14));

      expect(on(afternoon, now).map(hhmm), ['15:00', '17:00', '19:00', '21:00']);
    });

    test('should stop for today once the target is met, and start again tomorrow', () {
      final met = plan(
        const ReminderSettings(water: true),
        today: ReminderDay(end: dayEnd, waterMl: 2600, waterTargetMl: 2500),
      );

      expect(on(met, now), isEmpty);
      expect(on(met, DateTime(2026, 9, 17)), hasLength(7));
    });

    test('should keep going when the person asked not to stop', () {
      final met = plan(
        const ReminderSettings(water: true, stopWhenMet: false),
        today: ReminderDay(end: dayEnd, waterMl: 2600, waterTargetMl: 2500),
      );

      expect(on(met, now), hasLength(7));
    });

    test('should not stop on a target nobody set', () {
      final noPlan = plan(
        const ReminderSettings(water: true),
        today: ReminderDay(end: dayEnd, waterMl: 2600),
      );

      expect(on(noPlan, now), hasLength(7));
    });

    test('should ignore a day the server has already closed', () {
      final stale = plan(
        const ReminderSettings(water: true),
        today: ReminderDay(end: DateTime(2026, 9, 16, 4), waterMl: 3000, waterTargetMl: 2500),
      );

      expect(on(stale, now), hasLength(7));
    });
  });

  group('meals', () {
    test('should remind half an hour after each meal the profile has a time for', () {
      final meals = plan(
        const ReminderSettings(meals: true),
        routine: const ReminderRoutine(meals: {'breakfast': 8 * 60, 'dinner': 20 * 60}),
      );

      expect(on(meals, now).map(hhmm), ['08:30', '20:30']);
      expect(meals.every((r) => r.kind == ReminderKind.meal), isTrue);
    });

    test('should skip a meal already logged today', () {
      final meals = plan(
        const ReminderSettings(meals: true),
        today: ReminderDay(end: dayEnd, mealsLogged: const {'breakfast', 'snack'}),
      );

      expect(on(meals, now).map(hhmm), ['14:00', '20:30']);
      expect(on(meals, DateTime(2026, 9, 17)), hasLength(3));
    });
  });

  group('end of day', () {
    test('should remind an hour before bed', () {
      expect(on(plan(const ReminderSettings(dayEnd: true)), now).map(hhmm), ['22:00']);
    });

    test('should stay quiet for someone who was just in the app', () {
      final evening = plan(const ReminderSettings(dayEnd: true), at: DateTime(2026, 9, 16, 20, 30));

      expect(on(evening, now), isEmpty);
      expect(on(evening, DateTime(2026, 9, 17)), hasLength(1));
    });
  });

  test('should schedule nothing when everything is off', () {
    expect(plan(const ReminderSettings()), isEmpty);
  });

  test('should cover a week, soonest first, and never pass the platform limit', () {
    final everything = plan(
      const ReminderSettings(water: true, waterEveryMinutes: 60, meals: true, dayEnd: true),
    );

    expect(everything, hasLength(PlanReminders.maxPending));
    final times = everything.map((r) => r.at).toList();
    expect(times, [...times]..sort());
    // Hourly water fills the budget in a few days; the dropped ones are the furthest away.
    expect(times.last.isBefore(now.add(const Duration(days: 4))), isTrue);

    final twoHourly = plan(const ReminderSettings(water: true));
    expect(twoHourly, hasLength(7 * 7));
    expect(on(twoHourly, DateTime(2026, 9, 22)), hasLength(7));
    expect(on(twoHourly, DateTime(2026, 9, 23)), isEmpty);
  });

  group('the state kept on the phone', () {
    test('should read back what it wrote', () {
      final state = ReminderState(
        settings: const ReminderSettings(water: true, waterEveryMinutes: 90, meals: true),
        routine: routine,
        day: ReminderDay(
          end: dayEnd.toUtc(),
          waterMl: 800,
          waterTargetMl: 2500,
          mealsLogged: const {'lunch'},
        ),
      );

      final back = ReminderState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(back.settings.toJson(), state.settings.toJson());
      expect(back.routine!.toJson(), routine.toJson());
      expect(back.day!.toJson(), state.day!.toJson());
    });

    test('should turn an unknown interval into the default rather than a broken schedule', () {
      expect(ReminderSettings.fromJson(const {'water_every': 7}).waterEveryMinutes, 120);
    });

    test('should read profile times and ignore what is not a time', () {
      final fromProfile = ReminderRoutine.fromProfile(
        wake: '06:45',
        sleep: 'late',
        meals: const {'breakfast': '07:30', 'lunch': null},
      );

      expect(fromProfile.wake, 405);
      expect(fromProfile.sleep, isNull);
      expect(fromProfile.meals, {'breakfast': 450});
    });
  });
}
