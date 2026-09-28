import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';

/// `GET|POST /coach/application*` (docs/12 §6).
class CoachRemoteDataSource {
  CoachRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, CoachApplication?>> application() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/coach/application');
      final data = res.data;
      // No application yet is a normal state, not an error: most accounts never apply.
      return Right(data == null ? null : CoachApplication.fromJson(data));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, CoachApplication>> setDiscipline(CoachDiscipline discipline) =>
      _post('/coach/application/discipline', {'discipline': discipline.wire});

  Future<Either<Failure, CoachApplication>> acceptAgreement(String version) =>
      _post('/coach/application/agreement', {'agreement_version': version});

  Future<Either<Failure, CoachApplication>> acceptCoachingAgreement(String version) =>
      _post('/coach/application/coaching-agreement', {'agreement_version': version});

  Future<Either<Failure, CoachApplication>> attachDocuments({
    String? idDocumentFileId,
    String? qualificationDocumentFileId,
  }) => _post('/coach/application/documents', {
    if (idDocumentFileId != null) 'id_document_file_id': idDocumentFileId,
    if (qualificationDocumentFileId != null)
      'qualification_document_file_id': qualificationDocumentFileId,
  });

  Future<Either<Failure, CoachApplication>> submit() =>
      _post('/coach/application/submit', const {});

  /// `GET /coach/dashboard` (D-200).
  Future<Either<Failure, CoachDashboard>> dashboard() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/coach/dashboard');
      return Right(CoachDashboard.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/earnings?period=` (D-201). The period is a month, never a health field, so it is
  /// a query string rather than a body (rule 6 only binds health data).
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/coach/earnings',
        queryParameters: period == null ? null : {'period': period},
      );
      return Right(CoachEarnings.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, CoachReferral>> referral() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/coach/referral');
      return Right(CoachReferral.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/clients` (D-195). Consent grants decide the rows; the role only narrows them.
  Future<Either<Failure, List<CoachClient>>> clients() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/clients');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => CoachClient.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/clients/:id/progress` (D-203).
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/coach/clients/$clientUserId/progress');
      return Right(ClientProgress.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/clients/:id/diary?date=` (D-206). The server returns the same day shape the
  /// client sees on their own Home tab, so both sides read one number for one question.
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/coach/clients/$clientUserId/diary',
        queryParameters: date == null ? null : {'date': date},
      );
      final day = (res.data ?? const {})['day'] as Map<String, dynamic>?;
      return Right(DiaryDay.fromJson(day ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/clients/:id`. A 404 here means "no grant" as well as "no such person" — the server
  /// answers both the same way on purpose, so the app must not translate it into either.
  Future<Either<Failure, CoachClientDetail>> client(int clientUserId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/coach/clients/$clientUserId');
      return Right(CoachClientDetail.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/checkins` (docs/09 §6). [status] filters; null asks for the whole queue.
  Future<Either<Failure, List<CheckIn>>> checkIns({String? status}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/coach/checkins',
        queryParameters: {if (status != null) 'status': status},
      );
      final rows = res.data ?? const [];
      return Right(rows.map((r) => CheckIn.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /coach/checkins/{id}/complete` — the note and what they agreed to do next.
  Future<Either<Failure, CheckIn>> completeCheckIn({
    required String id,
    String? notes,
    List<String> actions = const [],
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/coach/checkins/$id/complete',
        data: {
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          if (actions.isNotEmpty) 'actions': actions,
        },
      );
      return Right(CheckIn.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /coach/alerts` (docs/02 FR-5.3).
  Future<Either<Failure, List<CoachAlert>>> alerts() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/alerts');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => CoachAlert.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<SentInvite>>> sentInvites() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/invites/sent');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => SentInvite.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<CoachInvite>>> invites() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/invites');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => CoachInvite.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> acceptInvite(String inviteId) => _answerInvite(inviteId, 'accept');

  Future<Either<Failure, Unit>> declineInvite(String inviteId) =>
      _answerInvite(inviteId, 'decline');

  /// Both answers are the same call with a different verb, and both return 204 — there is no body
  /// to read, so the list is reloaded afterwards rather than patched from a response that is empty
  /// by design.
  Future<Either<Failure, Unit>> _answerInvite(String inviteId, String answer) async {
    try {
      await _dio.post<void>('/coach/invites/$inviteId/$answer');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<DataAccess>>> dataAccess() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/access');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => DataAccess.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> invite({
    required String phoneE164,
    required List<String> scopes,
  }) async {
    try {
      await _dio.post<void>(
        '/coach/clients/invite',
        data: {'phone_e164': phoneE164, 'scopes': scopes},
      );
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> revokeAccess(int coachUserId) async {
    try {
      await _dio.post<void>('/coach/access/$coachUserId/revoke');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /files/upload`, returning the id the application stores.
  ///
  /// Separate from the attach call because the files module owns the bytes and the application
  /// owns the reference — and because the id is the only part that ever needs to be kept. The
  /// document itself never passes through the coach routes.
  Future<Either<Failure, String>> uploadDocument(String filePath, String fileName) async {
    try {
      final form = FormData.fromMap({
        // No explicit contentType: MultipartFile infers it from the extension, which avoids a
        // dependency on http_parser just to name a MIME type.
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final res = await _dio.post<Map<String, dynamic>>('/files/upload', data: form);
      final id = (res.data?['file'] as Map<String, dynamic>?)?['id']?.toString();
      if (id == null) {
        return const Left(UnexpectedFailure('Something went wrong. Please try again.'));
      }

      return Right(id);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, CoachApplication>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return Right(CoachApplication.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
