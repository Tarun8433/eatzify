import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/presentation/features/account/reminders_controller.dart';
import 'package:health_pro/presentation/features/account/reminders_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// D-222. The Reminders screen: the only place the notification question is asked.

const _withTimes = ProfileView(
  ageYears: 29,
  heightCm: 170,
  weightKg: 70,
  sexAtBirth: 'male',
  goal: 'fat_loss',
  activity: 'light',
  foodPreference: 'veg',
  conditions: [],
  allergies: [],
  healthProfileVersion: 1,
  wakeTime: '07:00',
  sleepTime: '23:00',
  breakfastTime: '08:00',
  dinnerTime: '20:00',
);

void main() {
  late FakeReminderRepository reminders;

  setUp(() => reminders = FakeReminderRepository());
  tearDown(Get.reset);

  Widget page({
    Either<Failure, ProfileView?> profile = const Right(_withTimes),
    TextScaler scaler = TextScaler.noScaling,
  }) {
    Get
      ..reset()
      ..put(
        RemindersController(
          reminders: reminders,
          replan: RefreshReminders(reminders),
          profiles: FakeProfileRepository(profileResult: profile),
        ),
      );
    return GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler, alwaysUse24HourFormat: true),
        child: const RemindersPage(),
      ),
    );
  }

  SwitchListTile tile(WidgetTester tester, String title) => tester.widget<SwitchListTile>(
    find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile)),
  );

  group('the four states', () {
    testWidgets('should wait behind a skeleton while it asks the phone', (tester) async {
      reminders.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.byType(Skeleton), findsOneWidget);

      reminders.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should say so on a phone that cannot schedule anything', (tester) async {
      reminders.permitted = ReminderPermission.unsupported;
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text("Reminders aren't available on this device."), findsOneWidget);
    });

    testWidgets('should not guess times when the profile could not be read', (tester) async {
      await tester.pumpWidget(page(profile: const Left(OfflineFailure('You are offline.'))));
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(reminders.scheduled, isNull, reason: 'nothing planned from made-up times');
    });

    testWidgets('should show every reminder off to begin with, at the profile’s times', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(tile(tester, 'Water').value, isFalse);
      expect(tile(tester, 'Logging meals').value, isFalse);
      expect(tile(tester, 'End of the day').value, isFalse);
      expect(find.text('Every 2 h, 07:00 – 23:00'), findsOneWidget);
      expect(find.text('Half an hour after 08:00, 20:00'), findsOneWidget);
      expect(find.text('At 22:00, an hour before bed'), findsOneWidget);
      expect(reminders.prompts, 0, reason: 'opening the screen asks nothing');
    });
  });

  testWidgets('should ask for permission on the first switch, then schedule the week', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.text('Water'));
    await settle(tester);

    expect(reminders.prompts, 1);
    expect(tile(tester, 'Water').value, isTrue);
    expect(reminders.scheduled, isNotEmpty);
    expect(reminders.scheduled!.every((r) => r.kind == ReminderKind.water), isTrue);
    expect(reminders.state.routine!.wake, 7 * 60);

    // The interval only matters once water is on.
    await tester.tap(find.text('3 h'));
    await settle(tester);
    expect(reminders.state.settings.waterEveryMinutes, 180);
  });

  testWidgets('should keep the switch off, and say why, when notifications are refused', (
    tester,
  ) async {
    reminders.afterRequest = ReminderPermission.denied;
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.text('End of the day'));
    await settle(tester);

    expect(tile(tester, 'End of the day').value, isFalse, reason: 'nothing will ring');
    expect(find.textContaining('Notifications are off for Eatzify'), findsOneWidget);
    expect(reminders.scheduled, isEmpty);

    // Turned on in Settings, then back to the app.
    reminders.permitted = ReminderPermission.granted;
    Get.find<RemindersController>().onResumed();
    await settle(tester);

    expect(tile(tester, 'End of the day').value, isTrue);
    expect(find.textContaining('Notifications are off'), findsNothing);
    expect(reminders.scheduled, isNotEmpty);
  });

  testWidgets('should not offer meal reminders without meal times', (tester) async {
    await tester.pumpWidget(page(profile: const Right(defaultProfile)));
    await settle(tester);

    expect(tile(tester, 'Logging meals').onChanged, isNull);
    expect(find.text('Add your meal times under Your day to use this.'), findsOneWidget);
    // No wake or sleep time either: the defaults, said out loud.
    expect(find.text('Every 2 h, 08:00 – 22:00'), findsOneWidget);
  });

  testWidgets('should survive a 200 % text scale with everything open', (tester) async {
    reminders
      ..permitted = ReminderPermission.granted
      ..state = const ReminderState(
        settings: ReminderSettings(water: true, meals: true, dayEnd: true),
      );
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('1.5 h'), findsOneWidget);
  });
}
