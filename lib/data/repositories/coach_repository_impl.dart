import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/coach_remote_data_source.dart';
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

class CoachRepositoryImpl implements CoachRepository {
  CoachRepositoryImpl(this._remote);

  final CoachRemoteDataSource _remote;

  @override
  Future<Either<Failure, CoachApplication?>> application() => _remote.application();

  @override
  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline discipline) =>
      _remote.setDiscipline(discipline);

  @override
  Future<Either<Failure, CoachApplication>> acceptAgreement(String version) =>
      _remote.acceptAgreement(version);

  @override
  Future<Either<Failure, CoachApplication>> acceptCoachingAgreement(String version) =>
      _remote.acceptCoachingAgreement(version);

  @override
  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  }) => _remote.attachDocuments(
    idDocumentFileId: idDocumentFileId,
    qualificationDocumentFileId: qualificationDocumentFileId,
  );

  @override
  Future<Either<Failure, String>> uploadDocument(String filePath, String fileName) =>
      _remote.uploadDocument(filePath, fileName);

  @override
  Future<Either<Failure, CoachApplication>> submit() => _remote.submit();

  @override
  Future<Either<Failure, List<SentInvite>>> sentInvites() => _remote.sentInvites();

  @override
  Future<Either<Failure, List<CheckIn>>> checkIns({String? status}) =>
      _remote.checkIns(status: status);

  @override
  Future<Either<Failure, CheckIn>> completeCheckIn({
    required String id,
    String? notes,
    List<String> actions = const [],
  }) => _remote.completeCheckIn(id: id, notes: notes, actions: actions);

  @override
  Future<Either<Failure, List<CoachAlert>>> alerts() => _remote.alerts();

  @override
  Future<Either<Failure, List<CoachInvite>>> invites() => _remote.invites();

  @override
  Future<Either<Failure, Unit>> acceptInvite(String inviteId) => _remote.acceptInvite(inviteId);

  @override
  Future<Either<Failure, Unit>> declineInvite(String inviteId) => _remote.declineInvite(inviteId);

  @override
  Future<Either<Failure, CoachDashboard>> dashboard() => _remote.dashboard();

  @override
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) =>
      _remote.earnings(period: period);

  @override
  Future<Either<Failure, CoachReferral>> referral() => _remote.referral();

  @override
  Future<Either<Failure, List<CoachClient>>> clients() => _remote.clients();

  @override
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) =>
      _remote.clientProgress(clientUserId);

  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) =>
      _remote.clientDiary(clientUserId, date: date);

  @override
  Future<Either<Failure, CoachClientDetail>> client(int clientUserId) =>
      _remote.client(clientUserId);

  @override
  Future<Either<Failure, List<DataAccess>>> dataAccess() => _remote.dataAccess();

  @override
  Future<Either<Failure, Unit>> revokeAccess(int coachUserId) => _remote.revokeAccess(coachUserId);

  @override
  Future<Either<Failure, Unit>> invite({required String phoneE164, required List<String> scopes}) =>
      _remote.invite(phoneE164: phoneE164, scopes: scopes);
}
