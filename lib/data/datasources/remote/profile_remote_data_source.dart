import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/entities/profile_view.dart';

/// docs/09 §4 over dio.
class ProfileRemoteDataSource {
  const ProfileRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, OnboardingResult>> submitOnboarding(OnboardingSubmission body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/profile/onboarding', data: body.toJson());
      final data = res.data!;
      return Right(
        OnboardingResult(
          userId: data['user_id']?.toString() ?? '',
          healthProfileVersion: data['health_profile_version'] as int? ?? 1,
          gates: (data['gates'] as List?)?.map((g) => g.toString()).toList() ?? const [],
        ),
      );
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `PATCH /profile` and `PATCH /profile/health`. Only the changed keys are sent — the server
  /// carries omitted fields forward, so sending the whole object would risk clobbering a field the
  /// user never touched.
  Future<Either<Failure, Unit>> patch(String path, Map<String, dynamic> changed) async {
    try {
      await _dio.patch<Map<String, dynamic>>(path, data: changed);
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /files/upload` then `PATCH /auth/me` to attach it.
  ///
  /// Two calls because the boilerplate's files module owns the upload and the user record owns the
  /// association — worth keeping rather than adding a third endpoint that does both.
  Future<Either<Failure, String>> uploadPhoto(String filePath, String fileName) async {
    try {
      final form = FormData.fromMap({
        // No explicit contentType: MultipartFile infers it from the filename extension, which
        // avoids taking a direct dependency on http_parser just to name a MIME type.
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final upload = await _dio.post<Map<String, dynamic>>('/files/upload', data: form);
      final file = upload.data?['file'] as Map<String, dynamic>?;
      final id = file?['id']?.toString();
      if (id == null) {
        return const Left(UnexpectedFailure('Something went wrong. Please try again.'));
      }

      await _dio.patch<Map<String, dynamic>>(
        '/auth/me',
        data: {
          'photo': {'id': id},
        },
      );

      return Right(file?['path']?.toString() ?? '');
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// The roles this account holds, from the `GET /auth/me` aggregate (docs/09 §3).
  ///
  /// Used for ONE thing: which shell to draw (CLAUDE.md rule 1). docs/10 §1 is explicit that a
  /// role is not permission to see a client — a consent grant is — so nothing else may key off it,
  /// and the server refuses the read regardless of what the app believes.
  Future<Either<Failure, List<String>>> roles() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      final roles = res.data?['roles'];
      if (roles is! List) return const Right([]);
      return Right(roles.map((r) => r.toString()).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// Detaches the photo. `docs/13`: a user must be able to remove a personal image they uploaded.
  Future<Either<Failure, Unit>> removePhoto() async {
    try {
      await _dio.patch<Map<String, dynamic>>('/auth/me', data: {'photo': null});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /profile`. Null on the right means onboarding is not done — not an error.
  Future<Either<Failure, ProfileView?>> profile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/profile');
      final json = res.data ?? const <String, dynamic>{};
      return Right(
        ProfileView.fromJson({...json, 'photo_url': _absolute(json['photo_url']?.toString())}),
      );
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// The API returns a file path relative to its own origin. Resolving it against the client's
  /// base URL — rather than trusting the server's `BACKEND_DOMAIN` — means the image loads from
  /// whatever host the app is already talking to. `BACKEND_DOMAIN` is `localhost` in development,
  /// which a physical device can never reach (D-32).
  String? _absolute(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    final base = Uri.parse(_dio.options.baseUrl);
    return base.replace(path: path).toString();
  }
}
