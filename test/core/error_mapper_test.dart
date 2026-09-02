import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';

/// Every remote data source funnels through `mapDioError`, so one wrong string here is wrong on
/// every screen at once — which is exactly what happened (D-93).

DioException _connectionFailure(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/profile/onboarding'),
  type: type,
);

DioException _badResponse(int status, Map<String, dynamic>? body) => DioException(
  requestOptions: RequestOptions(path: '/plans/generate'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/plans/generate'),
    statusCode: status,
    data: body,
  ),
);

void main() {
  group('no connection', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      test('$type is an OfflineFailure, not an unexpected one', () {
        expect(mapDioError(_connectionFailure(type)), isA<OfflineFailure>());
      });
    }

    test('the message promises nothing the app does not do', () {
      final message = mapDioError(
        _connectionFailure(DioExceptionType.connectionTimeout),
      ).userMessage.toLowerCase();

      // There is no outbox, no retry queue and no background sync anywhere in this app. The copy
      // used to say "Your logs are saved and will sync automatically", which on the onboarding
      // screen told someone their answers were safe seconds before they were thrown away.
      expect(message, isNot(contains('sync')));
      expect(message, isNot(contains('saved')));
      expect(message, contains('try again'), reason: 'retrying is the only thing that helps');
    });
  });

  group('the server explained itself', () {
    test("a 4xx renders the server's user_message and code", () {
      final failure = mapDioError(
        _badResponse(403, {
          'error': {'code': 'ENTITLEMENT_REQUIRED', 'user_message': 'Upgrade to see this plan.'},
        }),
      );

      expect(failure, isA<ApiFailure>());
      expect(failure.userMessage, 'Upgrade to see this plan.');
      expect((failure as ApiFailure).isEntitlementRequired, isTrue);
    });

    test('a 422 carrying a gate is a referral, not an error (docs/05 §3)', () {
      final failure = mapDioError(
        _badResponse(422, {
          'error': {
            'code': 'CLINICAL_GATE',
            'gate': 'pregnancy',
            'user_message': 'Please speak to your doctor first.',
          },
        }),
      );

      expect(failure, isA<ClinicalGateFailure>());
      expect((failure as ClinicalGateFailure).gate, 'pregnancy');
    });

    test('a body with no user_message still says something a user can read', () {
      final failure = mapDioError(_badResponse(500, null));
      expect(failure.userMessage, isNotEmpty);
      expect(failure.userMessage, isNot(contains('DioException')));
    });
  });
}
