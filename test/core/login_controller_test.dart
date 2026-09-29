import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';

import '../fakes.dart';

/// Records what left the app, and answers what each test sets.
class _RecordingAuth implements AuthRepository {
  final calls = <String>[];
  Map<String, String>? lastBody;

  Either<Failure, Session> signInResult = const Left(
    ApiFailure('Email or password is incorrect.', code: 'INVALID_CREDENTIALS', status: 401),
  );
  Either<Failure, Unit> registerResult = const Right(unit);
  Either<Failure, Session> verifyResult = const Left(ApiFailure('bad code', code: 'CODE_INVALID'));

  @override
  Future<Either<Failure, Session>> signIn({required String email, required String password}) async {
    calls.add('signIn');
    lastBody = {'email': email, 'password': password};
    return signInResult;
  }

  @override
  Future<Either<Failure, Unit>> register({
    required String email,
    required String password,
    required String phoneE164,
  }) async {
    calls.add('register');
    lastBody = {'email': email, 'password': password, 'phone': phoneE164};
    return registerResult;
  }

  @override
  Future<Either<Failure, Session>> verifyEmail({
    required String email,
    required String code,
  }) async {
    calls.add('verify');
    lastBody = {'email': email, 'code': code};
    return verifyResult;
  }

  @override
  Future<Either<Failure, Unit>> resendCode(String email) async {
    calls.add('resend');
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> forgotPassword(String email) async {
    calls.add('forgot');
    lastBody = {'email': email};
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async => const Left(ApiFailure('no google', code: 'X'));

  @override
  Future<Either<Failure, Session>> refresh(Session current) async =>
      const Left(ApiFailure('x', code: 'X'));

  @override
  Future<Either<Failure, Unit>> logout(Session current) async => const Right(unit);
}

void main() {
  late _RecordingAuth auth;
  late LoginController c;
  late SessionController session;

  setUp(() {
    auth = _RecordingAuth();
    session = SessionController(store: SecureStore(), auth: auth, profile: FakeProfileRepository());
    c = LoginController(auth: auth, session: session)..onInit();
  });

  tearDown(() => c.onClose());

  void fillSignUp() => c
    ..email.value = ' Asha@Example.com '
    ..password.value = 'longenough'
    ..phone.value = '9876543210';

  group('sign in (D-250)', () {
    test('needs an email and a password before it will ask', () async {
      c.email.value = 'not-an-email';
      c.password.value = 'whatever';
      await c.signIn();
      expect(auth.calls, isEmpty);
    });

    test('sends the email trimmed and lowercased', () async {
      c
        ..email.value = ' Asha@Example.com '
        ..password.value = 'pw';
      await c.signIn();
      expect(auth.lastBody, {'email': 'asha@example.com', 'password': 'pw'});
    });

    test('shows the server message verbatim (rule 7)', () async {
      c
        ..email.value = 'asha@example.com'
        ..password.value = 'wrong';
      await c.signIn();
      expect(c.failure.value!.userMessage, 'Email or password is incorrect.');
      expect(c.step.value, AuthStep.signIn);
    });

    test('an unconfirmed address goes to the code step, not an error', () async {
      auth.signInResult = const Left(
        ApiFailure('Confirm your email', code: LoginController.emailNotVerified, status: 403),
      );
      c
        ..email.value = 'asha@example.com'
        ..password.value = 'longenough';
      await c.signIn();

      expect(c.step.value, AuthStep.verify);
      expect(c.failure.value, isNull);
      expect(
        c.resendIn.value,
        LoginController.resendCooldownSeconds,
        reason: 'a code was just sent',
      );
    });
  });

  group('sign up', () {
    test('needs a password of at least 8 and a real phone number', () {
      fillSignUp();
      expect(c.canSignUp, isTrue);

      c.password.value = 'short';
      expect(c.canSignUp, isFalse);

      c
        ..password.value = 'longenough'
        ..phone.value = '5876543210';
      expect(c.canSignUp, isFalse, reason: 'an Indian mobile starts 6-9');
    });

    test('sends the phone as E.164 and moves to the code step', () async {
      fillSignUp();
      await c.signUp();

      expect(auth.lastBody, {
        'email': 'asha@example.com',
        'password': 'longenough',
        'phone': '+919876543210',
      });
      expect(c.step.value, AuthStep.verify);
    });

    test('a refused sign-up stays put and says why', () async {
      auth.registerResult = const Left(ApiFailure('Already registered', code: 'EMAIL_TAKEN'));
      c.goTo(AuthStep.signUp);
      fillSignUp();
      await c.signUp();

      expect(c.step.value, AuthStep.signUp);
      expect(c.failure.value!.userMessage, 'Already registered');
      expect(c.resendIn.value, 0);
    });

    test('another country brings its own length', () {
      c.setCountry(dial: '+34', minLength: 9, maxLength: 9);
      c.phone.value = '123456789';
      expect(c.isPhoneValid, isTrue);
      expect(c.phoneE164, '+34123456789');
    });
  });

  group('the emailed code', () {
    test('requires six digits', () {
      c.code.value = '12345';
      expect(c.canVerify, isFalse);
      c.code.value = '123456';
      expect(c.canVerify, isTrue);
    });

    test('a wrong code shows the server message', () async {
      c
        ..email.value = 'asha@example.com'
        ..code.value = '123456';
      await c.verify();
      expect(auth.lastBody, {'email': 'asha@example.com', 'code': '123456'});
      expect(c.failure.value!.userMessage, 'bad code');
    });

    test('resend waits out its cooldown', () async {
      fillSignUp();
      await c.signUp();
      await c.resendCode();
      expect(auth.calls.where((x) => x == 'resend'), isEmpty);
    });
  });

  group('forgot password', () {
    test('sends the email and shows the same answer whatever the server knows', () async {
      c
        ..goTo(AuthStep.forgot)
        ..email.value = 'Asha@example.com';
      await c.sendReset();

      expect(auth.lastBody, {'email': 'asha@example.com'});
      expect(c.step.value, AuthStep.forgotSent);
    });
  });

  test('moving between steps keeps the email and drops the password', () {
    c
      ..email.value = 'asha@example.com'
      ..password.value = 'secret123'
      ..goTo(AuthStep.forgot);

    expect(c.email.value, 'asha@example.com');
    expect(c.password.value, isEmpty);
  });

  test('a sign-out returns the page to a clean sign-in', () async {
    fillSignUp();
    await c.signUp();

    session.status.value = AuthStatus.signedOut;

    expect(c.step.value, AuthStep.signIn);
    expect(c.email.value, isEmpty);
    expect(c.resendIn.value, 0);
    expect(c.dialCode.value, LoginController.defaultDialCode);
  });
}
