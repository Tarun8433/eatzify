import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/goal_result.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// The goal-gap card (D-110).
///
/// What is worth asserting on a screen this decorative is the one claim it makes. "Your target
/// sits inside the healthy weight range" is a restatement of the rule the form already enforced —
/// so it must appear only when that is true, and never when the app cannot know.
Widget app({
  double? startKg = 70,
  double? targetKg = 50,
  bool? inHealthyRange,
  TextScaler scaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: scaler),
    child: child!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GoalResultView(startKg: startKg, targetKg: targetKg, inHealthyRange: inHealthyRange),
      ),
    ),
  ),
);

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalResultView)));

void main() {
  testWidgets('shows the gap, both weights, and no forecast', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    // The headline reads as one sentence to a screen reader even though it is drawn in two
    // coloured lines — the split is a visual arrangement, not two facts.
    expect(find.bySemanticsLabel(l.onboardingResultTitle('20.0')), findsOneWidget);
    expect(find.text('70.0 kg'), findsOneWidget);
    expect(find.text('50.0 kg'), findsOneWidget);
    expect(find.text(l.onboardingResultCurrentChip), findsOneWidget);
    expect(find.text(l.onboardingResultGoalChip), findsOneWidget);
  });

  testWidgets('the healthy-range note appears only when the target is in it', (tester) async {
    await tester.pumpWidget(app(inHealthyRange: true));
    await settle(tester);
    final l = l10n(tester);
    expect(find.text(l.onboardingResultHealthyNote), findsOneWidget);
    expect(find.text(l.onboardingResultHealthyChip), findsOneWidget);
  });

  testWidgets('and says nothing at all when it is not, or cannot be known', (tester) async {
    for (final answer in [false, null]) {
      await tester.pumpWidget(app(inHealthyRange: answer));
      await settle(tester);
      final l = l10n(tester);

      // Silence, not a warning. docs/05 §6 forbids judging a goal, and rule 7 puts any clinical
      // message on the server — a goal under the floor is refused at input, not scolded here.
      expect(find.text(l.onboardingResultHealthyNote), findsNothing, reason: '$answer');
      expect(find.text(l.onboardingResultHealthyChip), findsNothing, reason: '$answer');
      // The rest of the card is unchanged.
      expect(find.text('50.0 kg'), findsOneWidget, reason: '$answer');
    }
  });

  testWidgets('with no target given there is no gap and no claim', (tester) async {
    await tester.pumpWidget(app(targetKg: null));
    await settle(tester);

    // Same weight both ends, so the headline is "hold your weight" rather than a zero-kilo loss.
    expect(find.bySemanticsLabel(l10n(tester).onboardingResultHold), findsOneWidget);
  });

  testWidgets('survives 200 % font scale without clipping (rule 12)', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(inHealthyRange: true, scaler: const TextScaler.linear(2)));
    await settle(tester);

    // The art is the first thing given up for the words at this scale, so the headline gets the
    // whole width rather than three characters of it.
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
