import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/progress/log_weight_sheet.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/weight_log_tab.dart';

import 'fakes.dart';

late FakeMeasurementsRepository repo;

late ProgressController controller;

/// One app around whatever the test opens, so the tab and the bottom sheet — the two places the
/// same form lives — are exercised through the same scaffolding rather than two copies of it.
Widget harness(void Function(BuildContext) onOpen) {
  repo = FakeMeasurementsRepository();
  Get
    ..reset()
    ..put<MeasurementsRepository>(repo, permanent: true);
  controller = Get.put(ProgressController(measurements: repo), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => onOpen(context), child: const Text('open')),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  // Pushed, because saving pops.
  await tester.pumpWidget(
    harness(
      (context) => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: WeightLogTab()))),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The Progress tab's modal route, which is the one that has to bring its own scrolling.
Future<void> openSheet(WidgetTester tester) async {
  await tester.pumpWidget(harness((context) => LogWeightSheet.show(context, controller)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Save weight');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  /// The server's `weight` kind is bounded in kilograms and refuses any other unit, so pounds are a
  /// reading, never a wire value. A pound figure sent as kg is a 2.2x error in someone's plan.
  testWidgets('a weight read in pounds is stored in kilograms', (tester) async {
    await open(tester);

    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '155');
    await tester.pumpAndSettle();
    await save(tester);

    expect(repo.lastRecorded, closeTo(70.307, 0.001));
  });

  testWidgets('switching units converts the reading rather than relabelling it', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '70.5');
    await tester.pumpAndSettle();
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();

    // 70.5 kg is 155.4 lb — not "70.5 lb", which is what a label swap would have left on screen.
    expect(find.text('155.4'), findsOneWidget);
  });

  /// docs/09 §4 takes `recorded_at`; the SERVER still decides which diary day it belongs to
  /// (CLAUDE.md rule 8). Sending nothing is what "now" means, and is the common case.
  testWidgets('a reading taken now carries no timestamp of its own', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '70.5');
    await tester.pumpAndSettle();
    await save(tester);

    expect(repo.lastRecorded, 70.5);
    expect(repo.lastAt, isNull);
  });

  /// The sheet opens with the keyboard already up, which leaves it far shorter than its content.
  /// Without a scroll view of its own that is a RenderFlex overflow across the bottom of the card.
  testWidgets('the sheet scrolls rather than overflowing in a keyboard-height viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    // Roughly what an iPhone leaves above the number pad.
    tester.view.physicalSize = const Size(390, 480);
    addTearDown(tester.view.reset);

    await openSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  /// The ruler opens on the last known weight, so a "0.0" placeholder had the sheet showing one
  /// reading as two different numbers. The field stays EMPTY either way — the hint is grey, Save
  /// is still disabled, and nothing is saved that the user did not enter.
  testWidgets('the empty field hints the weight the ruler is resting on, not zero', (tester) async {
    await open(tester);

    // defaultHistory ends at 75 - 3 * 0.2.
    expect(find.text('74.4'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save weight')).onPressed,
      isNull,
    );
  });
}
