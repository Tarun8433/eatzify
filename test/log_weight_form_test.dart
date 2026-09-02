import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/weight_log_tab.dart';

import 'fakes.dart';

late FakeMeasurementsRepository repo;

Widget tabUnderTest() {
  repo = FakeMeasurementsRepository();
  Get
    ..reset()
    ..put<MeasurementsRepository>(repo, permanent: true)
    ..put(ProgressController(measurements: repo), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    // Pushed, because saving pops.
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: WeightLogTab()))),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  await tester.pumpWidget(tabUnderTest());
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
}
