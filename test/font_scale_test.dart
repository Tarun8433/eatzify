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
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/account_page.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/features/progress/progress_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// CLAUDE.md rule 12: the app must survive 200 % font scale without clipping. A RenderFlex
/// overflow logs an exception, which fails the test — so this catches the class of bug where a
/// row of numbers looks fine at 1x and breaks for anyone who needs larger text.
void main() {
  testWidgets('Home survives 200 % font scale without overflowing', (tester) async {
    Get
      ..reset()
      ..put<DiaryRepository>(
        FakeDiaryRepository(
          dayResult: const Right(
            DiaryDay(
              diaryDate: '2026-08-25',
              entries: [
                LogEntry(
                  id: '1',
                  slot: 'lunch',
                  name: 'Dal (arhar cooked) with extra long name',
                  quantityG: 300,
                  measureLabel: 'katori',
                  kcal: 348,
                  locked: false,
                ),
              ],
              totals: Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
              targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
            ),
          ),
        ),
        permanent: true,
      )
      ..put<PlanRepository>(FakePlanRepository(), permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: HomePage()),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Progress survives 200 % font scale', (tester) async {
    Get
      ..reset()
      ..put<MeasurementsRepository>(FakeMeasurementsRepository(), permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ProgressPage()),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('You survives 200 % font scale', (tester) async {
    Get
      ..reset()
      ..put<ProfileRepository>(FakeProfileRepository(), permanent: true)
      // The You tab reads the plan's targets for its goal tiles (D-59).
      ..put<PlanRepository>(FakePlanRepository(plan: samplePlan), permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: AccountPage()),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  group('light mode renders', () {
    // Both themes ship, so both are exercised. A theme that is only ever looked at in one mode is
    // a theme with untested colours.
    testWidgets('Home in light mode', (tester) async {
      Get
        ..reset()
        ..put<DiaryRepository>(
          FakeDiaryRepository(
            dayResult: const Right(
              DiaryDay(
                diaryDate: '2026-08-25',
                entries: [
                  LogEntry(
                    id: '1',
                    slot: 'lunch',
                    name: 'Dal',
                    quantityG: 300,
                    measureLabel: 'katori',
                    kcal: 348,
                    locked: false,
                  ),
                ],
                totals: Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
                targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
              ),
            ),
          ),
          permanent: true,
        )
        ..put<PlanRepository>(FakePlanRepository(), permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: HomePage()),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      // The nutrient tiles sit under the hero (D-138) — below the fold on the test surface, and a
      // lazily built list has not made them yet, so the check is for the card that IS above it.
      expect(find.text('supplied'), findsOneWidget);
    });

    testWidgets('Home in light mode at 200 % font scale', (tester) async {
      Get
        ..reset()
        ..put<DiaryRepository>(FakeDiaryRepository(), permanent: true)
        ..put<PlanRepository>(FakePlanRepository(), permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: HomePage()),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
