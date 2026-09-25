import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/invite_client_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// docs/09 §6 and docs/10 §3. An invite is an ASK. The screen must not promise otherwise, and it
/// must not report back whether the number has an account (docs/09 §3).

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.failure, this.level});

  final Failure? failure;

  /// The coach's partner level, as `application()` reports it. Null means "not a partner" — which
  /// is what every older case in this file assumed.
  final int? level;
  final sent = <({String phone, List<String> scopes})>[];

  @override
  Future<Either<Failure, Unit>> invite({
    required String phoneE164,
    required List<String> scopes,
  }) async {
    sent.add((phone: phoneE164, scopes: scopes));
    final f = failure;
    return f != null ? Left(f) : const Right(unit);
  }

  /// Everything this screen does not call. The invite sheet is about one endpoint; the rest of the
  /// coach surface is somebody else's test.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication?>> application() async {
    final l = level;
    if (l == null) return const Right(null);
    return Right(
      CoachApplication(
        status: 'verified',
        level: l,
        agreementAccepted: true,
        hasIdDocument: true,
        hasQualificationDocument: true,
        whatVerificationMeans: '',
        coachingAgreementAccepted: l >= 3,
      ),
    );
  }
  @override
  Future<Either<Failure, CoachApplication>> acceptAgreement(String v) async =>
      throw UnimplementedError();
  @override
  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  }) async => throw UnimplementedError();
  @override
  Future<Either<Failure, String>> uploadDocument(String p, String n) async =>
      throw UnimplementedError();
  @override
  Future<Either<Failure, CoachApplication>> submit() async => throw UnimplementedError();
  @override
  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline discipline) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<CoachClient>>> clients() async => const Right([]);

  @override
  Future<Either<Failure, CoachClientDetail>> client(int clientUserId) => throw UnimplementedError();

  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, CoachDashboard>> dashboard() => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachReferral>> referral() => throw UnimplementedError();

  @override
  Future<Either<Failure, List<DataAccess>>> dataAccess() async => const Right([]);
  @override
  Future<Either<Failure, Unit>> revokeAccess(int id) async => const Right(unit);

  /// Pending invites this fake was seeded with, plus what was answered — so a test can tell "the
  /// screen sent the answer" from "the screen redrew itself".
  List<CoachInvite> pendingInvites = const [];
  final answered = <({String id, bool accepted})>[];

  @override
  Future<Either<Failure, List<CoachInvite>>> invites() async =>
      invitesFailure != null ? Left(invitesFailure!) : Right(pendingInvites);

  Failure? invitesFailure;

  @override
  Future<Either<Failure, Unit>> acceptInvite(String inviteId) async {
    answered.add((id: inviteId, accepted: true));
    if (answerFailure != null) return Left(answerFailure!);
    pendingInvites = pendingInvites.where((i) => i.id != inviteId).toList();
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> declineInvite(String inviteId) async {
    answered.add((id: inviteId, accepted: false));
    if (answerFailure != null) return Left(answerFailure!);
    pendingInvites = pendingInvites.where((i) => i.id != inviteId).toList();
    return const Right(unit);
  }

  Failure? answerFailure;

  @override
  Future<Either<Failure, List<SentInvite>>> sentInvites() async =>
      sentInvitesFailure != null ? Left(sentInvitesFailure!) : Right(sentInvitesRows);

  List<SentInvite> sentInvitesRows = const [];
  Failure? sentInvitesFailure;
}

Future<void> openSheet(WidgetTester tester, FakeCoachRepository repo) async {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => InviteClientSheet.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  /// Nothing can be asked of nobody.
  testWidgets('cannot send without a number', (tester) async {
    await openSheet(tester, FakeCoachRepository());

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send invitation'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('sends the number and the scopes asked for', (tester) async {
    final repo = FakeCoachRepository();
    await openSheet(tester, repo);

    await tester.enterText(find.byType(TextField), '+919000000001');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(repo.sent.single.phone, '+919000000001');
    expect(repo.sent.single.scopes, ['basic', 'progress']);
  });

  /// The bug that made the whole invite flow invisible: this sheet sent the field's raw text,
  /// sign-in stores `+91` + digits, and the server matches the two by EXACT equality. A coach
  /// typing the number the normal way wrote an invite the client could never be shown.
  testWidgets('should send a bare local number in the form sign-in stores', (tester) async {
    final repo = FakeCoachRepository();
    await openSheet(tester, repo);

    await tester.enterText(find.byType(TextField), '8433145573');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(repo.sent.single.phone, '+918433145573');
  });

  /// docs/10 §3: a coach may request a scope; only the client grants it. A sheet that read like
  /// "add client" would promise something the server will not do.
  testWidgets('says plainly that nothing is shared until they accept', (tester) async {
    await openSheet(tester, FakeCoachRepository());

    expect(find.textContaining('until they accept'), findsOneWidget);
  });

  /// docs/09 §3: never reveal whether a number exists. The confirmation must not say the person
  /// was found, only that the invitation was sent.
  testWidgets('confirms sending without confirming who received it', (tester) async {
    await openSheet(tester, FakeCoachRepository());

    await tester.enterText(find.byType(TextField), '+919000000001');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(find.text('Invitation sent'), findsOneWidget);
    expect(find.textContaining('If they use Eatzify'), findsOneWidget);
  });

  /// Rule 7: the server's own words, verbatim.
  testWidgets('shows the server message when the invite is refused', (tester) async {
    await openSheet(
      tester,
      FakeCoachRepository(failure: const ApiFailure('That partner is not verified.', code: 'X')),
    );

    await tester.enterText(find.byType(TextField), '+919000000001');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(find.text('That partner is not verified.'), findsOneWidget);
    expect(find.text('Invitation sent'), findsNothing);
  });

  /// docs/10 §1: chat is level 3's. The sheet offers it to a Coaching Partner and to nobody else,
  /// because a scope that comes back refused teaches people to distrust the form (D-235).
  group('asking for chat', () {
    testWidgets('should not offer chat below Coaching Partner', (tester) async {
      await openSheet(tester, FakeCoachRepository(level: 2));

      expect(find.text('Can message you'), findsNothing);
    });

    testWidgets('should offer chat to a Coaching Partner, unticked', (tester) async {
      await openSheet(tester, FakeCoachRepository(level: 3));

      final chat = find.widgetWithText(CheckboxListTile, 'Can message you');
      expect(chat, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(chat).value, isFalse);
    });

    testWidgets('should send chat when it is ticked', (tester) async {
      final repo = FakeCoachRepository(level: 3);
      await openSheet(tester, repo);

      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.text('Can message you'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();

      expect(repo.sent.single.scopes, containsAll(['basic', 'progress', 'chat']));
    });
  });
}
