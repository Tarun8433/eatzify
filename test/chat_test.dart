import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/chat.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';
import 'package:health_pro/presentation/features/coach/chat_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// docs/02 FR-5.5. The conversation works over REST; the socket only makes it live, so every test
/// here proves the screen without one — and one proves what happens when a message does arrive.

const me = 7;
const coach = 1;

class _FakeChat implements ChatRepository {
  List<ChatMessage> rows = const [];
  List<ChatThread> threadRows = const [];
  Failure? failure;
  Failure? sendFailure;

  /// Holds the read open so a test can see the loading state.
  Completer<void>? hold;

  final sent = <String>[];
  final watched = <int>[];
  int unwatches = 0;
  int readMarks = 0;

  final _live = StreamController<ChatMessage>.broadcast();

  /// Stands in for the socket: a message from the other side, while the screen is open.
  void arrive(ChatMessage message) => _live.add(message);

  @override
  Future<Either<Failure, List<ChatThread>>> threads() async {
    await hold?.future;
    return failure != null ? Left(failure!) : Right(threadRows);
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> messages(int otherUserId, {DateTime? before}) async {
    await hold?.future;
    return failure != null ? Left(failure!) : Right(rows);
  }

  @override
  Future<Either<Failure, ChatMessage>> send(int otherUserId, String body) async {
    sent.add(body);
    if (sendFailure != null) return Left(sendFailure!);
    return Right(
      ChatMessage(
        id: 'm${sent.length}',
        senderUserId: me,
        body: body,
        mine: true,
        createdAt: DateTime(2026, 9, 18, 10),
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> markRead(int otherUserId) async {
    readMarks++;
    return const Right(unit);
  }

  @override
  Stream<ChatMessage> live(int otherUserId) => _live.stream;

  @override
  Future<void> watch(int otherUserId) async => watched.add(otherUserId);

  @override
  Future<void> unwatch() async => unwatches++;
}

ChatMessage message({String id = 'm1', String body = 'How was the week?', bool mine = false}) =>
    ChatMessage(
      id: id,
      senderUserId: mine ? me : coach,
      body: body,
      mine: mine,
      createdAt: DateTime(2026, 9, 18, 9, 30),
    );

void main() {
  late _FakeChat chat;

  setUp(() => chat = _FakeChat());
  tearDown(Get.reset);

  Widget app(Widget home) {
    Get
      ..reset()
      ..put<ChatRepository>(chat, permanent: true);
    return GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }

  Widget thread() => app(const ChatPage(otherUserId: coach, name: 'A. Coach'));

  group('the thread list', () {
    testWidgets('should wait behind a skeleton, then say when there is nobody to talk to', (
      tester,
    ) async {
      chat.hold = Completer<void>();
      await tester.pumpWidget(app(const Scaffold(body: ThreadsView())));
      await tester.pump();
      expect(find.byType(Skeleton), findsOneWidget);

      chat.hold!.complete();
      await settle(tester);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No conversations yet'), findsOneWidget);
    });

    testWidgets('should tell a client and a coach a different reason for the empty list', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Scaffold(body: ThreadsView(asCoach: false))));
      await settle(tester);

      expect(find.textContaining('share chat with a coach'), findsOneWidget);
      // The client waits on a coach's invite; there is nothing for them to press here.
      expect(find.widgetWithText(FilledButton, 'Invite a client'), findsNothing);
    });

    /// D-235: the coach's empty inbox names the path to chat and offers the one action that
    /// starts it, rather than a sentence about a client who has no way to share chat yet.
    testWidgets('should tell a coach how chat opens, and offer the invite', (tester) async {
      await tester.pumpWidget(app(const Scaffold(body: ThreadsView())));
      await settle(tester);

      expect(find.textContaining('Coaching Partner'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Invite a client'), findsOneWidget);
    });

    testWidgets('should show the last message and how many are new', (tester) async {
      chat.threadRows = [
        const ChatThread(
          otherUserId: coach,
          name: 'A. Coach',
          iAmCoach: false,
          lastMessage: 'How was the week?',
          unread: 2,
        ),
      ];
      await tester.pumpWidget(app(const Scaffold(body: ThreadsView())));
      await settle(tester);

      expect(find.text('A. Coach'), findsOneWidget);
      expect(find.text('How was the week?'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      chat.failure = const OfflineFailure('You are offline.');
      await tester.pumpWidget(app(const Scaffold(body: ThreadsView())));
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
    });
  });

  group('one conversation', () {
    testWidgets('should say when nothing has been said yet', (tester) async {
      await tester.pumpWidget(thread());
      await settle(tester);

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('should show what was said, and mark the thread read', (tester) async {
      chat.rows = [message(), message(id: 'm2', body: 'Good, thanks', mine: true)];
      await tester.pumpWidget(thread());
      await settle(tester);

      expect(find.text('How was the week?'), findsOneWidget);
      expect(find.text('Good, thanks'), findsOneWidget);
      expect(chat.readMarks, 1);
      expect(chat.watched, [coach], reason: 'the live connection follows the open thread');
    });

    testWidgets('should send what was typed and show it straight away', (tester) async {
      await tester.pumpWidget(thread());
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Sleeping better this week');
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);

      expect(chat.sent, ['Sleeping better this week']);
      expect(find.text('Sleeping better this week'), findsOneWidget);
    });

    testWidgets('should say why the server refused, and keep the message typed', (tester) async {
      chat.sendFailure = const ApiFailure(
        'This conversation is not open any more.',
        code: 'CHAT_NOT_ALLOWED',
      );
      await tester.pumpWidget(thread());
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Hello?');
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);

      expect(find.text('This conversation is not open any more.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Hello?'), findsOneWidget);
    });

    testWidgets('should show a message that arrives while the thread is open', (tester) async {
      chat.rows = [message()];
      await tester.pumpWidget(thread());
      await settle(tester);

      chat.arrive(message(id: 'm9', body: 'One more thing'));
      await settle(tester);

      expect(find.text('One more thing'), findsOneWidget);
    });

    /// The socket echoes back what was just posted; a conversation that showed everything twice
    /// would be unreadable.
    testWidgets('should not show the same message twice', (tester) async {
      chat.rows = [message()];
      await tester.pumpWidget(thread());
      await settle(tester);

      chat.arrive(message());
      await settle(tester);

      expect(find.text('How was the week?'), findsOneWidget);
    });

    testWidgets('should drop the live connection when the screen goes', (tester) async {
      await tester.pumpWidget(thread());
      await settle(tester);

      // Replaced WITHOUT re-registering: this is the screen going away, not the app restarting.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
      await settle(tester);

      expect(chat.unwatches, 1);
    });

    testWidgets('should survive a 200 % text scale', (tester) async {
      chat.rows = [message(), message(id: 'm2', body: 'Good, thanks', mine: true)];
      await tester.pumpWidget(
        app(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ChatPage(otherUserId: coach, name: 'A. Coach'),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
