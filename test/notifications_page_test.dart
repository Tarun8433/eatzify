import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/app_notification.dart';
import 'package:health_pro/presentation/features/account/notifications_controller.dart';
import 'package:health_pro/presentation/features/account/notifications_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// docs/14 §6. The server's messages, in a list that says which are new.

AppNotification notice({String id = 'n1', bool unread = true}) => AppNotification(
  id: id,
  kind: 'renewal_t7',
  contentClass: 'service',
  title: 'Your plan renews on 24 September',
  body: '₹999 will be charged on 24 September.',
  readAt: unread ? null : DateTime(2026, 9, 17),
  createdAt: DateTime(2026, 9, 17, 9, 30),
);

void main() {
  late FakeNotificationsRepository repo;

  setUp(() => repo = FakeNotificationsRepository());
  tearDown(Get.reset);

  Widget page({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put(NotificationsController(notifications: repo));
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
        child: const NotificationsPage(),
      ),
    );
  }

  group('the four states', () {
    testWidgets('should wait behind a skeleton while the list loads', (tester) async {
      repo.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);

      repo.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should say there is nothing to read rather than show an empty list', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Nothing to read'), findsOneWidget);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      repo = FakeNotificationsRepository(failure: const OfflineFailure('You are offline.'));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });

    testWidgets('should show the message, when it arrived, and that it is new', (tester) async {
      repo = FakeNotificationsRepository(feedResult: Right((items: [notice()], unreadCount: 1)));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Your plan renews on 24 September'), findsOneWidget);
      expect(find.text('₹999 will be charged on 24 September.'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget, reason: 'the unread dot');
    });
  });

  testWidgets('should mark one read when it is opened, and drop the dot', (tester) async {
    repo = FakeNotificationsRepository(feedResult: Right((items: [notice()], unreadCount: 1)));
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.byType(AppCard).first);
    await settle(tester);

    expect(repo.readIds, ['n1']);
    expect(find.byIcon(Icons.circle), findsNothing);
    expect(Get.find<NotificationsController>().unread.value, 0);
  });

  testWidgets('should offer "mark all read" only while something is unread', (tester) async {
    repo = FakeNotificationsRepository(
      feedResult: Right((
        items: [
          notice(),
          notice(id: 'n2', unread: false),
        ],
        unreadCount: 1,
      )),
    );
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.text('Mark all read'));
    await settle(tester);

    expect(repo.readAllCalls, 1);
    expect(find.text('Mark all read'), findsNothing);
    expect(find.byIcon(Icons.circle), findsNothing);
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    repo = FakeNotificationsRepository(feedResult: Right((items: [notice()], unreadCount: 1)));
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
