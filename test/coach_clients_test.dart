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
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/coach_shell.dart';

import 'pumping.dart';

/// The coach's Clients tab. It answers one question — what have I asked, and has anyone replied?
///
/// It is NOT a client list: an open invite is not a client, and docs/10 §1 keeps those apart
/// ("the level does not grant access. The consent grant does").

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.rows = const [], this.roster = const [], this.failure});

  final List<SentInvite> rows;
  final List<CoachClient> roster;
  final Failure? failure;

  @override
  Future<Either<Failure, List<SentInvite>>> sentInvites() async =>
      failure != null ? Left(failure!) : Right(rows);

  @override
  Future<Either<Failure, List<CoachClient>>> clients() async =>
      failure != null ? Left(failure!) : Right(roster);

  @override
  Future<Either<Failure, CoachClientDetail>> client(int id) => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication?>> application() => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline d) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication>> acceptAgreement(String v) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, String>> uploadDocument(String p, String n) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachApplication>> submit() => throw UnimplementedError();

  @override
  Future<Either<Failure, List<CoachInvite>>> invites() => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> acceptInvite(String id) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> declineInvite(String id) => throw UnimplementedError();

  /// The counts the tab draws above the list. Derived from the same fixtures as the roster, the way
  /// the server derives them from the same rows — a tile that disagreed with the list under it
  /// would be a bug the test could not see.
  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, CoachDashboard>> dashboard() async => failure != null
      ? Left(failure!)
      : Right(
          CoachDashboard(
            totalClients: roster.length,
            activeClients: roster.where((c) => c.status == 'active').length,
            atRiskClients: roster.where((c) => c.status != null && c.status != 'active').length,
            pendingInvites: rows.length,
            renewalsDue30d: 0,
            needsAttention: roster.where((c) => c.status != null && c.status != 'active').toList(),
          ),
        );

  /// Absent rather than failing. A partner whose ledger is unreachable still has a client list.
  @override
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) async =>
      const Left(ApiFailure('no ledger', code: 'X', status: 404));

  @override
  Future<Either<Failure, CoachReferral>> referral() async =>
      const Left(ApiFailure('no code', code: 'X', status: 404));

  @override
  Future<Either<Failure, List<DataAccess>>> dataAccess() => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> revokeAccess(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> invite({required String phoneE164, required List<String> scopes}) =>
      throw UnimplementedError();
}

SentInvite sent({String? name, String? photoUrl, String phone = '+918433145573'}) => SentInvite(
  id: 'i1',
  phoneE164: phone,
  scopes: const ['basic', 'progress'],
  status: 'pending',
  expiresAt: DateTime(2026, 10, 15),
  createdAt: DateTime(2026, 9, 15),
  name: name,
  photoUrl: photoUrl,
);

Widget shellWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const CoachShell(),
  );
}

void main() {
  /// Clients above invites: an answered question outranks an open one, and a coach opening this
  /// tab wants who they HAVE before who they asked.
  testWidgets('should list accepted clients and what they allowed', (tester) async {
    await tester.pumpWidget(
      shellWith(
        FakeCoachRepository(
          roster: [
            const CoachClient(userId: 9, name: 'Asha Rao', scopes: ['basic', 'progress']),
          ],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Asha Rao'), findsOneWidget);
    // Named, not counted — the same words the client read when they granted it.
    expect(find.textContaining('Name and goal'), findsOneWidget);
  });

  /// The bug this closed: two invites sent, and the tab still said "your clients will appear here
  /// once a client accepts" — the coach could not tell whether anything had been sent at all.
  testWidgets('should list an invite the coach has sent', (tester) async {
    await tester.pumpWidget(shellWith(FakeCoachRepository(rows: [sent()])));
    await settle(tester);

    expect(find.text('Waiting for a reply'), findsOneWidget);
    expect(find.text('+91 84331 45573'), findsOneWidget);
  });

  /// Invites were stored with whatever the coach typed until the number was normalised, so one
  /// person could hold two pending rows — `8433145573` and `+918433145573` sat on this screen
  /// looking like two different invitees.
  testWidgets('should show one row per person, not one per stored row', (tester) async {
    await tester.pumpWidget(
      shellWith(
        FakeCoachRepository(
          rows: [
            sent(phone: '8433145573'),
            sent(),
          ],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('+91 84331 45573'), findsOneWidget);
  });

  testWidgets('should show the name when the number belongs to an account', (tester) async {
    await tester.pumpWidget(shellWith(FakeCoachRepository(rows: [sent(name: 'Asha Rao')])));
    await settle(tester);

    expect(find.text('Asha Rao'), findsOneWidget);
    // The number stays beside the name — it is what the coach typed and what they recognise.
    expect(find.text('+91 84331 45573'), findsOneWidget);
  });

  /// No name means the number is not on the app, or nobody has given one. A placeholder name would
  /// be a claim about somebody who may not have an account at all.
  testWidgets('should say plainly when the number is not on the app', (tester) async {
    await tester.pumpWidget(shellWith(FakeCoachRepository(rows: [sent()])));
    await settle(tester);

    expect(find.text('Not on Eatzify yet'), findsOneWidget);
  });

  testWidgets('should tell the coach when the invite runs out', (tester) async {
    await tester.pumpWidget(shellWith(FakeCoachRepository(rows: [sent()])));
    await settle(tester);

    expect(find.textContaining('Expires'), findsOneWidget);
  });

  /// Nobody asked yet: the ordinary state for a new coach, and docs/14 §6 wants one clear action.
  testWidgets('should offer to invite somebody when nothing has been sent', (tester) async {
    await tester.pumpWidget(shellWith(FakeCoachRepository()));
    await settle(tester);

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('Invite a client'), findsOneWidget);
  });

  testWidgets('should show the server message and a retry when the list fails', (tester) async {
    await tester.pumpWidget(
      shellWith(FakeCoachRepository(failure: const ApiFailure('Could not load that.', code: 'X'))),
    );
    await settle(tester);

    expect(find.byType(FailedView), findsOneWidget);
    expect(find.text('Could not load that.'), findsOneWidget);
  });
}
