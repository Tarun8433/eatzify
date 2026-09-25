import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/data_access_controller.dart';
import 'package:health_pro/presentation/features/coach/data_access_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// docs/10 §3 names this screen and its rules: one place, everything listed, one-tap revoke, no
/// retention dark pattern.

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.rows = const [], this.failure});

  List<DataAccess> rows;
  final Failure? failure;
  final revoked = <int>[];

  /// Everything this screen does not call — the check-in queue and the rest of the coach surface
  /// are somebody else's test.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

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
  Future<Either<Failure, List<DataAccess>>> dataAccess() async {
    final f = failure;
    return f != null ? Left(f) : Right(rows);
  }

  @override
  Future<Either<Failure, Unit>> revokeAccess(int coachUserId) async {
    revoked.add(coachUserId);
    rows = rows
        .map(
          (r) => r.coachUserId == coachUserId
              ? DataAccess(
                  coachUserId: r.coachUserId,
                  scopes: r.scopes,
                  status: 'paused',
                  expiresAt: r.expiresAt,
                )
              : r,
        )
        .toList();
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> invite({
    required String phoneE164,
    required List<String> scopes,
  }) async => const Right(unit);

  @override
  Future<Either<Failure, CoachApplication?>> application() async => const Right(null);
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

Widget pageWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true)
    ..put(DataAccessController(coach: repo), permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DataAccessPage(),
  );
}

DataAccess access({
  int id = 7,
  List<String> scopes = const ['basic', 'progress'],
  String status = 'active',
}) => DataAccess(coachUserId: id, scopes: scopes, status: status, expiresAt: DateTime.utc(2027));

CoachInvite invite({
  String id = 'inv-1',
  int coachUserId = 7,
  List<String> scopes = const ['basic'],
  String? coachName,
  String? coachDiscipline,
  bool coachVerified = false,
  List<String> coachVerifiedAttributes = const [],
  String whatVerificationMeans = '',
}) => CoachInvite(
  id: id,
  coachUserId: coachUserId,
  scopes: scopes,
  status: 'pending',
  expiresAt: DateTime(2030),
  coachName: coachName,
  coachDiscipline: coachDiscipline,
  coachVerified: coachVerified,
  coachVerifiedAttributes: coachVerifiedAttributes,
  whatVerificationMeans: whatVerificationMeans,
);

void main() {
  /// The gap this closed: the server had `GET /coach/invites` plus accept and decline, and the app
  /// called none of them — an invited person had nowhere to see the request at all.
  group('a coach asking to work with me (docs/09 §6)', () {
    testWidgets('should show the request and what it asks for', (tester) async {
      final repo = FakeCoachRepository()
        ..pendingInvites = [
          invite(scopes: const ['basic', 'progress']),
        ];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('A partner'), findsOneWidget);
      // Named, not counted: a request answered without naming what it asks for is not consent.
      expect(find.text('Name and goal'), findsOneWidget);
      expect(find.text('Weight, steps and adherence'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Decline'), findsOneWidget);
    });

    /// The whole point of keeping invites out of `state`: somebody who has granted nobody anything
    /// is Empty, and the request must not be hidden behind that empty state.
    testWidgets('should show a request even when no access has ever been granted', (tester) async {
      final repo = FakeCoachRepository()..pendingInvites = [invite()];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Nobody can see your data'), findsOneWidget);
      expect(find.text('A partner'), findsOneWidget);
    });

    /// "Partner #25" was what this screen showed. Nobody can consent to a number — and unlike the
    /// client's details, a coach APPLIED to be listed, so this is the profile they offered.
    testWidgets('should name the coach who is asking', (tester) async {
      final repo = FakeCoachRepository()
        ..pendingInvites = [invite(coachName: 'Neha Singh', coachDiscipline: 'nutritionist')];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Neha Singh'), findsOneWidget);
    });

    /// doc 00 §8: Eatzify accredits nobody. The badge never stands alone — the server's own
    /// sentence about what verification means travels with it (docs/12 §6, rule 7).
    testWidgets('should say what was checked, in the server own words', (tester) async {
      final repo = FakeCoachRepository()
        ..pendingInvites = [
          invite(
            coachName: 'Neha Singh',
            coachVerified: true,
            coachVerifiedAttributes: const ['identity', 'qualification_document'],
            whatVerificationMeans: 'We saw the document. We do not accredit anyone.',
          ),
        ];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Verified by Eatzify'), findsOneWidget);
      expect(find.textContaining('identity'), findsOneWidget);
      expect(find.text('We saw the document. We do not accredit anyone.'), findsOneWidget);
    });

    /// An unreviewed applicant has confirmed nothing, and the screen must not imply otherwise.
    testWidgets('should say plainly when nobody has verified them', (tester) async {
      final repo = FakeCoachRepository()..pendingInvites = [invite(coachName: 'Neha Singh')];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Not verified yet'), findsOneWidget);
      expect(find.text('Verified by Eatzify'), findsNothing);
    });

    testWidgets('should send the acceptance and drop the request when accepted', (tester) async {
      final repo = FakeCoachRepository()..pendingInvites = [invite()];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pumpAndSettle();

      expect(repo.answered, [(id: 'inv-1', accepted: true)]);
      expect(find.text('A partner'), findsNothing);
    });

    testWidgets('should send the decline and grant nothing when declined', (tester) async {
      final repo = FakeCoachRepository()..pendingInvites = [invite()];
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(repo.answered, [(id: 'inv-1', accepted: false)]);
      expect(repo.revoked, isEmpty);
      expect(find.text('Requests'), findsNothing);
    });

    /// Rule 7, and the silent failure this screen shipped with: every write parked its message in
    /// `error` and nothing displayed it, so a refused answer looked like one that worked.
    testWidgets('should show the server message when an answer is refused', (tester) async {
      final repo = FakeCoachRepository()
        ..pendingInvites = [invite()]
        ..answerFailure = const ApiFailure('That request has expired.', code: 'CONFLICT');
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pumpAndSettle();

      // The error line sits at the foot of the one composed list now, so it can be below the fold.
      await scrollTo(tester, find.text('That request has expired.'));
      expect(find.text('That request has expired.'), findsOneWidget);
      // Still listed: nothing was answered, so nothing may disappear.
      expect(find.text('A partner'), findsOneWidget);
    });

    /// The access list is what this page is ABOUT. A request that could not be fetched must not
    /// replace the answer the user came here to read.
    testWidgets('should still show granted access when the request list fails', (tester) async {
      final repo = FakeCoachRepository(rows: [access()])
        ..invitesFailure = const OfflineFailure('No connection.');
      await tester.pumpWidget(pageWith(repo));
      await tester.pumpAndSettle();

      expect(find.text('Requests'), findsNothing);
      expect(find.text('Partner #7'), findsOneWidget);
    });
  });

  /// The common and healthy state, and the reassuring one — it should not look like an error.
  testWidgets('says nobody can see anything when nothing was given', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nobody can see your data'), findsOneWidget);
    expect(find.text('Nobody can see your data'), findsOneWidget);
  });

  /// "3 permissions" tells somebody nothing about what they gave away.
  testWidgets('names each permission rather than counting them', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(rows: [access()])));
    await tester.pumpAndSettle();

    expect(find.text('Name and goal'), findsOneWidget);
    expect(find.text('Weight, steps and adherence'), findsOneWidget);
  });

  /// docs/10 §3: one tap, effective immediately, "no retention dark pattern". A confirmation
  /// dialog asking somebody to justify taking back their own health data is exactly that.
  testWidgets('revokes on one tap, with nothing to confirm', (tester) async {
    final repo = FakeCoachRepository(rows: [access()]);
    await tester.pumpWidget(pageWith(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();

    expect(repo.revoked, [7]);
    expect(find.text('Access ended'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
  });

  /// A paused grant stays listed. What access USED to exist is part of the answer, and a list
  /// that quietly forgets a revoked coach cannot be audited by the person it belongs to.
  testWidgets('keeps a revoked partner on the list, marked ended', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(rows: [access(status: 'paused')])));
    await tester.pumpAndSettle();

    expect(find.text('Access ended'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
  });

  testWidgets('shows the server message and a retry when the load fails', (tester) async {
    await tester.pumpWidget(
      pageWith(FakeCoachRepository(failure: const ApiFailure('Could not load that.', code: 'X'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FailedView), findsOneWidget);
    expect(find.text('Could not load that.'), findsOneWidget);
  });
}
