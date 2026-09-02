import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';

/// Turns a dio error into a Failure carrying the server's own `user_message`.
///
/// CLAUDE.md rule 7: `user_message` is the ONLY text shown to a user for a server-side failure. We
/// never write our own copy for a medical or safety message — those strings are server-controlled
/// by design. The single exception is a connectivity error, which the server never saw.
Failure mapDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      // States only what is true. The old copy — "Your logs are saved and will sync
      // automatically" — promised an offline queue that does not exist anywhere in this app, so on
      // the onboarding screen it told someone their answers were safe seconds before they were
      // lost. One mapper serves all five data sources, so the lie was on every screen.
      return const OfflineFailure('Cannot reach Eatzify. Check your connection and try again.');
    case DioExceptionType.badResponse:
      break;
    // ignore: no_default_cases
    default:
      return const UnexpectedFailure('Something went wrong. Please try again.');
  }

  final status = e.response?.statusCode;
  final body = e.response?.data;
  final envelope = body is Map<String, dynamic> ? body : const <String, dynamic>{};
  final error = envelope['error'] is Map<String, dynamic>
      ? envelope['error'] as Map<String, dynamic>
      : envelope;

  final code = error['code']?.toString() ?? 'UNKNOWN';
  final message = error['user_message']?.toString();

  // docs/05 §3 gates arrive as a 422 domain rejection and must render as a referral, not an error.
  if (status == 422 && error['gate'] != null) {
    return ClinicalGateFailure(message ?? '', gate: error['gate'].toString());
  }

  return ApiFailure(
    message ?? 'Something went wrong. Please try again.',
    code: code,
    status: status,
  );
}
