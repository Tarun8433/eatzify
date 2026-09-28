import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/usecases/adjust_steps.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/activity_log_tab.dart';

import 'fakes.dart';
import 'pumping.dart';

late FakeMeasurementsRepository measurements;

Widget tabUnderTest({
  TextScaler scaler = TextScaler.noScaling,
  int? steps,
  int? added,
  MeasurementSource source = MeasurementSource.manual,
  Failure? failure,
}) {
  measurements = FakeMeasurementsRepository();
  final day = DiaryDay(
    diaryDate: '2026-09-17',
    entries: const [],
    totals: const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
    steps: steps,
    stepsAdded: added,
    stepsSource: source,
  );
  Get
    ..reset()
    ..put<MeasurementsRepository>(measurements, permanent: true)
    ..put<DiaryRepository>(
      FakeDiaryRepository(dayResult: failure == null ? Right(day) : Left(failure)),
      permanent: true,
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
      data: MediaQueryData(textScaler: scaler),
      child: const Scaffold(body: ActivityLogTab()),
    ),
  );
}

Finder get _save => find.widgetWithText(FilledButton, 'Save activity');

Future<void> _saveNow(WidgetTester tester) async {
  await tester.ensureVisible(_save);
  await tester.pumpAndSettle();
  await tester.tap(_save);
  await settle(tester);
}

void main() {
  /// The bound, the wheel and the caption under the field are the same number. Three copies of
  /// `100000` is how those three drift apart, and a caption promising a range the field rejects is
  /// worse than no caption.
  testWidgets('each field says the range it will actually accept', (tester) async {
    await tester.pumpWidget(tabUnderTest());
    await settle(tester);

    expect(find.text('0 – 100,000 steps'), findsOneWidget);
    expect(find.text('0 – 8,000 kcal'), findsOneWidget);
  });

  testWidgets('a figure outside the range is not a saveable answer', (tester) async {
    await tester.pumpWidget(tabUnderTest());
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, '200000');
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(_save);
    expect(save.onPressed, isNull, reason: '200,000 steps is a typo, not an achievement');
  });

  /// CLAUDE.md rule 12: the layout must survive 200 % font scale. An overflow throws, so the
  /// assertion is that nothing did.
  testWidgets('the cards survive a 200 % text scale', (tester) async {
    await tester.pumpWidget(tabUnderTest(scaler: const TextScaler.linear(2), steps: 1400));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  group('a change to today (D-220)', () {
    testWidgets('should show what today already holds, and where it came from', (tester) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400, source: MeasurementSource.appleHealth));
      await settle(tester);

      expect(find.text('So far today: 1,400 · Apple Health'), findsOneWidget);
      // What can still be added before the day hits the ceiling.
      expect(find.text('0 – 98,600 steps'), findsOneWidget);
    });

    testWidgets('should say so when nothing is logged yet', (tester) async {
      await tester.pumpWidget(tabUnderTest());
      await settle(tester);

      expect(find.text('No steps logged today yet'), findsOneWidget);
    });

    testWidgets('should add what was typed to the count and send it as an addition', (
      tester,
    ) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pumpAndSettle();
      expect(find.text('New total: 1,900'), findsOneWidget);

      await _saveNow(tester);
      // Apart from the device's count (D-221), so a sync cannot wipe it.
      expect(measurements.lastKind, 'steps_added');
      expect(measurements.lastRecorded, 500);
      expect(measurements.lastSource, MeasurementSource.manual);
    });

    testWidgets('should build on what was already added today', (tester) async {
      await tester.pumpWidget(
        tabUnderTest(steps: 956, added: 500, source: MeasurementSource.appleHealth),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '300');
      await tester.pumpAndSettle();
      expect(find.text('New total: 1,256'), findsOneWidget);

      await _saveNow(tester);
      expect(measurements.lastRecorded, 800);
    });

    testWidgets('should show how much of a synced count the person added', (tester) async {
      await tester.pumpWidget(
        tabUnderTest(steps: 956, added: 500, source: MeasurementSource.appleHealth),
      );
      await settle(tester);

      expect(find.text('So far today: 956 — 456 from Apple Health, +500 by you'), findsOneWidget);
    });

    testWidgets('should not save a change of nothing', (tester) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('should open the wheels on a small number, not the middle of the range', (
      tester,
    ) async {
      await tester.pumpWidget(tabUnderTest(steps: 456));
      await settle(tester);

      NumberPickerConfig picker(int at) =>
          tester.widget<NumberField>(find.byType(NumberField).at(at)).picker!;
      expect(picker(0).opensAt, 1000);
      expect(picker(1).opensAt, 200);

      // Removing from 456: 1,000 is past the end, and the wheel only stops on 500s.
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(picker(0).opensAt, 0);
    });

    testWidgets('should take off what was typed when removing', (tester) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400));
      await settle(tester);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Steps to remove'), findsOneWidget);
      expect(find.text('0 – 1,400 steps'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '400');
      await tester.pumpAndSettle();
      expect(find.text('New total: 1,000'), findsOneWidget);

      await _saveNow(tester);
      expect(measurements.lastRecorded, -400);
    });

    testWidgets('should refuse to remove more than the day holds', (tester) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400));
      await settle(tester);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.pumpAndSettle();

      expect(find.text('You can remove at most 1,400 steps.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('should not offer Remove when there is nothing to remove', (tester) async {
      await tester.pumpWidget(tabUnderTest());
      await settle(tester);

      final segments = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
      expect(segments.segments.firstWhere((s) => s.value).enabled, isFalse);
    });

    /// Someone who just connected a watch will wonder whether the next sync undoes this (D-221).
    testWidgets('should say a change to a synced count survives the next sync', (tester) async {
      await tester.pumpWidget(tabUnderTest(steps: 1400, source: MeasurementSource.appleHealth));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pumpAndSettle();
      expect(find.text('Your change stays on top when Apple Health syncs again.'), findsOneWidget);
    });

    testWidgets('should not guess a total when today could not be read', (tester) async {
      await tester.pumpWidget(tabUnderTest(failure: const OfflineFailure('You are offline.')));
      await settle(tester);

      expect(find.text('You are offline.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(find.textContaining('New total'), findsNothing);
    });
  });

  group('AdjustSteps', () {
    test('should add to and remove from the day', () {
      expect(AdjustSteps.total(current: 1400, amount: 500, remove: false), 1900);
      expect(AdjustSteps.total(current: 1400, amount: 400, remove: true), 1000);
      expect(AdjustSteps.total(current: 1400, amount: 1400, remove: true), 0);
    });

    test('should treat nothing recorded as a zero to add to', () {
      expect(AdjustSteps.total(current: null, amount: 800, remove: false), 800);
      expect(AdjustSteps.total(current: null, amount: 1, remove: true), isNull);
    });

    test('should refuse a total outside what the server accepts', () {
      expect(AdjustSteps.total(current: 99000, amount: 1001, remove: false), isNull);
      expect(AdjustSteps.total(current: 99000, amount: 1000, remove: false), AdjustSteps.max);
      expect(AdjustSteps.total(current: 10, amount: 11, remove: true), isNull);
      expect(AdjustSteps.total(current: 10, amount: -5, remove: false), isNull);
    });

    test('should move the day’s addition, into the negative when removing', () {
      expect(AdjustSteps.added(previous: null, amount: 500, remove: false), 500);
      expect(AdjustSteps.added(previous: 500, amount: 300, remove: false), 800);
      expect(AdjustSteps.added(previous: 100, amount: 400, remove: true), -300);
    });

    test('should say how far each way the day can move', () {
      expect(AdjustSteps.limit(current: 1400, remove: false), 98600);
      expect(AdjustSteps.limit(current: 1400, remove: true), 1400);
      expect(AdjustSteps.limit(current: null, remove: true), 0);
    });
  });
}
