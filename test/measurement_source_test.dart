import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/activity_log_tab.dart';

import 'fakes.dart';
import 'pumping.dart';

/// D-97. The server refuses to let a sync overwrite a `manual` row, so which label a screen puts on
/// its write is not cosmetic: a hand-entry screen that called itself `apple_health` would lose the
/// user's own corrections at the next sync, and nothing on screen would show it happening.

late FakeMeasurementsRepository measurements;

Widget activityUnderTest() {
  measurements = FakeMeasurementsRepository();
  Get
    ..reset()
    ..put<MeasurementsRepository>(measurements, permanent: true)
    ..put<DiaryRepository>(FakeDiaryRepository(), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: ActivityLogTab()),
  );
}

void main() {
  testWidgets('typing a step count sends it as manual', (tester) async {
    await tester.pumpWidget(activityUnderTest());
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, '8000');
    await tester.pumpAndSettle();
    // The tab scrolls now that each measurement has its own card, so the button has to be brought
    // into view rather than assumed to be on screen.
    final save = find.widgetWithText(FilledButton, 'Save activity');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await settle(tester);

    expect(measurements.lastRecorded, 8000);
    expect(
      measurements.lastSource,
      MeasurementSource.manual,
      reason: 'otherwise the server would refuse the user their own correction',
    );
  });

  group('an unknown source degrades rather than crashes', () {
    test('a wire value from a newer server falls back to manual', () {
      // A closed enum meeting an open wire format. Falling back to `manual` is the quiet choice:
      // it is the label that claims the least, so a mislabelled row understates rather than
      // fabricates a device reading.
      expect(MeasurementSource.fromWire('some_future_platform'), MeasurementSource.manual);
      expect(MeasurementSource.fromWire(null), MeasurementSource.manual);
    });

    test('the known ones round-trip', () {
      for (final source in MeasurementSource.values) {
        expect(MeasurementSource.fromWire(source.wire), source);
      }
    });

    test('only a device reading counts as automatic', () {
      expect(MeasurementSource.manual.isAutomatic, isFalse);
      expect(MeasurementSource.appleHealth.isAutomatic, isTrue);
      expect(MeasurementSource.healthConnect.isAutomatic, isTrue);
    });
  });
}
