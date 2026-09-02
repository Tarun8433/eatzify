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
  LoginController({required this.auth, required this.session, this.googleIdToken});

  final AuthRepository auth;
  final SessionController session;

  /// How a Google ID token is obtained — `GoogleAuthDataSource.idToken` in the running app, a stub
  /// in a widget test that must not touch a platform channel.
  ///
  /// Null is the whole feature flag: main.dart passes it only when the OAuth client id was built
  /// in, and the sign-in screen draws the button only when it is here. A button that cannot
  /// possibly succeed is worse than no button.
  final Future<String?> Function()? googleIdToken;

  bool get googleEnabled => googleIdToken != null;

  static const otpLength = 6;
  static const resendCooldownSeconds = 30;
  static const defaultDialCode = '+91';
  static const defaultPhoneLength = 10;

  /// A stable per-install id so the server can name sessions in its security screen. Explicit
  /// rather than silently sending something identifying — it is the same placeholder for both
  /// sign-in routes, because a session is a session however it was opened.
  static const deviceId = 'pending-device-id';

  final phone = ''.obs;

  /// The chosen country's dialling code, with its `+`, and the length its numbers are allowed to
  /// be. Held here rather than read out of the field at submit time so `isPhoneValid` — and
  /// therefore whether the button is pressable — stays one place with one rule.
  ///
  /// India is the default because that is the market (docs/01), not because it is the only option.
  final dialCode = defaultDialCode.obs;
  final phoneMinLength = defaultPhoneLength.obs;
  final phoneMaxLength = defaultPhoneLength.obs;

  final otp = ''.obs;
  final codeSent = false.obs;
  final busy = false.obs;
  final failure = Rxn<Failure>();
  final resendIn = 0.obs;

  Timer? _cooldown;

  /// The number the running cooldown belongs to. A cooldown exists to stop the app re-sending to
  /// the SAME number; it must not block the first send to a corrected one.
  String? _cooldownFor;

  @override
  void onInit() {
    super.onInit();
    // The controller outlives a sign-out (it is registered with `fenix`), so without this the next
    // sign-in opens on the OTP step with the previous user's number still filled in — and the
    // resend cooldown still ticking against a number nobody is signing in with.
    ever(session.status, (status) {
      if (status == AuthStatus.signedOut) reset();
    });
  }

  /// Returns the form to a clean phone-entry state.
  void reset() {
    _cooldown?.cancel();
    _cooldown = null;
    _cooldownFor = null;
    phone.value = '';
    dialCode.value = defaultDialCode;
    phoneMinLength.value = defaultPhoneLength;
    phoneMaxLength.value = defaultPhoneLength;
    otp.value = '';
    codeSent.value = false;
    busy.value = false;
    failure.value = null;
    resendIn.value = 0;
  }

  /// Back to the phone step with a mistyped number still in the field. Without this the OTP step is
  /// a dead end — a user who fat-fingers a digit has no way back short of killing the app, and the
  /// code they are waiting for is on somebody else's phone.
  void editPhone() {
    otp.value = '';
    failure.value = null;
    codeSent.value = false;
  }

  /// Long enough for the chosen country, and digits only. Sent as E.164.
  ///
  /// The length bounds come from the country the user picked, so a nine-digit country is not asked
  /// for ten. India keeps one extra rule: a mobile number starts 6-9, and a ten-digit number that
  /// does not is a landline — an OTP sent to it is a message nobody will ever receive, so it is
  /// worth refusing here rather than spending an SMS to find out (docs/18 §9).
  bool get isPhoneValid {
    final number = phone.value;
    if (number.length < phoneMinLength.value || number.length > phoneMaxLength.value) return false;
    if (!RegExp(r'^\d+$').hasMatch(number)) return false;
    if (dialCode.value == defaultDialCode) return RegExp('^[6-9]').hasMatch(number);
    return true;
  }

  /// Called when the country changes. The number is cleared with it: digits typed for one country
  /// are rarely valid for the next, and a value the new length will not accept leaves the button
  /// dead with nothing on screen saying why.
  void setCountry({required String dial, required int minLength, required int maxLength}) {
    dialCode.value = dial;
    phoneMinLength.value = minLength;
    phoneMaxLength.value = maxLength;
    phone.value = '';
    failure.value = null;
  }

  bool get isOtpValid => otp.value.length == otpLength;
  bool get canSend =>
      isPhoneValid && !busy.value && (resendIn.value == 0 || phoneE164 != _cooldownFor);
  bool get canVerify => isOtpValid && !busy.value;

  String get phoneE164 => '${dialCode.value}${phone.value}';

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

    final result = await auth.verifyOtp(phoneE164: phoneE164, otp: otp.value, deviceId: deviceId);
    busy.value = false;

    await result.fold((f) async => failure.value = f, (s) async => session.adopt(s));
  }

  /// [failedMessage] is passed in because a plugin error has no server `user_message` to show and
  /// a controller has no `BuildContext` to localise with. Rule 7 is about server-side failures;
  /// this one never reached the server.
  Future<void> signInWithGoogle(String failedMessage) async {
    if (busy.value || !googleEnabled) return;
    busy.value = true;
    failure.value = null;

    String? idToken;
    try {
      idToken = await googleIdToken!();
    } on Object {
      idToken = null;
      failure.value = UnexpectedFailure(failedMessage);
    }

    // Cancelled, or already reported: either way there is nothing to exchange.
    if (idToken == null) {
      busy.value = false;
      return;
    }

    final result = await auth.signInWithGoogle(idToken: idToken, deviceId: deviceId);
    busy.value = false;
    await result.fold((f) async => failure.value = f, (s) async => session.adopt(s));
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _cooldownFor = phoneE164;
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
