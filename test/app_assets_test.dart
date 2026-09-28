import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/weight_log_tab.dart';

import 'fakes.dart';

/// The asset every [Image] in the tree is actually drawing.
Set<String> drawnAssets(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((a) => a.assetName)
    .toSet();

Widget tabIn(ThemeData theme) {
  final repo = FakeMeasurementsRepository();
  Get
    ..reset()
    ..put<MeasurementsRepository>(repo, permanent: true);
  return GetMaterialApp(
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: WeightLogTab()),
  );
}

/// The heroes supplied in two colour grades (D-161).
const paired = {
  AppAssets.activityHero,
  AppAssets.weightHero,
  AppAssets.waterHero,
  AppAssets.dashboardStage,
  AppAssets.routineHero,
  AppAssets.consentHero,
};

void main() {
  /// A missing asset in Flutter is a broken image at runtime, not an exception anything catches,
  /// so the pairing has to be checked against the disk rather than trusted.
  group('every paired hero has both grades on disk', () {
    for (final asset in paired) {
      test(asset, () {
        final dark = AppAssets.themed(asset, Brightness.dark);

        expect(dark, isNot(asset), reason: '$asset resolved to itself in dark mode');
        expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
        expect(File(dark).existsSync(), isTrue, reason: '$dark is missing');
      });
    }
  });

  test('light mode is the unqualified path', () {
    for (final asset in paired) {
      expect(AppAssets.themed(asset, Brightness.light), asset);
    }
  });

  /// The bowl is the one hero with no dark grade. Returning it unchanged is the honest answer;
  /// pointing at a `dark/` file that was never drawn would be a broken image on the Plan tab.
  test('an unpaired hero returns itself in both themes', () {
    expect(AppAssets.themed(AppAssets.planHero, Brightness.dark), AppAssets.planHero);
    expect(AppAssets.themed(AppAssets.planHero, Brightness.light), AppAssets.planHero);
  });

  /// A `dark/` file nobody resolves to is dead weight in the bundle (NFR-4), and usually means a
  /// hero was given a dark grade and never added to the paired set — so it silently keeps
  /// rendering the light one.
  test('no dark grade is stranded', () {
    final resolved = {for (final asset in paired) AppAssets.themed(asset, Brightness.dark)};

    for (final dir in [Directory('assets/activity/dark'), Directory('assets/onboarding/dark')]) {
      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.DS_Store')) continue;
        expect(resolved, contains(file.path), reason: '${file.path} is shipped but never drawn');
      }
    }
  });

  /// A directory entry in pubspec is NOT recursive: `assets/activity/` does not carry
  /// `assets/activity/dark/`. Miss this and every dark grade is absent from the bundle, which
  /// looks exactly like the bug this pairing was added to fix.
  test('the dark folders are declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('assets/activity/dark/'));
    expect(pubspec, contains('assets/onboarding/dark/'));
  });

  /// The resolver being right is not the same as the SCREENS using it. This is the failure the
  /// pairing actually has: a hero drawn straight from the constant keeps the light grade in dark
  /// mode, and nothing anywhere throws.
  group('the screens draw the grade their theme asks for', () {
    testWidgets('the weight tab takes the dark grade in dark mode', (tester) async {
      await tester.pumpWidget(tabIn(AppTheme.dark));
      await tester.pumpAndSettle();

      expect(drawnAssets(tester), contains('assets/activity/dark/weighing_scale.png'));
      expect(drawnAssets(tester), isNot(contains(AppAssets.weightHero)));
    });

    testWidgets('and the light grade in light mode', (tester) async {
      await tester.pumpWidget(tabIn(AppTheme.light));
      await tester.pumpAndSettle();

      expect(drawnAssets(tester), contains(AppAssets.weightHero));
      expect(drawnAssets(tester), isNot(contains('assets/activity/dark/weighing_scale.png')));
    });
  });
}
