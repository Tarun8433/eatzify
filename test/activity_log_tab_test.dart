import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/activity_log_tab.dart';

import 'fakes.dart';
import 'pumping.dart';

Widget tabUnderTest({TextScaler scaler = TextScaler.noScaling}) {
  Get
    ..reset()
    ..put<MeasurementsRepository>(FakeMeasurementsRepository(), permanent: true);
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

    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save activity'));
    expect(save.onPressed, isNull, reason: '200,000 steps is a typo, not an achievement');
  });

  /// CLAUDE.md rule 12: the layout must survive 200 % font scale. An overflow throws, so the
  /// assertion is that nothing did.
  testWidgets('the cards survive a 200 % text scale', (tester) async {
    await tester.pumpWidget(tabUnderTest(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
