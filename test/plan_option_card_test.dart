import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/presentation/features/plan/plan_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

Widget planUnderTest({double textScale = 1}) {
  Get
    ..reset()
    ..put<PlanRepository>(FakePlanRepository(plan: samplePlan), permanent: true)
    ..put<DiaryRepository>(FakeDiaryRepository(), permanent: true);
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PlanPage()),
    ),
  );
}

Future<void> openOptions(WidgetTester tester) async {
  // The header counts what is inside it (D-130): "6 suggested foods", not a fixed label.
  final headers = find.textContaining('suggested food');
  // Two hazards, one loop. At 200 % the first meal card is below the fold and a lazily built list
  // has not made it yet, so there is nothing to ensureVisible; and once the list HAS built, several
  // headers match at once, so a finder that demands exactly one is wrong too.
  for (var i = 0; i < 8 && headers.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester);
  }
  // A tap that lands off-screen is silently a no-op, which would make every assertion after it
  // vacuous.
  await tester.ensureVisible(headers.first);
  await settle(tester);
  // The first slot now opens READY (D-134), and the tile is a toggle — tapping an open one would
  // close it and hide the very strip these tests are about. Tap only when the fixture food is
  // not already on screen.
  if (find.text('Dal tadka').evaluate().isEmpty) {
    await tester.tap(headers.first);
    await settle(tester);
  }
}

void main() {
  /// The bug: the card was a fixed height with a SQUARE picture in it, so the picture plus two
  /// lines of name plus the measure overflowed by 8 px. A card whose text cannot grow is an
  /// overflow waiting for the first long food name or the first larger font.
  group('the option card fits its box (D-84)', () {
    testWidgets('at the default text size', (tester) async {
      await tester.pumpWidget(planUnderTest());
      await settle(tester);
      await openOptions(tester);

      // Guard against a vacuous pass: a card that never rendered cannot overflow either.
      expect(find.text('Dal tadka'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and at 200 % font scale, which CLAUDE.md rule 12 requires', (tester) async {
      await tester.pumpWidget(planUnderTest(textScale: 2));
      await settle(tester);
      await openOptions(tester);

      expect(find.text('Dal tadka'), findsOneWidget);
      // takeException() is how a RenderFlex overflow surfaces in a test — it is an exception, not
      // a failed expectation, so nothing catches it unless it is asked for.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the strip scrolls sideways rather than stacking', (tester) async {
      await tester.pumpWidget(planUnderTest());
      await settle(tester);
      await openOptions(tester);

      final list = tester.widget<ListView>(
        find.descendant(of: find.byType(PlanPage), matching: find.byType(ListView)).last,
      );
      expect(list.scrollDirection, Axis.horizontal);
    });
  });
}
