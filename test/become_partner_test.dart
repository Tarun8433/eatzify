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
import 'package:health_pro/presentation/features/coach/become_partner_controller.dart';
import 'package:health_pro/presentation/features/coach/become_partner_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// docs/12 §6. The screen may carry an applicant to `submitted` and no further — verification is
/// an admin decision (docs/09 §9), and a surface that implied otherwise would be claiming an
/// accreditation Eatzify does not make (doc 00 §8).

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.current, this.failure});

  final CoachApplication? current;
  final Failure? failure;
  int submitCalls = 0;

  /// Everything the application flow does not call. The client surface and the check-in queue are
  /// somebody else's test.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  /// What the fake was asked to record, so a test can tell "the screen sent the answer" from
  /// "the screen redrew itself".
  CoachDiscipline? picked;

  /// See the profile fake: a pull that redraws without re-fetching is not a refresh.
  int applicationCalls = 0;

  @override
  Future<Either<Failure, CoachApplication?>> application() async {
    applicationCalls++;
    final f = failure;
    return f != null ? Left(f) : Right(current);
  }

  @override
  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline discipline) async {
    picked = discipline;
    return Right(
      CoachApplication(
        status: _accepted.status,
        level: _accepted.level,
        discipline: discipline,
        agreementAccepted: _accepted.agreementAccepted,
        hasIdDocument: _accepted.hasIdDocument,
        hasQualificationDocument: _accepted.hasQualificationDocument,
        whatVerificationMeans: _accepted.whatVerificationMeans,
      ),
    );
  }

  @override
  Future<Either<Failure, CoachApplication>> acceptAgreement(String version) async =>
      const Right(_accepted);

  @override
  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  }) async => const Right(_accepted);

  @override
  Future<Either<Failure, Unit>> invite({
    required String phoneE164,
    required List<String> scopes,
  }) async => const Right(unit);

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
  Future<Either<Failure, Unit>> revokeAccess(int coachUserId) async => const Right(unit);

  @override
  Future<Either<Failure, String>> uploadDocument(String filePath, String fileName) async =>
      const Right('file-1');

  @override
  Future<Either<Failure, CoachApplication>> submit() async {
    submitCalls += 1;
    return const Right(_submitted);
  }

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

const _accepted = CoachApplication(
  status: 'draft',
  level: 1,
  agreementAccepted: true,
  hasIdDocument: false,
  hasQualificationDocument: false,
  whatVerificationMeans: 'We have checked identity only.',
);

const _submitted = CoachApplication(
  status: 'submitted',
  level: 1,
  agreementAccepted: true,
  hasIdDocument: true,
  hasQualificationDocument: true,
  whatVerificationMeans: 'We have checked identity only.',
);

const _verified = CoachApplication(
  status: 'verified',
  level: 2,
  agreementAccepted: true,
  hasIdDocument: true,
  hasQualificationDocument: true,
  whatVerificationMeans: 'We have checked identity only.',
);

Widget pageWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true)
    ..put(BecomePartnerController(coach: repo), permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const BecomePartnerPage(),
  );
}

void main() {
  /// Never having applied is the common case, not an error.
  testWidgets('offers to start when the account has never applied', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Accept agreement'), findsOneWidget);
  });

  testWidgets('shows the server message and a retry when the load fails', (tester) async {
    await tester.pumpWidget(
      pageWith(FakeCoachRepository(failure: const ApiFailure('Could not load that.', code: 'X'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FailedView), findsOneWidget);
    expect(find.text('Could not load that.'), findsOneWidget);
  });

  /// docs/12 §6 level 2 is "ID + qualification document on file". Submitting with neither asks a
  /// reviewer to verify nothing.
  testWidgets('cannot submit until both documents are on file', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _accepted)));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Submit for review'));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit for review'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('submits once both documents are on file', (tester) async {
    final repo = FakeCoachRepository(
      current: const CoachApplication(
        status: 'draft',
        level: 1,
        agreementAccepted: true,
        hasIdDocument: true,
        hasQualificationDocument: true,
        whatVerificationMeans: 'We have checked identity only.',
      ),
    );
    await tester.pumpWidget(pageWith(repo));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Submit for review'));
    await tester.tap(find.widgetWithText(FilledButton, 'Submit for review'));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(find.text('Submit for review'), findsNothing);
  });

  /// The screen's ceiling. A submitted application waits for a human and says so.
  testWidgets('says it is waiting for a human once submitted', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _submitted)));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.textContaining('with our team'));
    expect(find.textContaining('with our team'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit for review'), findsNothing);
  });

  /// An already-verified partner has nothing left to submit. The button used to survive into this
  /// state, and the only thing tapping it produced was the server's refusal.
  testWidgets('offers no submit button once the partner is verified', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _verified)));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.textContaining('verified partner'));
    expect(find.textContaining('verified partner'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit for review'), findsNothing);
  });

  /// The verdict lands on the server; the applicant's only way to ask for it is to pull.
  testWidgets('pulling down re-asks the server for the application', (tester) async {
    final repo = FakeCoachRepository(current: _submitted);
    await tester.pumpWidget(pageWith(repo));
    await tester.pumpAndSettle();
    expect(repo.applicationCalls, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    expect(repo.applicationCalls, 2);
    // Quietly: the list it was pulled from stays put rather than being swapped for a spinner.
    expect(find.byType(LoadingView), findsNothing);
  });

  /// docs/12 §6: publish exactly what verification means. Server-authored, shown verbatim.
  testWidgets('shows the verification disclaimer the server sent', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _accepted)));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('We have checked identity only.'));
    expect(find.text('We have checked identity only.'), findsOneWidget);
  });

  /// The bug this screen shipped with: two unchecked circles and no way to check either. A status
  /// row pretending to be a step.
  testWidgets('offers a way to add each document', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _accepted)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photo ID'));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  /// An application a reviewer already holds is not the applicant's to edit — otherwise one set
  /// of documents gets approved while another is swapped in underneath.
  testWidgets('will not let documents change while in review', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _submitted)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photo ID'));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsNothing);
  });

  /// D-191. Onboarding asks what someone does purely to decide whether to offer this route, and
  /// keeps nothing — so the application is the only place the answer can be read back, and the
  /// only place it can be corrected.

  testWidgets('asks what the applicant does, and says so when they have not answered', (
    tester,
  ) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(current: _accepted)));
    await tester.pumpAndSettle();

    expect(find.text('What you do'), findsOneWidget);
    expect(find.text('Tell us which kind of partner you are.'), findsOneWidget);
  });

  testWidgets('reads the answer back once it has been given', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          current: const CoachApplication(
            status: 'draft',
            level: 1,
            discipline: CoachDiscipline.nutritionist,
            agreementAccepted: true,
            hasIdDocument: false,
            hasQualificationDocument: false,
            whatVerificationMeans: 'We have checked identity only.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nutritionist'), findsOneWidget);
  });

  testWidgets('changes it, and sends the new answer to the server', (tester) async {
    final repo = FakeCoachRepository(current: _accepted);
    await tester.pumpWidget(pageWith(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('What you do'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trainer'));
    await tester.pumpAndSettle();

    expect(repo.picked, CoachDiscipline.trainer);
    expect(find.text('Trainer'), findsOneWidget);
  });

  /// A qualification certificate means something different for a doctor than for a trainer, so it
  /// stops being the applicant's to change the moment a reviewer picks the application up.
  testWidgets('will not change it while a human is reviewing', (tester) async {
    final repo = FakeCoachRepository(current: _submitted);
    await tester.pumpWidget(pageWith(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('What you do'));
    await tester.pumpAndSettle();

    expect(find.text('What kind of partner are you?'), findsNothing);
    expect(repo.picked, isNull);
  });
}
