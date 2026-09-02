import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';

import '../fakes.dart';

class _RecordingAuth implements AuthRepository {
  int otpRequests = 0;
  String? lastPhone;
  Either<Failure, Unit> otpResult = const Right(unit);

  @override
  Future<Either<Failure, Unit>> requestOtp(String phoneE164) async {
    otpRequests++;
    lastPhone = phoneE164;
    return otpResult;
  }

  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async => const Left(ApiFailure('bad code', code: 'OTP_INVALID'));

  /// Records the exchange so a test can assert the token actually left the app.
  String? lastGoogleIdToken;
  Either<Failure, Session> googleResult = const Left(ApiFailure('no google', code: 'X'));

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async {
    lastGoogleIdToken = idToken;
    return googleResult;
  }

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

  group('phone validation — India by default (docs/01), any country on request', () {
    test('accepts a 10-digit number starting 6-9', () {
      for (final n in ['9876543210', '6000000000', '7012345678', '8123456789']) {
        c.phone.value = n;
        expect(c.isPhoneValid, isTrue, reason: n);
      }
    });

    test('rejects the wrong length, a leading 0-5, and anything non-numeric', () {
      for (final n in ['987654321', '98765432101', '5876543210', '0876543210', '98765abcde']) {
        c.phone.value = n;
        expect(c.isPhoneValid, isFalse, reason: n);
      }
    });

    test('sends E.164', () async {
      c.phone.value = '9876543210';
      await c.sendCode();
      expect(auth.lastPhone, '+919876543210');
    });

    test('another country brings its own length, and its own dialling code', () async {
      // Spain: nine digits, and none of India's 6-9 first-digit rule.
      c.setCountry(dial: '+34', minLength: 9, maxLength: 9);

      c.phone.value = '123456789';
      expect(c.isPhoneValid, isTrue, reason: 'nine digits is a whole Spanish number');

      c.phone.value = '1234567890';
      expect(c.isPhoneValid, isFalse, reason: 'and ten is not');

      c.phone.value = '123456789';
      await c.sendCode();
      expect(auth.lastPhone, '+34123456789');
    });

    test('changing country clears the number', () {
      // Nine digits typed for Spain is not a valid Indian number, and leaving it in the field
      // would disable the button with nothing on screen explaining why.
      c.phone.value = '123456789';
      c.setCountry(dial: '+91', minLength: 10, maxLength: 10);
      expect(c.phone.value, isEmpty);
    });

    test('a sign-out returns the country to the default too', () {
      c
        ..setCountry(dial: '+34', minLength: 9, maxLength: 9)
        ..reset();
      expect(c.dialCode.value, '+91');
      expect(c.phoneMaxLength.value, 10);
    });
  });

  group('OTP cost control (docs/18 §9)', () {
    test('will not send to an invalid number at all', () async {
      c.phone.value = '123';
      await c.sendCode();
      expect(auth.otpRequests, 0, reason: 'every send is money — docs/18 §9');
    });

    test('a cooldown blocks an immediate resend', () async {
      c.phone.value = '9876543210';
      await c.sendCode();
      expect(auth.otpRequests, 1);
      expect(c.resendIn.value, LoginController.resendCooldownSeconds);
      expect(c.canSend, isFalse);

      await c.sendCode();
      expect(auth.otpRequests, 1, reason: 'the second tap must not reach the API');
    });

    test('a failed request does not start a cooldown or advance the screen', () async {
      auth.otpResult = const Left(OfflineFailure('no connection'));
      c.phone.value = '9876543210';
      await c.sendCode();

      expect(c.codeSent.value, isFalse);
      expect(c.resendIn.value, 0, reason: 'the user must be able to retry immediately');
      expect(c.failure.value, isA<OfflineFailure>());
    });
  });

  group('verify', () {
    test('requires a full 6-digit code', () {
      c.otp.value = '12345';
      expect(c.canVerify, isFalse);
      c.otp.value = '123456';
      expect(c.canVerify, isTrue);
    });

    test('surfaces the server message verbatim (CLAUDE.md rule 7)', () async {
      c.otp.value = '123456';
      await c.verify();
      expect(c.failure.value!.userMessage, 'bad code');
    });
  });

  group('a mistyped number is recoverable', () {
    test('editPhone returns to phone entry with the number kept for editing', () async {
      c.phone.value = '8433145573';
      await c.sendCode();
      c.otp.value = '123';

      c.editPhone();

      expect(c.codeSent.value, isFalse, reason: 'the OTP step must not be a dead end');
      expect(c.phone.value, '8433145573', reason: 'a one-digit typo is not a reason to retype ten');
      expect(c.otp.value, isEmpty, reason: 'the old code belongs to the old number');
      expect(c.failure.value, isNull);
    });

    test('the resend cooldown does not block the FIRST send to a corrected number', () async {
      c.phone.value = '8433145573';
      await c.sendCode();
      expect(c.resendIn.value, LoginController.resendCooldownSeconds);
      expect(c.canSend, isFalse, reason: 'resending to the same number is still on cooldown');

      c.editPhone();
      c.phone.value = '8433145574';

      expect(c.canSend, isTrue, reason: 'a different number has never been sent to');
      await c.sendCode();
      expect(auth.otpRequests, 2);
      expect(auth.lastPhone, '+918433145574');
    });
  });

  group('signing out clears the form', () {
    test('a sign-out returns the page to phone entry with no stale number', () {
      c
        ..phone.value = '9876543210'
        ..otp.value = '123456'
        ..codeSent.value = true
        ..resendIn.value = 25;

      // What the user sees after tapping Sign out on the You tab.
      session.status.value = AuthStatus.signedOut;

      expect(c.phone.value, isEmpty);
      expect(c.otp.value, isEmpty);
      expect(c.codeSent.value, isFalse, reason: 'must open on phone entry, not the OTP step');
      expect(c.resendIn.value, 0, reason: 'the cooldown belonged to the previous number');
      expect(c.failure.value, isNull);
    });

    test('signing in does not clear the form mid-flow', () {
      c
        ..phone.value = '9876543210'
        ..codeSent.value = true;

      session.status.value = AuthStatus.signedIn;

      expect(c.phone.value, '9876543210');
      expect(c.codeSent.value, isTrue);
    });
  });
}
