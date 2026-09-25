import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/features/home/home_skeleton.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

/// The skeleton exists to have the same SHAPE as the loaded dashboard, and shape is the one thing
/// a widget test cannot check. Regenerate with
/// `flutter test --update-goldens test/home_skeleton_golden_test.dart`.
Widget skeletonIn(ThemeData theme) {
  // Roboto for Inter: every style goes through google_fonts, which in a test is an HTTP fetch
  // that fails to Ahem. See D-160.
  final withFont = theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto'));

  return MaterialApp(
    theme: withFont,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
      body: Padding(
        // TabScaffold's own inset, so the golden frames the skeleton the way Home does.
        padding: EdgeInsets.only(top: 24),
        child: HomeSkeleton(),
      ),
    ),
  );
}

Future<void> pump(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(skeletonIn(theme));
  // The sweep is a repeating animation, so the tree never settles — pump a fixed way into it
  // instead, which also makes the golden deterministic.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the dashboard skeleton, light', (tester) async {
    await pump(tester, AppTheme.light);
    await expectLater(find.byType(HomeSkeleton), matchesGoldenFile('goldens/home_skeleton.png'));
  });

  testWidgets('the dashboard skeleton, dark', (tester) async {
    await pump(tester, AppTheme.dark);
    await expectLater(
      find.byType(HomeSkeleton),
      matchesGoldenFile('goldens/home_skeleton_dark.png'),
    );
  });

  /// The point of the whole exercise: the skeleton is meant to be THIS page with the words
  /// missing. Kept beside the skeleton golden so the two can be held up against each other —
  /// a day bar, a hero card with the water card on its foot, a heading row, a tile row, a card,
  /// a heading and a list of entries.
  testWidgets('the loaded dashboard, for comparison', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final theme = AppTheme.light;
    Get
      ..reset()
      ..put<DiaryRepository>(
        FakeDiaryRepository(
          dayResult: const Right(
            DiaryDay(
              diaryDate: '2026-08-25',
              entries: [],
              totals: Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
              targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
              waterLoggedMl: 900,
              waterTargetMl: 2500,
            ),
          ),
        ),
        permanent: true,
      )
      ..put<PlanRepository>(FakePlanRepository(), permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
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
    // The walker is always mid-stride, so nothing ever settles (see pumping.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(find.byType(HomePage), matchesGoldenFile('goldens/home_loaded.png'));
  });
}
