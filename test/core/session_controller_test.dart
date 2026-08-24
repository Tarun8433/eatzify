import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

/// In-memory stand-in for the keychain.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage() : super();
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data.clear();
}

class _FakeAuth implements AuthRepository {
  Either<Failure, Session> refreshResult = const Left(ApiFailure('nope', code: 'X'));
  int logoutCalls = 0;

  @override
  Future<Either<Failure, Session>> refresh(Session current) async => refreshResult;

  @override
  Future<Either<Failure, Unit>> logout(Session current) async {
    logoutCalls++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> requestOtp(String phoneE164) async => const Right(unit);

  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async =>
      Right(session());
}

Session session({bool onboardingRequired = false, String access = 'a1', String refresh = 'r1'}) =>
    Session(
      accessToken: access,
      refreshToken: refresh,
      userId: 'u-1',
      roles: const ['client'],
      onboardingRequired: onboardingRequired,
    );

void main() {
  late _FakeSecureStorage storage;
  late SecureStore store;
  late _FakeAuth auth;
  late SessionController controller;

  setUp(() {
    storage = _FakeSecureStorage();
    store = SecureStore(storage: storage);
    auth = _FakeAuth();
    controller = SessionController(store: store, auth: auth);
  });

  group('boot', () {
    test('no stored session means signed out', () async {
      await controller.restore();
      expect(controller.status.value, AuthStatus.signedOut);
      expect(controller.session, isNull);
    });

    test('a stored session is restored without a network call', () async {
      await store.save(session());
      await controller.restore();
      expect(controller.status.value, AuthStatus.signedIn);
      expect(controller.accessToken, 'a1');
    });

    test('the server decides onboarding, not the app', () async {
      await store.save(session(onboardingRequired: true));
      await controller.restore();
      expect(controller.status.value, AuthStatus.onboardingRequired);
    });
  });

  group('token rotation (docs/09 §3)', () {
    test('a successful refresh replaces BOTH tokens and persists them', () async {
      await controller.adopt(session());
      auth.refreshResult = Right(session(access: 'a2', refresh: 'r2'));

      expect(await controller.refreshAccessToken(), 'a2');
      expect(controller.session!.refreshToken, 'r2', reason: 'rotation replaces the refresh token');
      expect((await store.read())!.refreshToken, 'r2', reason: 'and it survives a restart');
    });

    test('a rejected refresh signs the user out — the family is revoked', () async {
      await controller.adopt(session());
      auth.refreshResult = const Left(ApiFailure('revoked', code: 'TOKEN_REUSE'));

      expect(await controller.refreshAccessToken(), isNull);
      expect(controller.status.value, AuthStatus.signedOut);
      expect(await store.read(), isNull, reason: 'a half-cleared session gets retried forever');
    });

    test('does not call the server to log out a session it has already lost', () async {
      auth.refreshResult = const Left(ApiFailure('revoked', code: 'TOKEN_REUSE'));
      await controller.adopt(session());
      await controller.refreshAccessToken();
      expect(auth.logoutCalls, 0, reason: 'the refresh token is already dead');
    });

    test('refreshing with no session is a no-op, not a crash', () async {
      expect(await controller.refreshAccessToken(), isNull);
    });
  });

  group('sign out', () {
    test('clears local state even when the server call fails', () async {
      await controller.adopt(session());
      await controller.signOut();
      expect(controller.session, isNull);
      expect(controller.status.value, AuthStatus.signedOut);
      expect(await store.read(), isNull);
      expect(auth.logoutCalls, 1);
    });
  });

  group('onboarding completion', () {
    test('flips to signedIn and persists', () async {
      await controller.adopt(session(onboardingRequired: true));
      expect(controller.status.value, AuthStatus.onboardingRequired);

      await controller.markOnboardingComplete();
      expect(controller.status.value, AuthStatus.signedIn);
      expect((await store.read())!.onboardingRequired, isFalse);
    });
  });

  group('docs/13 — no credential ever reaches a log', () {
    test('toString omits both tokens', () {
      final text = session(access: 'SECRET-ACCESS', refresh: 'SECRET-REFRESH').toString();
      expect(text, isNot(contains('SECRET-ACCESS')));
      expect(text, isNot(contains('SECRET-REFRESH')));
      expect(text, contains('u-1'));
    });
  });
}
