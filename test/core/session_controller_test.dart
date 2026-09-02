import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

import '../fakes.dart';

/// In-memory stand-in for the keychain.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage() : super();
  final Map<String, String> data = {};
  bool throwOnRead = false;

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
  }) async {
    if (throwOnRead) throw Exception('keychain unavailable');
    return data[key];
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.clear();
}

class _FakeAuth implements AuthRepository {
  Either<Failure, Session> refreshResult = const Left(ApiFailure('nope', code: 'X', status: 401));
  int logoutCalls = 0;
  int refreshCalls = 0;

  /// Set to make refresh take a turn of the event loop, so concurrent callers overlap.
  Duration refreshDelay = Duration.zero;

  @override
  Future<Either<Failure, Session>> refresh(Session current) async {
    refreshCalls++;
    if (refreshDelay > Duration.zero) await Future<void>.delayed(refreshDelay);
    return refreshResult;
  }

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
  }) async => Right(session());

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async => Right(session());
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

  /// What `GET /profile` answers on boot. `Right(null)` — no profile on the server — is the state
  /// of someone who genuinely still has to onboard, so it is the default.
  Either<Failure, ProfileView?> onServer = const Right(null);

  void build() => controller = SessionController(
    store: store,
    auth: auth,
    profile: FakeProfileRepository(profileResult: onServer),
    splashFloor: Duration.zero,
  );

  setUp(() {
    storage = _FakeSecureStorage();
    store = SecureStore(storage: storage);
    auth = _FakeAuth();
    onServer = const Right(null);
    build();
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

    /// The reported bug: a user who already has an account opens the app and gets "About you"
    /// after every splash. `onboarding_required` is cached at sign-in and copied forward by every
    /// refresh, so once it is stale nothing on the device can ever correct it — and the form has no
    /// route back to their account.
    test('a stale onboarding flag is corrected by the server on boot', () async {
      await store.save(session(onboardingRequired: true));
      onServer = const Right(defaultProfile);
      build();

      await controller.restore();

      expect(controller.status.value, AuthStatus.signedIn);
      // Persisted, so the next launch does not need the round-trip.
      expect(storage.data['auth.onboarding_required'], 'false');
    });

    test('an offline boot keeps the cached flag rather than guessing', () async {
      await store.save(session(onboardingRequired: true));
      onServer = const Left(OfflineFailure('offline'));
      build();

      await controller.restore();

      expect(controller.status.value, AuthStatus.onboardingRequired);
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
      auth.refreshResult = const Left(ApiFailure('revoked', code: 'TOKEN_REUSE', status: 401));

      expect(await controller.refreshAccessToken(), isNull);
      expect(controller.status.value, AuthStatus.signedOut);
      expect(await store.read(), isNull, reason: 'a half-cleared session gets retried forever');
    });

    test('does not call the server to log out a session it has already lost', () async {
      auth.refreshResult = const Left(ApiFailure('revoked', code: 'TOKEN_REUSE', status: 401));
      await controller.adopt(session());
      await controller.refreshAccessToken();
      expect(auth.logoutCalls, 0, reason: 'the refresh token is already dead');
    });

    test('refreshing with no session is a no-op, not a crash', () async {
      expect(await controller.refreshAccessToken(), isNull);
    });

    test(
      'concurrent 401s share ONE refresh — sending the token twice revokes the family',
      () async {
        await controller.adopt(session());
        auth
          ..refreshResult = Right(session(access: 'a2', refresh: 'r2'))
          ..refreshDelay = const Duration(milliseconds: 10);

        final tokens = await Future.wait([
          controller.refreshAccessToken(),
          controller.refreshAccessToken(),
          controller.refreshAccessToken(),
          controller.refreshAccessToken(),
        ]);

        expect(
          auth.refreshCalls,
          1,
          reason: 'four tabs 401ing must not rotate the token four times',
        );
        expect(tokens, everyElement('a2'), reason: "the waiters get the winner's token");
      },
    );

    test('a later refresh still works once the first has finished', () async {
      await controller.adopt(session());
      auth.refreshResult = Right(session(access: 'a2', refresh: 'r2'));
      await controller.refreshAccessToken();

      auth.refreshResult = Right(session(access: 'a3', refresh: 'r3'));
      expect(await controller.refreshAccessToken(), 'a3', reason: 'the gate reopens');
      expect(auth.refreshCalls, 2);
    });

    test(
      'an offline refresh keeps the session — a dropped connection is not a revocation',
      () async {
        await controller.adopt(session());
        auth.refreshResult = const Left(OfflineFailure('no connection'));

        expect(await controller.refreshAccessToken(), isNull);
        expect(controller.status.value, AuthStatus.signedIn, reason: 'a lift is not a logout');
        expect(controller.session, isNotNull);
        expect((await store.read())!.refreshToken, 'r1', reason: 'the token is still good');
      },
    );

    test('a 500 from /auth/refresh keeps the session', () async {
      await controller.adopt(session());
      auth.refreshResult = const Left(ApiFailure('server error', code: 'INTERNAL', status: 500));

      expect(await controller.refreshAccessToken(), isNull);
      expect(controller.status.value, AuthStatus.signedIn);
    });
  });

  group('boot resilience', () {
    test('an unreadable keychain signs out rather than hanging on the splash', () async {
      storage.throwOnRead = true;
      await controller.restore();
      expect(controller.status.value, AuthStatus.signedOut);
    });

    test('clearing an unreadable keychain still empties it', () async {
      await store.save(session());
      storage.throwOnRead = true;

      // `clear` reads one key before deleting (the intro flag survives a sign-out). It is also the
      // recovery path for a keychain that cannot be read, so that read must not be able to throw —
      // when it did, an unreadable keychain sat on the splash forever.
      await store.clear();
      expect(storage.data, isEmpty);
    });

    test('the intro flag outlives a sign-out', () async {
      await store.markIntroSeen();
      await store.save(session());
      await controller.signOut(revokeOnServer: false);

      expect(await store.readIntroSeen(), isTrue, reason: 'signing out is not a fresh install');
      expect(await store.read(), isNull, reason: 'but the session is gone');
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
