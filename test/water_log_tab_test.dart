import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/water_log_tab.dart';

import 'fakes.dart';
import 'pumping.dart';

late FakeMeasurementsRepository measurements;

/// Home owns the day, and the water tab reads its running total from there — so the day has to be
/// on screen before the tab can show anything.
Widget waterUnderTest(DiaryDay day) {
  measurements = FakeMeasurementsRepository();
  final diary = FakeDiaryRepository(dayResult: Right(day));
  Get
    ..reset()
    ..put<MeasurementsRepository>(measurements, permanent: true)
    ..put<DiaryRepository>(diary, permanent: true)
    ..put<PlanRepository>(FakePlanRepository(), permanent: true)
    ..put(HomeController(diary: diary, plans: FakePlanRepository()), permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: WaterLogTab()),
  );
}

const dayWithGoal = DiaryDay(
  diaryDate: '2026-09-01',
  entries: [],
  totals: Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
  targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
  waterLoggedMl: 0,
  waterTargetMl: 2310,
);

void main() {
  testWidgets("the goal on screen is the engine's, and there is no way to edit it here", (
    tester,
  ) async {
    await tester.pumpWidget(waterUnderTest(dayWithGoal));
    await settle(tester);

    expect(find.text('Goal 2,310 ml'), findsOneWidget);
    expect(find.text('Daily goal'), findsOneWidget);
    // The reference draws a pencil beside the goal. A goal the app let a user edit would be the
    // app setting a target, which is the server's job (CLAUDE.md rule 2).
    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('a quick add sends the running TOTAL, not the glass', (tester) async {
    await tester.pumpWidget(waterUnderTest(dayWithGoal));
    await settle(tester);

    await tester.tap(find.text('+250 ml'));
    await settle(tester);

    // One row per kind per diary day: the server stores a day's total, so the addition happens
    // here and the write is the new total (D-86).
    expect(measurements.lastRecorded, 250);
  });

  testWidgets('nothing logged says so rather than drawing an empty list', (tester) async {
    await tester.pumpWidget(waterUnderTest(dayWithGoal));
    await settle(tester);

    expect(find.text('No water logged yet'), findsOneWidget);
  });
}
