import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';

/// Coach onboarding (docs/12 §6). Nothing about clients: an applicant has none, and the surfaces
/// that do are gated on a consent grant rather than on a role (docs/10 §1).
abstract class CoachRepository {
  /// Null when this account has never applied.
  Future<Either<Failure, CoachApplication?>> application();

  /// What the applicant says they do. Answerable before the agreement, and revisable right up
  /// until a human starts reading the documents.
  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline discipline);

  /// The whole of level 1. [version] records WHICH agreement was accepted.
  Future<Either<Failure, CoachApplication>> acceptAgreement(String version);

  /// docs/12 §6: the coaching agreement — level 3's partner half (D-235).
  Future<Either<Failure, CoachApplication>> acceptCoachingAgreement(String version);

  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  });

  /// Uploads a document and returns its file id. The bytes go to the files module; only the id
  /// reaches the application.
  Future<Either<Failure, String>> uploadDocument(String filePath, String fileName);

  /// Hands the application to a human. The last step the app can take.
  Future<Either<Failure, CoachApplication>> submit();

  /// docs/10 §3's "Who can see my data": every grant this client has given, paused ones included.
  /// What THIS coach has asked and nobody has answered yet — their own actions read back.
  Future<Either<Failure, List<SentInvite>>> sentInvites();

  /// docs/12 §9's coach widgets in one call: counts, renewals due, and the at-risk list. One read,
  /// because a tile and the list under it must never disagree.
  Future<Either<Failure, CoachDashboard>> dashboard();

  /// docs/12 §8. Aggregate only — a per-client line would tell a partner what one person paid.
  /// [period] is `YYYY-MM`; null means this month.
  Future<Either<Failure, CoachEarnings>> earnings({String? period});

  /// The code and link a partner shares. Minted on first ask and stable afterwards.
  Future<Either<Failure, CoachReferral>> referral();

  /// The people who ACCEPTED (docs/10 §1). Driven by consent grants, not by a role: a coach with
  /// no grant has an empty roster whatever their level.
  Future<Either<Failure, List<CoachClient>>> clients();

  /// What the client has been logging — weight, steps, water, adherence, streak. Needs their
  /// `progress` grant and a verified coach; the server answers 404 otherwise, the same way it
  /// answers for a person who does not exist.
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId);

  /// One day of what this client actually ate. [date] is a diary date, `YYYY-MM-DD`; null means
  /// today. Needs their `progress` grant and a verified coach.
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date});

  /// One client, already filtered by the server to what they allowed and what this coach's level
  /// reaches. The app never decides what it may show — it renders what arrived.
  Future<Either<Failure, CoachClientDetail>> client(int clientUserId);

  /// docs/02 FR-5.2: this coach's weekly reviews, already sorted by who needs attention most.
  /// The server opens this week's rows as it answers, so the queue is never empty by accident.
  Future<Either<Failure, List<CheckIn>>> checkIns({String? status});

  /// docs/09 §6: closes one review with what was said and what was agreed.
  Future<Either<Failure, CheckIn>> completeCheckIn({
    required String id,
    String? notes,
    List<String> actions,
  });

  /// docs/02 FR-5.3: who has stopped logging, drifted off their goal, is running out of plan, or
  /// has a review nobody did.
  Future<Either<Failure, List<CoachAlert>>> alerts();

  /// What this client has been ASKED, keyed on their own number from the token. Pending only —
  /// the server drops expired and answered rows, so anything here is still open (docs/09 §6).
  Future<Either<Failure, List<CoachInvite>>> invites();

  /// The client says yes. The only call in the app that turns an ask into a grant.
  Future<Either<Failure, Unit>> acceptInvite(String inviteId);

  /// The client says no. Nothing is created, and the coach is not told who declined.
  Future<Either<Failure, Unit>> declineInvite(String inviteId);

  Future<Either<Failure, List<DataAccess>>> dataAccess();

  /// Takes one coach's access back. One tap, immediate, no reason asked.
  Future<Either<Failure, Unit>> revokeAccess(int coachUserId);

  /// The coach ASKS one person to work with them (docs/09 §6). Creates no access — only the
  /// client accepting does that.
  ///
  /// Succeeds the same way whether the number has an account or not: docs/09 §3 forbids revealing
  /// whether a number exists, so the app must not report it either.
  Future<Either<Failure, Unit>> invite({required String phoneE164, required List<String> scopes});
}
