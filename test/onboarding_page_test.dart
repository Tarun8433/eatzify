import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/core/widgets/weight_curve.dart';
import 'package:health_pro/core/widgets/wheel_picker.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/choice_tile.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// These exist because the first build shipped a reactivity bug: every step widget read its `.obs`
/// values outside the parent Obx, so tapping an option changed the value and nothing rebuilt.
/// The domain tests all passed — only the UI was broken. Hence: tap, then assert what the user sees.
Widget app({ProfileRepository? profiles, PlanRepository? plans}) {
  Get
    ..reset()
    ..put<ProfileRepository>(profiles ?? FakeProfileRepository(), permanent: true)
    // The preparing screen generates the first plan for real (D-75), so the flow needs both.
    ..put<PlanRepository>(plans ?? FakePlanRepository(plan: samplePlan), permanent: true);
  putFakeSession();
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

/// Whether an option reads as selected.
///
/// Via the semantics flag rather than by hunting for a filled radio icon: chips show selection with
/// a border and weight and carry no icon at all (D-88), and the flag is what a screen reader
/// actually announces — so asserting on it tests the contract that matters rather than the artwork.
bool isSelected(WidgetTester tester, String label) => tester
    .widget<ChoiceTile>(
      find.ancestor(of: find.text(label), matching: find.byType(ChoiceTile)).first,
    )
    .selected;

/// The basics and conditions steps are taller than the 800px test surface, so a bare tap can land
/// off-screen. Scroll the target into view first — this is a test-harness detail, not app behaviour.
Future<void> tapChoice(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> fillBasics(WidgetTester tester) async {
  // TYPED, not poked into the controller (D-95). The numbers are fields again — a wheel behind a
  // button, and a keyboard for anyone who already knows their weight — so the test can drive the
  // real path instead of the shortcut the inline wheels forced on it.
  const values = ['Asha', '29', '173', '95', '78'];
  for (final (i, value) in values.indexed) {
    await tester.ensureVisible(find.byType(TextField).at(i));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(i), value);
    await tester.pumpAndSettle();
  }
  // Blur the last field so it commits — the controller only accepts loudly on blur.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();

  await tapChoice(tester, 'Male');
}

/// The time fields open a platform picker, which is a dialog dance that tells us nothing about the
/// flow. Times are set on the controller instead — the same harness-shortcut reasoning as
/// `ensureVisible` above. `_TimeField` itself is covered by its own test.
void setTimes(WidgetTester tester) {
  Get.find<OnboardingController>()
    ..wakeTime.value = '06:30'
    ..sleepTime.value = '23:00'
    ..breakfastTime.value = '08:00'
    ..lunchTime.value = '13:30'
    ..eveningSnackTime.value = '17:30'
    ..dinnerTime.value = '20:30';
}

/// docs/05 §4 has three yes/no questions; taps are positional because 'Yes'/'No' repeat.
Future<void> answerScreening(
  WidgetTester tester, {
  required bool specialDiet,
  required bool insulinOrKidney,
  required bool eatingDisorder,
}) async {
  final answers = [specialDiet, insulinOrKidney, eatingDisorder];
  for (var q = 0; q < answers.length; q++) {
    final finder = find.text(answers[q] ? 'Yes' : 'No').at(q);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}

/// Walks as far as the conditions step. Every test that needs the condition list starts here, so a
/// step inserted before it is fixed in one place.
Future<void> reachConditions(WidgetTester tester) async {
  await fillBasics(tester);
  // Two Continues before the goal question, not one: basics now hands off to the result screen
  // (D-101), which asks nothing and exists to be read.
  for (final tap in [
    'Continue',
    'Continue',
    'Weight loss',
    'Continue',
    'Moderately active',
    'Continue',
  ]) {
    await tapChoice(tester, tap);
  }

  // Daily routine: the two clock times gate the step, and the duration is derived from them (D-77).
  setTimes(tester);
  await tester.pump();
  await tapChoice(tester, 'Continue');
}

/// Walks as far as the screening step, leaving it unanswered.
Future<void> reachScreening(WidgetTester tester) async {
  await reachConditions(tester);
  for (final tap in [
    'None of these',
    'Continue',
    // The health step is entirely optional — walking straight past it is the common path.
    'Continue',
  ]) {
    await tapChoice(tester, tap);
  }
}

/// Walks every step to the end. Mirrors what a user does, so a broken step fails here first.
Future<void> completeFlow(WidgetTester tester) async {
  await reachScreening(tester);
  await answerScreening(tester, specialDiet: false, insulinOrKidney: false, eatingDisorder: false);
  for (final tap in ['Continue', 'Vegetarian', 'Continue']) {
    await tapChoice(tester, tap);
  }

  // Meal timings were set in reachScreening; the step just needs advancing.
  await tapChoice(tester, 'Continue');

  // No budget tap: it is a slider now (D-78) and it starts at a usable default.
  for (final tap in ['4 meals', 'Office job', 'Continue']) {
    await tapChoice(tester, tap);
  }

  // The summary reads the answers back and asks nothing (D-114).
  await tapChoice(tester, 'Continue');
}

/// Ticks the consent card (D-115).
///
/// The whole card is the control now, not a `CheckboxListTile`, and the step is taller than the
/// test surface with the art on it — so this scrolls to the checkbox before tapping it.
Future<void> grantConsent(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Create my plan" completes the flow instead of doing nothing', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await completeFlow(tester);

    // On the consent step the button reads "Create my plan" and is disabled until consent is given.
    expect(find.text('Create my plan'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await grantConsent(tester);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);

    await tester.tap(find.text('Create my plan'));
    // Not pumpAndSettle: the preparing screen loops a Lottie, so a frame is always scheduled — the
    // same reason `settle` exists for the walker (D-58). The span clears the preparing floor's
    // timer too, which would otherwise be pending at teardown.
    await settle(tester, const Duration(seconds: 4));

    // The answers are persisted, then the preparing screen takes over while the first plan is
    // generated behind it.
    expect(find.text('Building your plan'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('"Create my plan" actually submits the collected answers', (tester) async {
    final repo = FakeProfileRepository();
    await tester.pumpWidget(app(profiles: repo));
    await tester.pumpAndSettle();
    await completeFlow(tester);
    await grantConsent(tester);
    await tester.tap(find.text('Create my plan'));
    // Not pumpAndSettle: the preparing screen loops a Lottie, so a frame is always scheduled — the
    // same reason `settle` exists for the walker (D-58). The span clears the preparing floor's
    // timer too, which would otherwise be pending at teardown.
    await settle(tester, const Duration(seconds: 4));

    // The body is what reaches the server — a flow that "completes" without this is the bug that
    // shipped before: every answer collected, then silently discarded.
    final body = repo.lastSubmission;
    expect(body, isNotNull);
    expect(body!.ageYears, 29);
    expect(body.consentGranted, isTrue);

    final json = body.toJson();
    expect(json['profile'], isA<Map<String, dynamic>>());
    expect(json['consents'], isNotEmpty);
  });

  testWidgets('a server gate routes to the gate screen, not to "all set"', (tester) async {
    // docs/05 §3: the server re-runs every gate and its answer wins, even if the client let the
    // user through. Continuing to a plan here would be the exact failure the gates exist to prevent.
    final repo = FakeProfileRepository(
      result: const OnboardingResult(userId: '1', healthProfileVersion: 1, gates: ['pregnancy']),
    );
    await tester.pumpWidget(app(profiles: repo));
    await tester.pumpAndSettle();
    await completeFlow(tester);
    await grantConsent(tester);
    await tester.tap(find.text('Create my plan'));
    // Not pumpAndSettle: the preparing screen loops a Lottie, so a frame is always scheduled — the
    // same reason `settle` exists for the walker (D-58). The span clears the preparing floor's
    // timer too, which would otherwise be pending at teardown.
    await settle(tester, const Duration(seconds: 4));

    expect(find.text('Building your plan'), findsNothing);
  });

  group('the preparing screen (D-75)', () {
    testWidgets('generates the first plan rather than counting to three', (tester) async {
      final plans = FakePlanRepository(plan: samplePlan);
      await tester.pumpWidget(app(plans: plans));
      await tester.pumpAndSettle();
      await completeFlow(tester);
      await grantConsent(tester);
      await tester.tap(find.text('Create my plan'));
      await settle(tester, const Duration(seconds: 4));

      // Nothing else in the app called generate, so every new user landed on an empty Home behind
      // a "Create my plan" button. The wait was going to happen — this is where it belongs.
      expect(plans.generated, 1);
      expect(
        Get.find<SessionController>().status.value,
        AuthStatus.signedIn,
        reason: 'and it moves on to the dashboard by itself',
      );
    });

    testWidgets('a plan that fails to generate does not trap the user here', (tester) async {
      await tester.pumpWidget(
        app(
          plans: FakePlanRepository(failure: const ApiFailure('no plan', code: 'X')),
        ),
      );
      await tester.pumpAndSettle();
      await completeFlow(tester);
      await grantConsent(tester);
      await tester.tap(find.text('Create my plan'));
      await settle(tester, const Duration(seconds: 4));

      // Home renders the server's message and offers the button — the worst case is the screen
      // they used to get every time, not a dead end on an animation.
      expect(Get.find<SessionController>().status.value, AuthStatus.signedIn);
    });
  });

  testWidgets('a failed submit shows the server user_message and does not advance', (tester) async {
    // CLAUDE.md rule 7: the server's own string, never copy we invented.
    final repo = FakeProfileRepository(
      failure: const ApiFailure('We could not save your details.', code: 'X', status: 500),
    );
    await tester.pumpWidget(app(profiles: repo));
    await tester.pumpAndSettle();
    await completeFlow(tester);
    await grantConsent(tester);
    await tester.tap(find.text('Create my plan'));
    // Not pumpAndSettle: the preparing screen loops a Lottie, so a frame is always scheduled — the
    // same reason `settle` exists for the walker (D-58). The span clears the preparing floor's
    // timer too, which would otherwise be pending at teardown.
    await settle(tester, const Duration(seconds: 4));

    expect(find.text('Building your plan'), findsNothing);
    // ON SCREEN, not just in the controller. The previous version of this assertion read
    // `submitError.value` — which was true while nothing rendered it, so a failed submit looked
    // like a button that did nothing and the test stayed green (D-91).
    expect(find.text('We could not save your details.'), findsOneWidget);
  });

  testWidgets('the whole docs/03 §2 contract is collected', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final c = Get.find<OnboardingController>();
    await completeFlow(tester);

    expect(c.ageYears.value, 29);
    expect(c.heightCm.value, 173);
    expect(c.weightKg.value, 95.0);
    expect(c.sexAtBirth.value, isNotNull);
    expect(c.goalDeclared.value, isNotNull);
    expect(c.goal, isNotNull, reason: 'the engine goal is derived from the declared one');
    expect(c.activity.value, isNotNull);
    expect(c.conditions, isNotEmpty);
    expect(c.foodPreference.value, isNotNull);
    expect(c.mealCount.value, isNotNull);
    expect(c.lifestyle.value, isNotNull);
    // A slider now, so it always has a value; what matters is the tier it implies (D-78).
    expect(c.budgetMonthlyInr.value, BudgetRange.defaultInr);
    expect(c.budgetTier, BudgetTier.forMonthlyInr(BudgetRange.defaultInr));
  });

  /// The wheel replaced four number keyboards (D-88). What those tests guarded — a rejected value,
  /// a partial entry, a commit on blur — cannot happen on a control that only holds legal values.
  group('the basics step: type it or scroll to it (D-88, D-95)', () {
    testWidgets('every number is a field with a picker button beside it', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Name, age, height, weight, target weight. Four inline wheels cost five rows each and ran
      // the step past the fold (D-95); they are behind the buttons now.
      expect(find.byType(TextField), findsNWidgets(5));
      expect(find.byType(WheelPicker), findsNothing, reason: 'not until a button is tapped');
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(4));
    });

    testWidgets('the button opens a wheel, and Done writes it into the field', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      expect(find.byType(WheelPicker), findsOneWidget, reason: 'in a sheet, not on the step');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Committed WITHOUT scrolling: the sheet opens centred on a number, and Done has to mean
      // that number rather than nothing. 59 is the middle of 18..99.
      expect(Get.find<OnboardingController>().ageYears.value, 59);
      expect(find.widgetWithText(TextField, '59'), findsOneWidget, reason: 'and it is visible');
    });

    testWidgets('Done stays reachable at 200 % font scale (rule 12)', (tester) async {
      tester.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: app(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();

      // The sheet was capped at 9/16 of the screen, which put Done past the bottom edge — so the
      // tap landed on the barrier and DISMISSED the sheet. Dismissing looks exactly like
      // cancelling, so nothing about it read as broken.
      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(Get.find<OnboardingController>().ageYears.value, isNotNull);
    });

    testWidgets('a typed number is accepted, and an illegal one is refused', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final controller = Get.find<OnboardingController>();

      await tester.enterText(find.byType(TextField).at(1), '34');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(controller.ageYears.value, 34, reason: 'typing is a first-class path again');

      // The wheel could not produce an out-of-range value; a keyboard can, so the range has to be
      // enforced somewhere the keyboard also passes through.
      await tester.enterText(find.byType(TextField).at(1), '7');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(controller.ageYears.value, isNull);
      expect(controller.reject.value, isNotNull, reason: 'and it says so');
    });

    testWidgets('age sits beside height, and the two weights beside each other (D-90)', (
      tester,
    ) async {
      // A PHONE, not the 800x600 default. The first version of this test passed on the default
      // surface while the pair stacked on every real device, because 800 cleared a threshold no
      // phone ever reaches (D-90).
      tester.view
        ..physicalSize =
            const Size(1170, 2532) // iPhone 13/14/15 class
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Index 0 is the name field; the four numbers follow it.
      final fields = find.byType(TextField);
      final age = tester.getRect(fields.at(1));
      final height = tester.getRect(fields.at(2));
      final weight = tester.getRect(fields.at(3));
      final target = tester.getRect(fields.at(4));

      // Same row: aligned tops, and one starts where the other ends.
      expect(age.top, moreOrLessEquals(height.top, epsilon: 1));
      expect(height.left, greaterThan(age.right - 1));

      // The weights especially: the gap between current and target is what is being decided, and
      // it is only visible with both numbers in view.
      expect(weight.top, moreOrLessEquals(target.top, epsilon: 1));
      expect(target.left, greaterThan(weight.right - 1));
      expect(weight.top, greaterThan(age.top), reason: 'and the weights come after');
    });

    testWidgets('at 200 % font scale the pairs stack instead of squeezing (rule 12)', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: app(),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final age = tester.getRect(fields.at(1));
      final height = tester.getRect(fields.at(2));

      // A label and its value need the full width at that scale; the layout gives way, not the
      // text.
      expect(height.top, greaterThan(age.bottom - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Continue enables once every number and the gender are answered', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await fillBasics(tester);

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
        reason: 'every field committed a legal value',
      );
    });
  });

  /// D-106 rebuilt this screen against the supplied reference. What is asserted here is what the
  /// reference is FOR — art on the first screen, and a label that fits beside a picker button.
  group('the basics step matches the reference (D-106)', () {
    testWidgets('the art is on the first step and nowhere else', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);

      Get.find<OnboardingController>().step.value = OnboardingStep.goal;
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing, reason: 'the funnel is not a gallery');
    });

    testWidgets('a large text scale takes the art, not the title (rule 12)', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: app(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('About you'), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'the words get the width, the picture goes');
    });

    /// Two defects, one measurement (D-104, D-106, D-108).
    ///
    /// D-104 found "Current weight (kg)" clipped to "Current wei…" by looking at a screenshot.
    /// D-106 and D-108 each shrank the same slot again — a leading disc, then an even gap around
    /// it — and each time the label went with it. What is asserted is the SLOT, not the string:
    /// the test font is twice the width of any real one, so comparing a label to the space it has
    /// only measures the fixture. A slot that stops shrinking is what actually keeps labels whole.
    ///
    /// And D-108's own report: the disc was not sitting the same way in every field. Every field
    /// on the step is measured, and they have to agree exactly.
    testWidgets('every field gives its label the same slot, and enough of one', (tester) async {
      // The NARROWEST phone that still puts the number pair side by side. A 390 pt screen has
      // slack and hides this; 375 is where a slot one affix too many actually clips.
      tester.view
        ..physicalSize = const Size(750, 1334)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      /// What a leading disc costs a field: the inset before it, and the whole prefix box.
      List<double> geometryOf(String label) {
        final text = find.text(label);
        final field = find.ancestor(of: text, matching: find.byType(TextField)).first;
        final icon = find.descendant(of: field, matching: find.byType(FieldIcon));
        final f = tester.getRect(field);
        final i = tester.getRect(icon);
        return [i.left - f.left, i.width, tester.getRect(text).left - i.right];
      }

      final name = geometryOf('Your name');
      for (final label in ['Age', 'Height', 'Weight', 'Target']) {
        expect(
          geometryOf(label),
          name,
          reason: '"$label" sits its icon differently from the name field',
        );
      }

      // 60 pt holds every paired label with room to spare on this phone. Below it they ellipsise,
      // and the only honest fix is to stop putting two of these side by side.
      for (final label in ['Age', 'Height', 'Weight', 'Target']) {
        expect(
          tester.getRect(find.text(label)).width,
          greaterThanOrEqualTo(60),
          reason: 'the affixes have eaten the slot "$label" is drawn in',
        );
      }
    });
  });

  /// D-109 rebuilt the routine step against its reference. The screen's job is to take two times
  /// and hand back the one number they add up to.
  group('the routine step gives the arithmetic back (D-109)', () {
    Future<void> openRoutine(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      Get.find<OnboardingController>()
        ..wakeTime.value = '07:00'
        ..sleepTime.value = '23:00'
        ..step.value = OnboardingStep.dailyRoutine;
      await tester.pumpAndSettle();
    }

    testWidgets('the two times are rows, and the hours are derived from them', (tester) async {
      await openRoutine(tester);

      // Not `TextField`s: a time already chosen is an answer to read back (D-109).
      expect(find.byType(ValueRow), findsNWidgets(2));
      expect(find.text('8 hours in bed'), findsOneWidget);

      Get.find<OnboardingController>().sleepTime.value = '22:30';
      await tester.pumpAndSettle();
      expect(find.text('8.5 hours in bed'), findsOneWidget, reason: 'D-77: derived, never asked');
    });

    testWidgets('nothing judges the number (docs/05 §6)', (tester) async {
      await openRoutine(tester);
      Get.find<OnboardingController>().sleepTime.value = '02:00';
      await tester.pumpAndSettle();

      // Five hours. The note under the rule still reads the same, the Continue button still
      // works, and no colour or label calls it a problem.
      expect(find.text('5 hours in bed'), findsOneWidget);
      expect(find.textContaining('7-9 hours'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('the disclaimer is a card, not a footnote (docs/05 §7)', (tester) async {
      await openRoutine(tester);

      expect(find.text('Important'), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
    });
  });

  /// D-110 rebuilt the conditions step against its reference.
  /// D-117: going back showed empty fields for answers that had been given.
  group('going back shows what was already answered', () {
    testWidgets('every typed field on the basics step comes back filled', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await fillBasics(tester);

      // Forward to the result screen, then straight back.
      await tapChoice(tester, 'Continue');
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Read off the WIDGETS, not the controller: the controller kept these all along — the bug
      // was that the fields were rebuilt empty on top of them, which is what the user saw.
      for (final typed in ['Asha', '29', '173', '95', '78']) {
        expect(find.text(typed), findsOneWidget, reason: '"$typed" survived the round trip');
      }
      expect(isSelected(tester, 'Male'), isTrue, reason: 'and so did the choice');
    });

    testWidgets('the free-text answers on later steps come back too', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachConditions(tester);
      await tapChoice(tester, 'None of these');
      await tapChoice(tester, 'Continue');

      // The health step: medicines, typed and optional.
      await tester.enterText(find.byType(TextField).first, 'Metformin 500mg');
      await tester.pumpAndSettle();
      await tapChoice(tester, 'Continue');
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Metformin 500mg'), findsOneWidget);
    });
  });

  /// D-115 rebuilt the consent step against its reference.
  group('consent is asked for, never assumed', () {
    testWidgets('it arrives unticked and the button is dead until it is ticked', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await completeFlow(tester);

      // FR-1.7 / docs/13 §3: opt-in, never pre-ticked. The button is the proof — it is the thing
      // that would let a user through without having agreed.
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await grantConsent(tester);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('the whole card is the control, not just the box', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await completeFlow(tester);

      // Tapping the sentence has to work: a 24 pt box beside a two-line label is a target most
      // people will miss on the one screen they must not miss it on (rule 12).
      await tester.ensureVisible(find.text('Store my health details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Store my health details'));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('and it says what happens to the data, beside the decision', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await completeFlow(tester);

      for (final line in ['Your data is secure', "You're in control", 'Delete anytime']) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
    });
  });

  /// D-114 added the summary step after the routine one.
  group('the summary reads the answers back before consent', () {
    Future<void> reachSummary(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: false,
        insulinOrKidney: false,
        eatingDisorder: false,
      );
      for (final tap in [
        'Continue',
        'Vegetarian',
        'Continue',
        'Continue',
        '4 meals',
        'Office job',
        'Continue',
      ]) {
        await tapChoice(tester, tap);
      }
    }

    testWidgets('it shows the budget the user set, which nothing else reads back', (tester) async {
      await reachSummary(tester);

      // The slider is two screens back and its figure has not been seen since. Indian digit
      // grouping, per ui-standards — ₹8,000, never ₹8000 and never 8,000.
      expect(find.textContaining('₹8,000'), findsOneWidget);
    });

    testWidgets('and the shape of the day it will be built around', (tester) async {
      await reachSummary(tester);

      expect(find.text('4 meals'), findsOneWidget);
      expect(find.text('Office job'), findsOneWidget);
      // The curve comes back without the result step's headline: it is the part worth seeing
      // twice, the words that introduce it are not.
      expect(find.byType(WeightCurve), findsOneWidget);
      expect(find.textContaining("You're aiming to"), findsNothing);
    });

    testWidgets('it asks nothing, so Continue is live on arrival', (tester) async {
      await reachSummary(tester);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });
  });

  /// D-113 gave the meal-timings step the routine step's treatment.
  group('the meal timings step reads back four answers, not four empty fields', () {
    testWidgets('every slot is a row with its own glyph', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: false,
        insulinOrKidney: false,
        eatingDisorder: false,
      );
      for (final tap in ['Continue', 'Vegetarian', 'Continue']) {
        await tapChoice(tester, tap);
      }

      // Four slots, four rows — the same widget wake and bedtime use one step earlier, so the two
      // halves of "when does your day happen" cannot drift apart visually.
      expect(find.byType(ValueRow), findsNWidgets(4));
      for (final slot in ['Breakfast', 'Lunch', 'Evening snack', 'Dinner']) {
        expect(find.text(slot), findsOneWidget, reason: slot);
      }
    });
  });

  /// D-112 rebuilt the screening step against its reference.
  group('the screening step is three things to answer, not a form', () {
    testWidgets('each question is numbered and carries its own pair of answers', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);

      // Three numbered cards, three Yes/No pairs. The numbers are what say "this is a short set"
      // before any of the questions have been read.
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget, reason: 'question $n is numbered');
      }
      expect(find.text('Yes'), findsNWidgets(3));
      expect(find.text('No'), findsNWidgets(3));
    });

    testWidgets('answering one question leaves the other two alone', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);

      await tester.tap(find.text('Yes').first);
      await tester.pumpAndSettle();

      // Asserted on what the user sees, not on the controller: three identical pairs on one screen
      // is exactly the shape where a shared value or a missed rebuild goes unnoticed.
      expect(isSelected(tester, 'Yes'), isTrue);
      final laterYes = tester
          .widgetList<ChoiceTile>(
            find.ancestor(of: find.text('Yes'), matching: find.byType(ChoiceTile)),
          )
          .toList();
      expect(laterYes[1].selected, isFalse);
      expect(laterYes[2].selected, isFalse);
    });

    testWidgets('and it says what happens to the answers (docs/13)', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);

      await tester.scrollUntilVisible(
        find.textContaining('private and secure'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The most sensitive of the three questions is on this screen, and it was the one step
      // asking a health question that did not carry the note.
      expect(find.textContaining('private and secure'), findsOneWidget);
    });
  });

  group('the conditions step is a checklist, and says so (D-110)', () {
    testWidgets('the multi-select is stated before the first tap', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachConditions(tester);

      // Every other step takes one answer and moves on. Nothing about a list of rows says this one
      // does not, so it is said in words rather than discovered.
      expect(find.text('You can select more than one option'), findsOneWidget);
    });

    testWidgets('every condition carries its own glyph, and "none" carries none', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachConditions(tester);

      IconData? iconOn(String label) => tester
          .widget<ChoiceTile>(
            find.ancestor(of: find.text(label), matching: find.byType(ChoiceTile)).first,
          )
          .icon;

      // Distinct, because the point of them is a list the eye can move through without reading it.
      final icons = ['Type 2 diabetes', 'High blood pressure', 'Kidney disease'].map(iconOn);
      expect(icons.toSet(), hasLength(3));

      // "None of these" is not a condition; a disc on its row would make it look like one.
      expect(iconOn('None of these'), isNull);
    });

    testWidgets('the screen says what happens to the answers (docs/13)', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachConditions(tester);

      await tester.scrollUntilVisible(
        find.textContaining('private and secure'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('private and secure'), findsOneWidget);
    });
  });

  /// D-111 rebuilt the health step against its reference.
  group('the health step says what it wants and what it does not (D-111)', () {
    Future<void> openHealth(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      Get.find<OnboardingController>().step.value = OnboardingStep.health;
      await tester.pumpAndSettle();
    }

    testWidgets('the free-text box is marked optional', (tester) async {
      await openHealth(tester);

      // The subtitle already says the step is skippable, but a text box on a health screen reads
      // as something being demanded, and a user with nothing to type looks for what goes in it.
      expect(find.text('Optional'), findsOneWidget);
    });

    testWidgets('every multi-select group says it takes several answers', (tester) async {
      await openHealth(tester);

      // Defaulted in `_ChoiceGroup`, so a new group cannot forget it: both lists here, and the
      // allergies list on the diet step, say so without any call site opting in.
      expect(find.text('Select all that apply'), findsNWidgets(2));
    });

    testWidgets('the screen says what happens to the answers (docs/13)', (tester) async {
      await openHealth(tester);

      await tester.scrollUntilVisible(
        find.textContaining('private and secure'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('private and secure'), findsOneWidget);
    });
  });

  /// D-112 rebuilt the diet step against its reference.
  group('the diet step asks its own question (D-112)', () {
    Future<void> openDiet(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      Get.find<OnboardingController>().step.value = OnboardingStep.diet;
      await tester.pumpAndSettle();
    }

    testWidgets('the promise is not also the question', (tester) async {
      await openDiet(tester);

      // The bug: the diet group was headed with the STEP's subtitle, so "We only plan food you
      // actually eat." was printed twice — once as the promise, once as the heading — and neither
      // of them asked anything.
      expect(find.text('We only plan food you actually eat.'), findsOneWidget);
      expect(find.text('What best describes your diet?'), findsOneWidget);
    });

    testWidgets('each diet says what it means', (tester) async {
      await openDiet(tester);

      // "Eggetarian" and "Jain" are not words every user knows, and "Vegetarian" means different
      // things to different people. The description is the part that answers "is that me?".
      expect(find.text('No meat, but includes eggs'), findsOneWidget);
      expect(find.text('No onion, garlic or root vegetables'), findsOneWidget);
    });

    testWidgets('the allergies are two-up, and fall back to one column at scale', (tester) async {
      await openDiet(tester);

      // Eleven of them. Two columns is six rows; one is eleven.
      expect(find.byType(IntrinsicHeight), findsWidgets);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: app(),
        ),
      );
      await tester.pumpAndSettle();
      Get.find<OnboardingController>().step.value = OnboardingStep.diet;
      await tester.pumpAndSettle();

      // Rule 12: a two-word label in half a phone at 200 % is three wrapped lines in a cell built
      // for one, so the grid gives way rather than the text.
      expect(find.byType(IntrinsicHeight), findsNothing);
    });
  });

  /// D-113 brought the routine step in line with the rest of the funnel.
  group('the routine step explains its own questions (D-113)', () {
    Future<void> openRoutine(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      Get.find<OnboardingController>().step.value = OnboardingStep.routine;
      await tester.pumpAndSettle();
    }

    testWidgets('a meal count says what the day looks like', (tester) async {
      await openRoutine(tester);

      // "3 meals" / "4 meals" / "5-6 meals" and nothing else made the user guess what the app
      // would do with each.
      expect(find.text('Breakfast, lunch and dinner'), findsOneWidget);
      expect(find.text('Smaller plates, more often'), findsOneWidget);
    });

    testWidgets('neither count nor lifestyle is framed as a discipline (docs/05 §6)', (
      tester,
    ) async {
      await openRoutine(tester);

      // The count is a SHAPE, not a virtue: five small plates and three large ones get the same
      // day's food, and the screen has to say so or the question reads as a judgement.
      expect(find.textContaining('no right answer'), findsOneWidget);
      expect(find.textContaining('not what is in them'), findsOneWidget);
    });

    testWidgets('the budget answer sits on a surface like every other answer', (tester) async {
      await openRoutine(tester);

      await tester.scrollUntilVisible(
        find.byType(Slider),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.ancestor(of: find.byType(Slider), matching: find.byType(AppCard)),
        findsOneWidget,
        reason: 'it was the one question in the funnel whose answer had no card under it',
      );
    });
  });

  group('the healthy weight note (D-76)', () {
    testWidgets('appears only once age, gender, height and weight are all in', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Nothing entered: a prompt, not a number beside a blank form.
      expect(find.textContaining('to see your daily calorie'), findsOneWidget);

      Get.find<OnboardingController>()
        ..setAge(29)
        ..setHeight(170)
        ..setWeight(95);
      await tester.pump();
      await tapChoice(tester, 'Male');

      // 18.5–24.9 at 1.70 m is 53.5–72.0 kg, and 95 kg at 1.70 m is a BMI of 32.9.
      expect(find.textContaining('53.5'), findsOneWidget);
      expect(find.textContaining('72.0'), findsOneWidget);
      expect(find.textContaining('32.9'), findsOneWidget);
    });

    testWidgets('it does not choose the target for them', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      Get.find<OnboardingController>()
        ..setAge(29)
        ..setHeight(170)
        ..setWeight(95);
      await tester.pump();
      await tapChoice(tester, 'Male');

      // The band informs the choice; it must never make it. An auto-filled target is the app
      // setting a target, which is the line CLAUDE.md rule 2 draws.
      final c = Get.find<OnboardingController>();
      expect(c.goalWeightKg.value, isNull);

      c.setGoalWeight(80);
      await tester.pump();
      expect(c.goalWeightKg.value, 80.0, reason: 'and the user can still pick anything legal');
    });

    testWidgets('gender is what it is called on screen', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Sex at birth'), findsNothing);
    });
  });

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

  testWidgets('goal and activity selections update', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillBasics(tester);

    // Past basics, then past the result screen (D-101).
    await tapChoice(tester, 'Continue');
    await tapChoice(tester, 'Continue');
    await tapChoice(tester, 'Weight loss');
    expect(isSelected(tester, 'Weight loss'), isTrue);

    await tapChoice(tester, 'Continue');
    await tapChoice(tester, 'Moderately active');
    expect(isSelected(tester, 'Moderately active'), isTrue);
  });

  testWidgets('conditions multi-select, and "None of these" clears the rest', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await reachConditions(tester);

    // Prediabetes rather than PCOS: this flow selects Male, and PCOS is no longer offered to
    // men (D-89).
    await tapChoice(tester, 'Prediabetes');
    expect(isSelected(tester, 'Prediabetes'), isTrue);

    await tapChoice(tester, 'None of these');
    expect(isSelected(tester, 'None of these'), isTrue);
    expect(isSelected(tester, 'Prediabetes'), isFalse, reason: 'docs/03 §2: none is exclusive');
  });

  testWidgets('a blocking condition ends the flow on the referral screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await reachConditions(tester);

    await tapChoice(tester, 'Kidney disease');
    await tapChoice(tester, 'Continue');

    // docs/05 §3: no plan, and no way to push past it.
    expect(find.textContaining("Let's not plan this on our own"), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  group('docs/05 §4 screening routes to three DIFFERENT screens', () {
    testWidgets('an eating-disorder disclosure gets the support message, not a referral', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: false,
        insulinOrKidney: false,
        eatingDisorder: true,
      );
      await tapChoice(tester, 'Continue');

      // docs/05 §7 verbatim, and it must NOT be the generic referral or the coach-unlock text.
      expect(find.textContaining('not going to set calorie or weight targets'), findsOneWidget);
      expect(find.textContaining("isn't the right tool here"), findsNothing);
      expect(find.textContaining('Your coach can unlock it'), findsNothing);
    });

    testWidgets('insulin or kidney medication is a hard block', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: false,
        insulinOrKidney: true,
        eatingDisorder: false,
      );
      await tapChoice(tester, 'Continue');

      expect(find.textContaining("isn't the right tool here"), findsOneWidget);
    });

    testWidgets('a clinician-prescribed diet routes to the coach unlock', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: true,
        insulinOrKidney: false,
        eatingDisorder: false,
      );
      await tapChoice(tester, 'Continue');

      expect(find.textContaining('Your coach can unlock it'), findsOneWidget);
    });

    testWidgets('an eating-disorder screen cannot be backed out of into the form', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reachScreening(tester);
      await answerScreening(
        tester,
        specialDiet: false,
        insulinOrKidney: false,
        eatingDisorder: true,
      );
      await tapChoice(tester, 'Continue');

      // No enabled action back into a calorie form, and no paywall (docs/05 §6).
      final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
      expect(buttons.every((b) => b.onPressed == null), isTrue);
    });
  });

  testWidgets('the disclaimer appears in the onboarding footer (docs/05 §7)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('is not medical advice'), findsOneWidget);
  });

  testWidgets('PCOS is offered to women only (D-89)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await reachConditions(tester); // fillBasics selects Male

    // Polycystic OVARY Syndrome is not a condition a man can have. Offering it reads as the app
    // not having listened to the answer two screens earlier.
    expect(find.text('PCOS'), findsNothing);
  });

  testWidgets('a woman is offered PCOS (D-89)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Asha');
    await tester.pumpAndSettle();
    Get.find<OnboardingController>()
      ..setAge(29)
      ..setHeight(165)
      ..setWeight(70);
    await tester.pump();
    await tapChoice(tester, 'Female');

    // Two Continues before the goal question — the result screen sits between them (D-101).
    for (final tap in [
      'Continue',
      'Continue',
      'Weight loss',
      'Continue',
      'Moderately active',
      'Continue',
    ]) {
      await tapChoice(tester, tap);
    }
    setTimes(tester);
    await tester.pump();
    await tapChoice(tester, 'Continue');

    expect(find.text('PCOS'), findsOneWidget);
  });

  testWidgets('a selected option keeps its label readable (D-89)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await reachConditions(tester);

    await tapChoice(tester, 'Prediabetes');

    // Settle first: the fill TWEENS now (D-103), so reading it on the frame after the tap catches
    // it mid-way between the two colours and matches neither.
    await tester.pumpAndSettle();

    // The bug D-89 found on the chip this row replaced: the selected fill came from
    // `primaryContainer`, which this scheme never defines, so Material derived a dark one and the
    // dark-green label vanished into it. The row is a different widget; the trap is the same, and
    // it is a trap any future restyle can walk back into.
    final theme = Theme.of(tester.element(find.text('Prediabetes')));
    final tile = tester.widget<AnimatedContainer>(
      find.ancestor(of: find.text('Prediabetes'), matching: find.byType(AnimatedContainer)).last,
    );
    final fill = (tile.decoration! as BoxDecoration).color;

    expect(
      fill,
      isNot(theme.colorScheme.primary),
      reason: 'the label is drawn in primary, so the fill must never be it',
    );
    expect(
      fill,
      isNot(theme.colorScheme.primaryContainer),
      reason: 'D-89: this scheme does not define it, so Material derives a dark one',
    );
  });

  testWidgets('men are never asked about pregnancy (FR-1.3)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await reachConditions(tester); // fillBasics selects Male

    expect(find.text('Pregnant'), findsNothing);
    expect(find.text('Breastfeeding'), findsNothing);
  });

  group('a gate is a dead end (docs/05 §3)', () {
    // Regression: the gate screen's button was wired to `back()`, which returned the user to the
    // screening step. Flipping the answer that caused the gate then walked straight past it.
    for (final gate in [
      (label: 'a blocking condition', tapYes: 1),
      (label: 'a clinician gate', tapYes: 0),
    ]) {
      testWidgets('${gate.label} cannot be backed out of into the form', (tester) async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        final c = Get.find<OnboardingController>()
          ..outcome.value = gate.tapYes == 1 ? GateOutcome.blocked : GateOutcome.clinicianRequired
          ..step.value = OnboardingStep.gate;
        await tester.pumpAndSettle();
        c.back();
        await tester.pumpAndSettle();

        expect(
          c.step.value,
          OnboardingStep.gate,
          reason: 'back() must not leave a gate — the answer could be changed',
        );
      });
    }

    testWidgets('the gate screen offers no route back into the form', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      Get.find<OnboardingController>()
        ..outcome.value = GateOutcome.clinicianRequired
        ..step.value = OnboardingStep.gate;
      await tester.pumpAndSettle();

      // The only action is one that leaves the app, never one that returns to the questions.
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('I understand'), findsNothing);
    });
  });

  /// The reported bug's other half: RootGate routes a session flagged `onboarding_required`
  /// straight to this form, so it can be the first screen a returning user sees. Without a way out
  /// they cannot reach the sign-in screen to try another number.
  group('the wrong account can be left', () {
    testWidgets('step one offers sign out', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Sign out'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(Get.find<SessionController>().status.value, AuthStatus.signedOut);
    });

    testWidgets('later steps do not, where answers would be lost', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      Get.find<OnboardingController>().step.value = OnboardingStep.goal;
      await tester.pumpAndSettle();

      expect(find.text('Sign out'), findsNothing);
    });
  });
}
