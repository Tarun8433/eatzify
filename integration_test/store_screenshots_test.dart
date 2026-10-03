import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Google Play listing screenshots of the real app (docs/18 §10). Run against a local API seeded
/// with `api/scripts/seed-demo-clients.ts` as a `@demo.eatzify.test` account — synthetic people
/// only, never a real user's diary. Set the emulator to 1080×1920 first (Play caps the long side at
/// twice the short one). Same session hand-in as gym_flow_test.dart.
const _access = String.fromEnvironment('TEST_ACCESS');
const _refresh = String.fromEnvironment('TEST_REFRESH');
const _user = String.fromEnvironment('TEST_USER');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('never appeared: $finder');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    await binding.takeScreenshot(name);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await waitFor(tester, find.text(label));
    // The bar is built last, so its label is the last match on screen.
    await tester.tap(find.text(label).last);
    await settle(tester, 2500);
  }

  Future<void> dismissHealthPrompt(WidgetTester tester) async {
    for (var i = 0; i < 40 && find.text('Not now').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (find.text('Not now').evaluate().isEmpty) return;
    await tester.tap(find.text('Not now').first, warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('Play listing screenshots', (tester) async {
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
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    await waitFor(tester, find.text('Home'), seconds: 60);
    await settle(tester, 4000);
    await dismissHealthPrompt(tester);
    await shot(tester, '01_home');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1100));
    await shot(tester, '02_home_meals');

    await openTab(tester, 'Plan');
    await shot(tester, '03_plan');

    await openTab(tester, 'Progress');
    await shot(tester, '04_progress');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await shot(tester, '05_progress_more');

    await openTab(tester, 'You');
    await shot(tester, '06_you');
  });
}
