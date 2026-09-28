import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';
import 'package:health_pro/presentation/features/account/tickets_controller.dart';
import 'package:health_pro/presentation/features/account/tickets_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// docs/14 §6's help screen, and docs/03 §5's states rendered as words rather than as the enum.

SupportTicket ticket({String id = 't1', String status = 'open'}) => SupportTicket(
  id: id,
  subject: 'Charged twice for September',
  status: status,
  lastMessageAt: DateTime(2026, 9, 17, 9, 30),
  createdAt: DateTime(2026, 9, 16, 9, 30),
);

void main() {
  late FakeTicketsRepository repo;

  setUp(() => repo = FakeTicketsRepository());
  tearDown(Get.reset);

  Widget app(Widget home, {TextScaler scaler = TextScaler.noScaling}) => GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(data: MediaQueryData(textScaler: scaler), child: home),
  );

  Widget page({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put<TicketsRepository>(repo)
      ..put(TicketsController(tickets: repo));
    return app(const TicketsPage(), scaler: scaler);
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

    testWidgets('should offer a way to write rather than show an empty list', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Nothing open'), findsOneWidget);
      // An empty state with one clear action (ui-standards).
      expect(find.widgetWithText(FilledButton, 'Ask for help'), findsOneWidget);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      repo = FakeTicketsRepository(failure: const OfflineFailure('You are offline.'));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });

    testWidgets('should list a conversation with its state in words', (tester) async {
      repo = FakeTicketsRepository(tickets: [ticket()]);
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Charged twice for September'), findsOneWidget);
      // Rule 4: never `open`, never `waiting_user`.
      expect(find.text('With support'), findsOneWidget);
      expect(find.text('open'), findsNothing);
    });
  });

  testWidgets('should say when the ball is with the reader', (tester) async {
    repo = FakeTicketsRepository(tickets: [ticket(status: 'waiting_user')]);
    await tester.pumpWidget(page());
    await settle(tester);

    expect(find.text('Waiting for you'), findsOneWidget);
  });

  testWidgets('should open a conversation from the sheet it was written in', (tester) async {
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Ask for help'));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Charged twice');
    await tester.enterText(find.byType(TextField).last, 'It went out of my account twice.');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await settle(tester);

    expect(repo.opened, ['Charged twice']);
  });

  /// Rule 7: the server's own words, not copy written here.
  testWidgets('should show the server refusal verbatim', (tester) async {
    repo = FakeTicketsRepository(
      openFailure: const ApiFailure(
        'You already have several conversations open with us.',
        code: 'TOO_MANY_TICKETS',
      ),
    );
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Ask for help'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'One more');
    await tester.enterText(find.byType(TextField).last, 'Please help');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await settle(tester);

    expect(find.text('You already have several conversations open with us.'), findsOneWidget);
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    repo = FakeTicketsRepository(tickets: [ticket()]);
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  group('one conversation', () {
    Widget thread({String status = 'open', TextScaler scaler = TextScaler.noScaling}) {
      final only = ticket(status: status);
      repo = FakeTicketsRepository(
        tickets: [only],
        threadResult: (
          ticket: only,
          messages: [
            SupportMessage(
              id: 'm1',
              body: 'It went out of my account twice.',
              fromSupport: false,
              createdAt: DateTime(2026, 9, 16, 9, 30),
            ),
            SupportMessage(
              id: 'm2',
              body: 'We are checking with the bank.',
              fromSupport: true,
              createdAt: DateTime(2026, 9, 17, 9, 30),
            ),
          ],
        ),
      );
      Get
        ..reset()
        ..put<TicketsRepository>(repo)
        ..put(TicketThreadController(tickets: repo, ticketId: only.id));
      return app(TicketThreadPage(ticket: only), scaler: scaler);
    }

    testWidgets('should show both sides and say which is which', (tester) async {
      await tester.pumpWidget(thread());
      await settle(tester);

      expect(find.text('It went out of my account twice.'), findsOneWidget);
      expect(find.text('We are checking with the bank.'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byType(AppCard), findsNWidgets(2));
    });

    testWidgets('should send a reply and clear the box', (tester) async {
      await tester.pumpWidget(thread());
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Any news?');
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);

      expect(repo.replies, ['Any news?']);
      expect(find.text('Any news?'), findsNothing);
    });

    testWidgets('should hide the box on a closed conversation and say why', (tester) async {
      await tester.pumpWidget(thread(status: 'closed'));
      await settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('This conversation is closed. Start a new one and we will pick it up.'),
        findsOneWidget,
      );
    });

    testWidgets('should survive a 200 % text scale', (tester) async {
      await tester.pumpWidget(thread(scaler: const TextScaler.linear(2)));
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
