import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// The Gym journey on a real device against a real API (ADR-013): load a plan, move today's
/// workout, weigh in, log sets with rest between them, finish, and see the energy estimate reach
/// the summary, the Gym and Home. Run with `flutter drive` — see plan.md, Phase 11.
///
/// A signed-in session is handed in by dart-define (a synthetic test account; no real number), so
/// the journey starts on Home rather than at the OTP screen, which has its own tests.
const _access = String.fromEnvironment('TEST_ACCESS');
const _refresh = String.fromEnvironment('TEST_REFRESH');
const _user = String.fromEnvironment('TEST_USER');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await binding.takeScreenshot(name);
  }

  /// Pumps until [finder] shows, for as long as a real network round trip may take.
  Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('never appeared: $finder');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await waitFor(tester, find.text(text));
    await tester.ensureVisible(find.text(text).first);
    // Let whatever is moving finish: a tap aimed mid-animation lands where the widget no longer is.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text(text).first);
    await tester.pump(const Duration(milliseconds: 800));
  }

  /// Drags the current list until [text] is built — a long screen keeps what is below the fold out
  /// of the tree entirely, so "not found" can just mean "not scrolled to".
  Future<void> scrollToText(WidgetTester tester, String text) async {
    for (var i = 0; i < 20 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// The one-time "connect your health app" sheet. It arrives a moment after Home and holds a
  /// barrier over everything, so the journey waits for it and makes sure it has gone.
  Future<void> dismissHealthPrompt(WidgetTester tester) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      for (var i = 0; i < 40 && find.text('Not now').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      if (find.text('Not now').evaluate().isEmpty) return;
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Not now').first, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Not now').evaluate().isEmpty) return;
    }
  }

  testWidgets('the Gym, start to finish', (tester) async {
    expect(_access, isNotEmpty, reason: 'pass --dart-define=TEST_ACCESS=…');
    final store = SecureStore();
    await store.clear();
    await store.save(
      const Session(
        accessToken: _access,
        refreshToken: _refresh,
        userId: _user,
        roles: ['client'],
        onboardingRequired: false,
      ),
    );
    await store.markIntroSeen();
    // Semantics labels are how a set's value boxes are found. The handle is released at the end of
    // the body: flutter_test checks for leaked handles before tearDowns run.
    final semantics = SemanticsBinding.instance.ensureSemantics();

    app.main();

    // Home, with the one-time "connect your health app" offer set aside — it arrives a moment
    // after Home does, so wait for it rather than glance once.
    await waitFor(tester, find.text("Today's workout"), seconds: 60);
    await dismissHealthPrompt(tester);
    await tester.ensureVisible(find.textContaining('Calorie summary'));
    await shot(tester, '01_home_calorie_card_before');
    await tester.ensureVisible(find.text("Today's workout"));
    await shot(tester, '02_home_workout_card');

    // The hub. An account with no plan gets the welcome card: load the starter plan from it.
    await tapText(tester, 'Open Gym');
    bool hubShown() =>
        find.text('This week').evaluate().isNotEmpty ||
        find.text('Build your training week').evaluate().isNotEmpty;
    for (var i = 0; i < 120 && !hubShown(); i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (find.text('Build your training week').evaluate().isNotEmpty) {
      await shot(tester, '03a_gym_welcome');
      await tapText(tester, 'Load a starter plan');
    }
    await waitFor(tester, find.text('This week'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '03_gym_today');

    // The plan: a weekly schedule and three routines.
    await tapText(tester, 'Routines');
    await waitFor(tester, find.text('Weekly schedule'));
    await shot(tester, '04_routines_tab');
    await tapText(tester, 'Today');
    await tester.pump(const Duration(seconds: 1));

    // Start from the Today card: its one action either starts what is planned or opens the
    // chooser. Push Day is picked deliberately, so the journey logs the same workout every run.
    await tapText(
      tester,
      find.text('Start Workout').evaluate().isNotEmpty ? 'Start Workout' : 'Start a workout',
    );
    await waitFor(tester, find.text('Quick check-in'));
    await shot(tester, '05_weigh_in');
    await tapText(tester, 'Choose a different workout');
    final pushInSheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Push Day'),
    );
    await waitFor(tester, pushInSheet);
    await tester.tap(pushInSheet.first);
    await tester.pump(const Duration(milliseconds: 600));
    await waitFor(tester, find.text('Quick check-in'));
    await tapText(tester, 'Save and start');

    // The workout: the bench press, its reason, its sets.
    await waitFor(tester, find.text('Barbell Bench Press'));
    await shot(tester, '06_workout_first_exercise');

    // Load the first set: tap its weight, add 20 kg, done.
    await tester.tap(find.bySemanticsLabel(RegExp('Edit kg')).first);
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('+2.5').last);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.text('Done').last);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('Mark set 1 done'));
    await tester.pump(const Duration(seconds: 1));
    await waitFor(tester, find.text('Skip'));
    await shot(tester, '07_rest_timer');
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 500));

    for (final n in [2, 3, 4]) {
      await tester.ensureVisible(find.byTooltip('Mark set $n done'));
      await tester.tap(find.byTooltip('Mark set $n done'));
      await tester.pump(const Duration(milliseconds: 600));
      if (find.text('Skip').evaluate().isNotEmpty) {
        await tester.tap(find.text('Skip'));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }
    await waitFor(tester, find.text('Working weight'));
    await shot(tester, '08_working_weight');
    await tapText(tester, 'Save and next exercise');
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '09_next_exercise');

    // Finish early: the summary is the server's own account, energy included.
    await tester.tap(find.byTooltip('Finish workout'));
    await tester.pump(const Duration(milliseconds: 600));
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Finish workout'),
    );
    await waitFor(tester, confirm);
    await tester.tap(confirm);
    await tester.pump(const Duration(milliseconds: 600));
    await waitFor(tester, find.text('Workout complete!'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '10_summary');
    await scrollToText(tester, 'Nice!');
    await tapText(tester, 'Nice!');

    // Back in the Gym: the energy card and the stats.
    await waitFor(tester, find.text('Workout energy'));
    await tester.ensureVisible(find.text('Workout energy'));
    await shot(tester, '11_gym_energy_card');

    // Home: the workout's energy as its own line on the calorie card. Checked here, from the Gym's
    // own route, rather than after the exercise sheet — a sheet cannot be popped with a back button.
    await tester.pageBack();
    await waitFor(tester, find.text("Today's workout"));
    await scrollToText(tester, 'Workouts · ~');
    await waitFor(tester, find.textContaining('Workouts · ~'));
    await tester.ensureVisible(find.textContaining('Workouts · ~'));
    await shot(tester, '16_home_calorie_card_after');

    await tapText(tester, 'Open Gym');
    await waitFor(tester, find.text('This week'), seconds: 60);
    await tapText(tester, 'Stats');
    await scrollToText(tester, 'Muscle balance');
    await waitFor(tester, find.text('Muscle balance'));
    await shot(tester, '12_stats_top');
    await tester.ensureVisible(find.text('Muscle balance'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '13_stats_muscle_map');

    // The library and one exercise in full.
    await tapText(tester, 'Exercises');
    await waitFor(tester, find.text('Create your own exercise'));
    await shot(tester, '14_exercise_library');
    await tester.enterText(find.byType(TextField).first, 'bench press');
    await tester.pump(const Duration(seconds: 1));
    await tapText(tester, 'Barbell Bench Press');
    await waitFor(tester, find.byType(BottomSheet));
    await scrollToText(tester, 'How to');
    await waitFor(tester, find.text('How to'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '15_exercise_detail');

    semantics.dispose();
  });
}
