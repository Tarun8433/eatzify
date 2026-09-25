import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';

import '../fakes.dart';

/// D-222. What gets stored and scheduled when something changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 16, 6);
  final dayEnd = DateTime(2026, 9, 17, 4);
  const water = ReminderSettings(water: true);
  const routine = ReminderRoutine(wake: 7 * 60, sleep: 23 * 60);

  late FakeReminderRepository repo;
  late RefreshReminders refresh;

  setUp(() {
    repo = FakeReminderRepository(permitted: ReminderPermission.granted);
    refresh = RefreshReminders(repo, now: () => now);
  });

  bool today(PlannedReminder r) => r.at.isBefore(dayEnd);

  test('should schedule the week once something is on and the phone allows it', () async {
    await refresh(settings: water, routine: routine);

    expect(repo.scheduled, hasLength(7 * 7));
    expect(repo.state.settings.water, isTrue);
    expect(repo.state.routine!.wake, 7 * 60);
  });

  test('should cancel everything when all is switched off', () async {
    await refresh(settings: water, routine: routine);
    await refresh(settings: const ReminderSettings());

    expect(repo.scheduled, isEmpty);
    expect(repo.cancels, 1);
  });

  test('should schedule nothing the phone will not show, and still remember the choice', () async {
    repo.permitted = ReminderPermission.denied;

    await refresh(settings: water);

    expect(repo.scheduled, isEmpty);
    expect(repo.state.settings.water, isTrue, reason: 'it starts once notifications are allowed');
    expect(repo.prompts, 0, reason: 'asking belongs to the screen, after a tap');
  });

  test('should keep what it was not told, so a log only has to pass the day', () async {
    await refresh(settings: water, routine: routine);
    await refresh(today: ReminderDay(end: dayEnd, waterMl: 500, waterTargetMl: 2500));

    expect(repo.state.settings.water, isTrue);
    expect(repo.state.routine!.sleep, 23 * 60);
    expect(repo.scheduled!.where(today), hasLength(7));
  });

  test('should drop the rest of today when a glass logged elsewhere meets the target', () async {
    await refresh(
      settings: water,
      routine: routine,
      today: ReminderDay(end: dayEnd, waterMl: 2300, waterTargetMl: 2500),
    );

    await refresh.waterLogged(2500);

    expect(repo.state.day!.waterMl, 2500);
    expect(repo.scheduled!.where(today), isEmpty);
    expect(repo.scheduled, hasLength(6 * 7));
  });

  test('should run one refresh at a time, in the order asked', () async {
    final first = refresh(settings: water, routine: routine);
    final second = refresh(settings: const ReminderSettings());
    await Future.wait([first, second]);

    expect(repo.state.settings.water, isFalse);
    expect(repo.scheduled, isEmpty);
  });

  testWidgets('Home should re-plan from the day it loads', (tester) async {
    // Built inside the test's own clock: one made in setUp chains on a zone this test never runs.
    final repo = FakeReminderRepository(permitted: ReminderPermission.granted);
    final home = HomeController(
      diary: FakeDiaryRepository(
        dayResult: Right(
          DiaryDay(
            diaryDate: '2026-09-16',
            entries: const [],
            totals: const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
            waterLoggedMl: 2600,
            waterTargetMl: 2500,
            windowEnd: dayEnd,
          ),
        ),
      ),
      plans: FakePlanRepository(),
      reminders: RefreshReminders(repo, now: () => now),
    );

    await home.load();
    await tester.pump();

    expect(repo.state.day!.waterMl, 2600);
    expect(repo.state.day!.end, dayEnd);
  });
}
