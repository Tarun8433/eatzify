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
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/account/health_connect_controller.dart';
import 'package:health_pro/presentation/features/account/health_connect_page.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// D-215. The one screen a health permission sheet may appear on, and Home's offer to reach it.
///
/// These run on the test host, which is not iOS, so the platform name on screen is Health Connect.

final _window = DiaryWindow(
  diaryDate: '2026-09-17',
  start: DateTime.utc(2026, 9, 16, 22, 30),
  end: DateTime.utc(2026, 9, 17, 22, 30),
);

Widget _app(Widget home) => GetMaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  late FakeHealthRepository health;
  late FakeMeasurementsRepository measurements;
  late FakeDiaryRepository diary;

  setUp(() {
    health = FakeHealthRepository();
    measurements = FakeMeasurementsRepository();
    diary = FakeDiaryRepository()..windowsResult = [_window];
  });

  tearDown(Get.reset);

  HealthConnectController controller() => Get.find<HealthConnectController>();

  Widget page() {
    Get
      ..reset()
      ..put(
        HealthConnectController(
          health: health,
          sync: SyncHealth(health: health, measurements: measurements, diary: diary),
        ),
      );
    return _app(const HealthConnectPage());
  }

  group('the four states', () {
    testWidgets('should wait behind a skeleton while it asks the phone', (tester) async {
      health.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);

      health.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should render a failure it is handed', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      controller().state.value = const Failed(OfflineFailure('You are offline.'));
      await tester.pump();
      expect(find.byType(FailedView), findsOneWidget);
    });

    testWidgets('should still say manual entry works when there is nothing to show', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await settle(tester);

      controller().state.value = const Empty();
      await tester.pump();
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.textContaining('enter steps and calories yourself'), findsOneWidget);
    });

    testWidgets('should say exactly what is read, and what is not, in every ready state', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('Walking distance'), findsOneWidget);
      expect(find.text('Calories burned while active'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Sleep, heart rate, weight'), 100);
      expect(find.textContaining('Sleep, heart rate, weight'), findsOneWidget);
    });
  });

  group('not connected', () {
    /// A permission sheet follows a tap, never the screen opening.
    testWidgets('should not prompt just because the screen opened', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(health.prompts, 0);
      expect(find.widgetWithText(FilledButton, 'Connect Health Connect'), findsOneWidget);
    });

    testWidgets('should connect, fill in the last days and say so', (tester) async {
      health.recorded = {
        _window.diaryDate: {HealthMetric.steps: 7000},
      };
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect Health Connect'));
      await settle(tester);

      expect(health.prompts, 1);
      expect(measurements.batches, hasLength(1), reason: 'the backfill ran straight away');
      expect(find.text('Connected to Health Connect'), findsOneWidget);
      expect(find.text('Updated from Health Connect.'), findsOneWidget);
    });

    testWidgets('should stay put, without filling anything, when the user says no', (tester) async {
      health.afterRequest = HealthPermission.denied;
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect Health Connect'));
      await settle(tester);

      expect(measurements.batches, isEmpty);
      expect(find.widgetWithText(FilledButton, 'Connect Health Connect'), findsOneWidget);
      expect(find.textContaining('keep entering steps and calories yourself'), findsOneWidget);
    });
  });

  group('connected', () {
    testWidgets('should say so, and offer to fill in again', (tester) async {
      health.permitted = HealthPermission.granted;
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Connected to Health Connect'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sync from Health Connect'), findsOneWidget);
    });

    testWidgets('should say when there was nothing new', (tester) async {
      health.permitted = HealthPermission.granted;
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sync from Health Connect'));
      await settle(tester);
      expect(find.text('Health Connect has no activity for these days yet.'), findsOneWidget);
    });

    /// D-218. "Could not be read" used to cover a dropped connection too, which sent people to
    /// their health app for a problem that was not there.
    testWidgets('should say which side failed', (tester) async {
      health.permitted = HealthPermission.granted;
      diary.windowsResult = null;
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sync from Health Connect'));
      await settle(tester);
      expect(find.textContaining('Could not reach Eatzify just now'), findsOneWidget);
    });

    /// iOS never reveals what was granted, so the screen names who decides instead of claiming.
    testWidgets('should not claim what an unknowable grant contains', (tester) async {
      health.permitted = HealthPermission.unknown;
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.textContaining('Apple Health decides what Eatzify may read'), findsOneWidget);
    });
  });

  group('no health store', () {
    testWidgets('should offer nothing to connect', (tester) async {
      health.available = HealthAvailability.unsupported;
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.textContaining('no health app Eatzify can read from'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('should send an older Android to install Health Connect', (tester) async {
      health.available = HealthAvailability.needsInstall;
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Get Health Connect'));
      await settle(tester);
      expect(health.installs, 1);
      expect(health.prompts, 0, reason: 'installing is not the same as agreeing');
    });
  });

  testWidgets('should survive 200 % text without overflowing', (tester) async {
    health.permitted = HealthPermission.granted;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: page(),
      ),
    );
    await settle(tester);
    final scale = MediaQuery.textScalerOf(tester.element(find.byType(HealthConnectPage)));
    expect(
      scale.scale(10),
      20,
      reason: 'the scale has to reach the page for this to prove anything',
    );
    expect(tester.takeException(), isNull);
  });

  group('Home', () {
    Widget home({int? steps}) {
      final sync = SyncHealth(health: health, measurements: measurements, diary: diary);
      final day = DiaryDay(
        diaryDate: _window.diaryDate,
        entries: const [],
        totals: const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
        steps: steps,
        windowStart: _window.start,
        windowEnd: _window.end,
      );
      Get
        ..reset()
        ..put<DiaryRepository>(FakeDiaryRepository(dayResult: Right(day)), permanent: true)
        ..put<PlanRepository>(FakePlanRepository(), permanent: true)
        ..put<HealthRepository>(health, permanent: true)
        ..put(sync, permanent: true);
      return _app(const Scaffold(body: HomePage()));
    }

    const offer = 'Connect Health Connect to fill in your steps';
    const syncButton = 'Sync from Health Connect';

    group('the button under the day', () {
      // The one-time sheet is its own group; these start after it has been seen.
      setUp(() => health.offered = true);

      /// D-218: the offer used to hide as soon as any step count existed — so someone who typed a
      /// number never learned the watch could supply it.
      testWidgets('should offer to connect even when steps were typed', (tester) async {
        await tester.pumpWidget(home(steps: 200));
        await settle(tester);

        expect(find.text(offer), findsOneWidget);
        expect(health.prompts, 0, reason: 'an offer, not a prompt');
      });

      testWidgets('should ask for access from the offer, sync, and say so', (tester) async {
        health.recorded = {
          _window.diaryDate: {HealthMetric.steps: 456},
        };
        await tester.pumpWidget(home(steps: 200));
        await settle(tester);

        await tester.tap(find.text(offer));
        await settle(tester);

        expect(health.prompts, 1);
        expect(
          measurements.batches.single.single.replaceManual,
          isTrue,
          reason: 'the tap asked for the watch figure over the typed one',
        );
        expect(find.text('Updated from Health Connect.'), findsOneWidget);
        // There is a figure now, so Sync sits in its row.
        expect(find.byTooltip(syncButton), findsOneWidget);
        expect(find.text(offer), findsNothing);
      });

      /// Sync beside the figure it refreshes, not on a line of its own.
      testWidgets('should put Sync in the steps row when there is a figure', (tester) async {
        health
          ..permitted = HealthPermission.granted
          ..recorded = {
            _window.diaryDate: {HealthMetric.steps: 1400},
          };
        await tester.pumpWidget(home(steps: 1400));
        await settle(tester);

        expect(find.byTooltip(syncButton), findsOneWidget);
        expect(find.text(syncButton), findsNothing, reason: 'not also as a line below');

        await tester.tap(find.byTooltip(syncButton));
        await settle(tester);
        expect(find.text('Updated from Health Connect.'), findsOneWidget);
      });

      testWidgets('should offer a sync once connected', (tester) async {
        health.permitted = HealthPermission.granted;
        await tester.pumpWidget(home());
        await settle(tester);

        expect(find.text(offer), findsNothing);
        await tester.tap(find.text(syncButton));
        await settle(tester);
        expect(find.text('Health Connect has no activity for these days yet.'), findsOneWidget);
      });

      testWidgets('should say when Eatzify could not be reached', (tester) async {
        health.permitted = HealthPermission.granted;
        diary.windowsResult = null;
        await tester.pumpWidget(home());
        await settle(tester);

        await tester.tap(find.text(syncButton));
        await settle(tester);
        expect(find.textContaining('Could not reach Eatzify just now'), findsOneWidget);
        expect(find.text(syncButton), findsOneWidget, reason: 'a failed send is not a disconnect');
      });

      testWidgets('should show nothing on a phone with nothing to connect', (tester) async {
        health.available = HealthAvailability.unsupported;
        await tester.pumpWidget(home());
        await settle(tester);

        expect(find.text(offer), findsNothing);
        expect(find.text(syncButton), findsNothing);
      });
    });

    group('the one-time offer', () {
      const title = 'Fill in your activity automatically';

      testWidgets('should appear by itself the first time, without the system sheet', (
        tester,
      ) async {
        await tester.pumpWidget(home());
        await settle(tester);

        expect(find.text(title), findsOneWidget);
        expect(health.offered, isTrue);
        expect(health.prompts, 0, reason: 'the system sheet only ever follows a tap');
      });

      testWidgets('should go away on "Not now" and leave the button', (tester) async {
        await tester.pumpWidget(home());
        await settle(tester);

        await tester.tap(find.text('Not now'));
        await settle(tester);

        expect(find.text(title), findsNothing);
        expect(health.prompts, 0);
        expect(find.text(offer), findsOneWidget);
      });

      testWidgets('should connect from the sheet', (tester) async {
        await tester.pumpWidget(home());
        await settle(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Connect Health Connect'));
        await settle(tester);

        expect(health.prompts, 1);
        expect(find.text(title), findsNothing);
        expect(find.text(syncButton), findsOneWidget);
      });

      testWidgets('should not appear again once offered', (tester) async {
        health.offered = true;
        await tester.pumpWidget(home());
        await settle(tester);

        expect(find.text(title), findsNothing);
      });

      testWidgets('should not appear once connected', (tester) async {
        health.permitted = HealthPermission.granted;
        await tester.pumpWidget(home());
        await settle(tester);

        expect(find.text(title), findsNothing);
        expect(health.offered, isFalse);
      });
    });
  });
}
