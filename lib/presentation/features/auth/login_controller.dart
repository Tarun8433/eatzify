import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

/// Phone + OTP sign-in. docs/09 §3.
///
/// docs/18 §9 warns that OTP SMS is the dominant cost at low scale and scales with signups rather
/// than revenue, so the resend cooldown here is a real cost control, not a nicety. The server
/// enforces 3/hour/number regardless (docs/09 §10) — this only stops the app adding to the bill.
class LoginController extends GetxController {
  LoginController({required this.auth, required this.session});

  final AuthRepository auth;
  final SessionController session;

  static const otpLength = 6;
  static const resendCooldownSeconds = 30;

  final phone = ''.obs;
  final otp = ''.obs;
  final codeSent = false.obs;
  final busy = false.obs;
  final failure = Rxn<Failure>();
  final resendIn = 0.obs;

  Timer? _cooldown;

  /// India-only for v1 (docs/01). A 10-digit number starting 6-9, sent as E.164.
  bool get isPhoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(phone.value);
  bool get isOtpValid => otp.value.length == otpLength;
  bool get canSend => isPhoneValid && !busy.value && resendIn.value == 0;
  bool get canVerify => isOtpValid && !busy.value;

  String get phoneE164 => '+91${phone.value}';

  @override
  void onClose() {
    _cooldown?.cancel();
    super.onClose();
  }

  Future<void> sendCode() async {
    if (!canSend) return;
    busy.value = true;
    failure.value = null;

    final result = await auth.requestOtp(phoneE164);
    busy.value = false;

    result.fold((f) => failure.value = f, (_) {
      codeSent.value = true;
      _startCooldown();
    });
  }

  Future<void> verify() async {
    if (!canVerify) return;
    busy.value = true;
    failure.value = null;

    final result = await auth.verifyOtp(
      phoneE164: phoneE164,
      otp: otp.value,
      // A stable per-install id belongs here so the server can name sessions in the security
      // screen. Left explicit rather than silently sending something identifying.
      deviceId: 'pending-device-id',
    );
    busy.value = false;

    await result.fold((f) async => failure.value = f, (s) async => session.adopt(s));
  }

  void _startCooldown() {
    _cooldown?.cancel();
    resendIn.value = resendCooldownSeconds;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (resendIn.value <= 1) {
        t.cancel();
        resendIn.value = 0;
        return;
      }
      resendIn.value -= 1;
    });
  }
}
