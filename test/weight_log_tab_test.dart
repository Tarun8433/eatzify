import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/weight_log_tab.dart';

import 'fakes.dart';

/// Pushed onto a route rather than sitting at `home`: the form closes the log sheet after a save,
/// and a pop needs something underneath it, exactly as it has in the app.
Widget tabUnderTest(MeasurementsRepository repo) {
  Get
    ..reset()
    ..put<MeasurementsRepository>(repo, permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: WeightLogTab()))),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> openAndSave(WidgetTester tester, String weight) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), weight);
  await tester.pumpAndSettle();
  // "Save weight", not "Save": the button names what it saves (D-127).
  final save = find.widgetWithText(FilledButton, 'Save weight');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('should record the weight when the tab saves it', (tester) async {
    final repo = FakeMeasurementsRepository();
    await tester.pumpWidget(tabUnderTest(repo));

    await openAndSave(tester, '72.5');

    // The tab was a "not connected yet" placeholder; the assertion is that a number typed here now
    // reaches the endpoint at all.
    expect(repo.lastRecorded, 72.5);
    // Hand entry, so the server's conflict rule (D-97) lets it correct a synced figure.
    expect(repo.lastSource, MeasurementSource.manual);
  });

  testWidgets('should ask to confirm when the server calls the value suspect', (tester) async {
    await tester.pumpWidget(tabUnderTest(FakeMeasurementsRepository(isSuspect: true)));

    await openAndSave(tester, '40');

    // docs/09 §4: already saved, so this asks rather than blocks.
    expect(find.text('Does that look right?'), findsOneWidget);
  });

  testWidgets('should keep the form open showing the server message when the save fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      tabUnderTest(
        FakeMeasurementsRepository(
          failure: const ApiFailure(
            'Weight must be between 30 and 250 kg.',
            code: 'X',
            status: 422,
          ),
        ),
      ),
    );

    await openAndSave(tester, '72.5');

    // Rule 7: the server's own words, next to the field the user still has to correct.
    expect(find.text('Weight must be between 30 and 250 kg.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
