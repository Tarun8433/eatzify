import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';

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
  }) async =>
      const Left(ApiFailure('bad code', code: 'OTP_INVALID'));

  @override
  Future<Either<Failure, Session>> refresh(Session current) async =>
      const Left(ApiFailure('x', code: 'X'));

  @override
  Future<Either<Failure, Unit>> logout(Session current) async => const Right(unit);
}

void main() {
  late _RecordingAuth auth;
  late LoginController c;

  setUp(() {
    auth = _RecordingAuth();
    c = LoginController(
      auth: auth,
      session: SessionController(store: SecureStore(), auth: auth),
    );
  });

  tearDown(() => c.onClose());

  group('phone validation — India only for v1 (docs/01)', () {
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
}
