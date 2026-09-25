import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/privacy.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';
import 'package:health_pro/presentation/features/account/privacy_controller.dart';
import 'package:health_pro/presentation/features/account/privacy_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// docs/13 §3 and §9: the consents, the copy, and the way out — on one screen, with no dark
/// patterns and nothing rendered as a raw key.

/// The screen is a list and the interesting parts are below the fold, exactly as they are on a
/// phone. Scrolling to them is part of what the test is checking.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

void main() {
  late FakePrivacyRepository repo;

  setUp(() => repo = FakePrivacyRepository());
  tearDown(Get.reset);

  Widget page({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put<PrivacyRepository>(repo)
      ..put(PrivacyController(privacy: repo));

    return GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(data: MediaQueryData(textScaler: scaler), child: const PrivacyPage()),
    );
  }

  group('the states', () {
    testWidgets('should wait behind a skeleton while it loads', (tester) async {
      repo.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);

      repo.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      repo = FakePrivacyRepository(failure: const OfflineFailure('You are offline.'));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });
  });

  group('consent (docs/13 §3)', () {
    testWidgets('should name each permission in words, never as a key', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Store my health data'), findsOneWidget);
      expect(find.text('Offers and updates'), findsOneWidget);
      expect(find.text('health_data_storage'), findsNothing);
      expect(find.text('marketing'), findsNothing);
    });

    /// "No pre-ticked optional boxes."
    testWidgets('should show marketing off by default', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.last.value, isFalse);
    });

    testWidgets('should send a withdrawal when a toggle is turned off', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.byType(Switch).first);
      await settle(tester);

      expect(repo.setCalls, [(type: 'health_data_storage', granted: false)]);
      expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isFalse);
    });

    /// Rule 7: the server's own words when it refuses.
    testWidgets('should show the server refusal verbatim', (tester) async {
      repo = FakePrivacyRepository(
        actionFailure: const ApiFailure('We could not save that.', code: 'BAD'),
      );
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.byType(Switch).first);
      await settle(tester);

      await reveal(tester, find.text('We could not save that.'));
      expect(find.text('We could not save that.'), findsOneWidget);
    });
  });

  group('the right to a copy (docs/13 §9)', () {
    testWidgets('should build a copy and say what it holds', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      await reveal(tester, find.text('Build my copy'));
      await tester.tap(find.text('Build my copy'));
      await settle(tester);

      expect(repo.exports, 1);
      await reveal(tester, find.text('Your copy is ready.'));
      expect(find.text('Your copy is ready.'), findsOneWidget);
      expect(find.text('food_logs: 3 rows'), findsOneWidget);
    });
  });

  group('the right to leave (docs/13 §9)', () {
    testWidgets('should ask once, then schedule it', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      await reveal(tester, find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);

      // One confirmation — docs/13 §3 rules out asking again with guilt copy.
      expect(find.text('Delete your account?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(repo.deletions, 1);
      expect(find.text('Keep my account'), findsOneWidget);
    });

    testWidgets('should do nothing when the confirmation is declined', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      await reveal(tester, find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);

      expect(repo.deletions, 0);
    });

    testWidgets('should offer a way back while it is pending', (tester) async {
      repo = FakePrivacyRepository(
        requests: [
          PrivacyRequest(
            id: 'd1',
            kind: 'delete',
            status: 'pending',
            executeAfter: DateTime(2026, 9, 25),
          ),
        ],
      );
      await tester.pumpWidget(page());
      await settle(tester);

      await reveal(tester, find.textContaining('Scheduled for'));
      expect(find.textContaining('Scheduled for'), findsOneWidget);

      await tester.tap(find.text('Keep my account'));
      await settle(tester);

      expect(repo.cancellations, 1);
    });
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
