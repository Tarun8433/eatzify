import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// These exist because the first build shipped a reactivity bug: every step widget read its `.obs`
/// values outside the parent Obx, so tapping an option changed the value and nothing rebuilt.
/// The domain tests all passed — only the UI was broken. Hence: tap, then assert what the user sees.
Widget app() {
  Get.reset();
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const OnboardingPage(),
  );
}

/// A ChoiceTile shows a filled radio/checkbox only when selected.
bool isSelected(WidgetTester tester, String label) {
  final tile = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final icons = tester.widgetList<Icon>(
    find.descendant(of: tile.first, matching: find.byType(Icon)),
  );
  return icons.any((i) => i.icon == Icons.radio_button_checked || i.icon == Icons.check_box);
}

/// The basics and conditions steps are taller than the 800px test surface, so a bare tap can land
/// off-screen. Scroll the target into view first — this is a test-harness detail, not app behaviour.
Future<void> tapChoice(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> fillBasics(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), '29');
  await tester.enterText(fields.at(1), '173');
  await tester.enterText(fields.at(2), '95.0');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  await tapChoice(tester, 'Male');
}

void main() {
  testWidgets('selecting sex at birth updates the UI', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(isSelected(tester, 'Male'), isFalse);
    await tapChoice(tester, 'Male');
    expect(isSelected(tester, 'Male'), isTrue, reason: 'tapping must rebuild the tile');

    await tapChoice(tester, 'Female');
    expect(isSelected(tester, 'Female'), isTrue);
    expect(isSelected(tester, 'Male'), isFalse, reason: 'single-select must deselect the other');
  });

  testWidgets('Continue stays disabled until every basics field is answered', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull, reason: 'nothing entered yet');

    await fillBasics(tester);
    expect(button().onPressed, isNotNull, reason: 'all four answered');
  });

  testWidgets('Continue enables without blurring the last field', (tester) async {
    // The exact sequence a real user performs: type all three, then tap a choice tile. Tapping a
    // tile does not necessarily blur the weight field, so if values were only recorded on blur the
    // form would look complete while Continue stayed disabled.
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '29');
    await tester.enterText(fields.at(1), '173');
    await tester.enterText(fields.at(2), '95.0');
    await tester.pump();
    await tapChoice(tester, 'Male');

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
      reason: 'no blur happened, but every field holds a valid value',
    );
  });

  testWidgets('an out-of-range value blocks Continue and explains why on blur', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '29');
    await tester.enterText(fields.at(1), '173');
    await tester.enterText(fields.at(2), '9'); // below the 30 kg floor
    await tester.pump();
    await tapChoice(tester, 'Male');

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: '9 kg is out of range, so the value must not be recorded',
    );

    await tester.tap(fields.at(2));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('between 30 and 250'), findsOneWidget);
  });

  testWidgets('typing a partial age does not reject mid-keystroke', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // "2" on the way to "29" is under 18, but the user has not finished typing.
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.pump();
    expect(
      find.textContaining('built for adults'),
      findsNothing,
      reason: 'validation must wait for blur or submit',
    );

    // Committing an actually-underage value does reject (FR-1.2).
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('built for adults'), findsOneWidget);
  });

  testWidgets('goal and activity selections update', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillBasics(tester);

    await tapChoice(tester, 'Continue');
    await tapChoice(tester, 'Lose weight');
    expect(isSelected(tester, 'Lose weight'), isTrue);

    await tapChoice(tester, 'Continue');
    await tapChoice(tester, 'Moderately active');
    expect(isSelected(tester, 'Moderately active'), isTrue);
  });

  testWidgets('conditions multi-select, and "None of these" clears the rest', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillBasics(tester);
    for (final tap in ['Continue', 'Lose weight', 'Continue', 'Moderately active', 'Continue']) {
      await tapChoice(tester, tap);
    }

    await tapChoice(tester, 'PCOS');
    expect(isSelected(tester, 'PCOS'), isTrue);

    await tapChoice(tester, 'None of these');
    expect(isSelected(tester, 'None of these'), isTrue);
    expect(isSelected(tester, 'PCOS'), isFalse, reason: 'docs/03 §2: none is exclusive');
  });

  testWidgets('a blocking condition ends the flow on the referral screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillBasics(tester);
    for (final tap in ['Continue', 'Lose weight', 'Continue', 'Moderately active', 'Continue']) {
      await tapChoice(tester, tap);
    }

    await tapChoice(tester, 'Kidney disease');
    await tapChoice(tester, 'Continue');

    // docs/05 §3: no plan, and no way to push past it.
    expect(find.textContaining("Let's not plan this on our own"), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('men are never asked about pregnancy (FR-1.3)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillBasics(tester); // selects Male
    for (final tap in ['Continue', 'Lose weight', 'Continue', 'Moderately active', 'Continue']) {
      await tapChoice(tester, tap);
    }

    expect(find.text('Pregnant'), findsNothing);
    expect(find.text('Breastfeeding'), findsNothing);
  });
}
