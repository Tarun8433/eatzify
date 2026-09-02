import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/network/api_client.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/domain/entities/session.dart';

/// Answers every request with one canned JSON body and records what was sent.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Session get _current => const Session(
  accessToken: 'expired-access',
  refreshToken: 'good-refresh',
  userId: 'u-1',
  roles: ['client'],
  onboardingRequired: false,
);

void main() {
  /// api/src/auth/auth.controller.ts guards `POST /auth/refresh` with `AuthGuard('jwt-refresh')`,
  /// and jwt-refresh.strategy.ts pulls the token with `ExtractJwt.fromAuthHeaderAsBearerToken()`.
  /// Sending it in the body instead means every refresh 401s and the app signs the user out as
  /// soon as the 15-minute access token ages out.
  group('POST /auth/refresh matches the server contract', () {
    test('sends the REFRESH token as the bearer, not the access token', () async {
      final adapter = _StubAdapter(200, {
        'token': 'new-access',
        'refreshToken': 'new-refresh',
        'tokenExpires': 1,
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        // The real client's interceptor puts the ACCESS token here; refresh must override it.
        ..options.headers['Authorization'] = 'Bearer expired-access'
        ..httpClientAdapter = adapter;

      await AuthRemoteDataSource(dio).refresh(_current);

      expect(adapter.captured!.headers['Authorization'], 'Bearer good-refresh');
      expect(adapter.captured!.path, '/auth/refresh');
    });

    test('reads RefreshResponseDto — token/refreshToken, not access/refresh', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = _StubAdapter(200, {
          'token': 'new-access',
          'refreshToken': 'new-refresh',
          'tokenExpires': 1,
        });

      final result = await AuthRemoteDataSource(dio).refresh(_current);

      final fresh = result.getOrElse(() => throw StateError('expected a session'));
      expect(fresh.accessToken, 'new-access');
      expect(fresh.refreshToken, 'new-refresh', reason: 'rotation replaces it');
      expect(fresh.userId, 'u-1', reason: 'identity carries over — refresh does not re-state it');
    });
  });

  /// The gap that let the bug ship (D-79): every test above builds a bare `Dio`, so none of them
  /// saw what the auth interceptor does to the header on its way out.
  group('through the real ApiClient, with the interceptor attached', () {
    test('the refresh bearer survives — the interceptor must not overwrite it', () async {
      final adapter = _StubAdapter(200, {
        'token': 'new-access',
        'refreshToken': 'new-refresh',
        'tokenExpires': 1,
      });
      final client = ApiClient(baseUrl: 'https://x/api/v1')
        ..dio.httpClientAdapter = adapter
        // The expired one. Sending THIS to /auth/refresh is a guaranteed 401, and a 401 there is
        // read as "the session is dead" — which signed the user out mid-onboarding.
        ..attachAuth(accessToken: () => 'expired-access', onRefresh: () async => null);

      await AuthRemoteDataSource(client.dio).refresh(_current);

      expect(adapter.captured!.headers['Authorization'], 'Bearer good-refresh');
    });

    test('an ordinary call still gets the access token attached', () async {
      final adapter = _StubAdapter(200, {'ok': true});
      final client = ApiClient(baseUrl: 'https://x/api/v1')
        ..dio.httpClientAdapter = adapter
        ..attachAuth(accessToken: () => 'access-1', onRefresh: () async => null);

      await client.dio.get<dynamic>('/profile');

      expect(adapter.captured!.headers['Authorization'], 'Bearer access-1');
    });

    test('and a call made with no session carries no bearer at all', () async {
      final adapter = _StubAdapter(200, {'ok': true});
      final client = ApiClient(baseUrl: 'https://x/api/v1')
        ..dio.httpClientAdapter = adapter
        ..attachAuth(accessToken: () => null, onRefresh: () async => null);

      await client.dio.post<dynamic>('/auth/otp/request');

      expect(adapter.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });
}
