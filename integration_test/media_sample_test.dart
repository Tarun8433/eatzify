import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Screenshots of the exercise library and one exercise in full, against an API that is serving
/// exercise media (`GYM_MEDIA_BASE_URL`). A sample for the media decision (D-243) — it is not part
/// of the suite's promises, and it proves nothing about licensing.
const _access = String.fromEnvironment('TEST_ACCESS');
const _refresh = String.fromEnvironment('TEST_REFRESH');
const _user = String.fromEnvironment('TEST_USER');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await binding.takeScreenshot(name);
  }

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
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text(text).first);
    await tester.pump(const Duration(milliseconds: 800));
  }

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

  testWidgets('the library and one exercise, with media served', (tester) async {
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

    app.main();
    await waitFor(tester, find.text("Today's workout"), seconds: 60);
    await dismissHealthPrompt(tester);

    await tapText(tester, 'Open Gym');
    await waitFor(tester, find.text('Exercises'), seconds: 60);
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, 'media_00_today');
    await tapText(tester, 'Exercises');

    // The list: every row carries the still frame where one is served.
    await waitFor(tester, find.text('Create your own exercise'), seconds: 60);
    await tester.pump(const Duration(seconds: 3));
    await shot(tester, 'media_01_library');

    // One exercise in full: the animation, then what it works and how to do it.
    await tester.enterText(find.byType(TextField).first, 'barbell bench press');
    await tester.pump(const Duration(seconds: 2));
    await tapText(tester, 'Barbell Bench Press');
    await waitFor(tester, find.byType(BottomSheet), seconds: 60);
    await tester.pump(const Duration(seconds: 4));
    await shot(tester, 'media_02_detail');
    // Further down the same sheet: what it works, and the steps.
    for (var i = 0; i < 6 && find.text('How to').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, 'media_03_detail_scrolled');
  });
}
