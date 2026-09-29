import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

/// Which question the sign-in screen is asking.
enum AuthStep { signIn, signUp, verify, forgot, forgotSent }

/// Email and password sign-in, with a 6-digit code emailed the first time (D-250).
///
/// The phone number is still asked for at sign-up — Cashfree needs one per order — but it is
/// contact information, never a way in. Every refusal shown is the server's `user_message` (rule 7).
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

  static const codeLength = 6;
  static const minPasswordLength = 8;
  static const resendCooldownSeconds = 30;
  static const defaultDialCode = '+91';
  static const defaultPhoneLength = 10;

  /// A stable per-install id so the server can name sessions in its security screen. Explicit
  /// rather than silently sending something identifying.
  static const deviceId = 'pending-device-id';

  /// What the server answers when the password was right but the address was never confirmed. It
  /// has just emailed a fresh code, so the screen moves to where that code goes.
  static const emailNotVerified = 'EMAIL_NOT_VERIFIED';

  final step = AuthStep.signIn.obs;
  final email = ''.obs;
  final password = ''.obs;

  /// Sign-up only. The chosen country's dialling code and the lengths its numbers may be — India
  /// by default because it is the market (docs/01), not because it is the only option.
  final phone = ''.obs;
  final dialCode = defaultDialCode.obs;
  final phoneMinLength = defaultPhoneLength.obs;
  final phoneMaxLength = defaultPhoneLength.obs;

  final code = ''.obs;
  final busy = false.obs;
  final failure = Rxn<Failure>();
  final resendIn = 0.obs;

  Timer? _cooldown;

  @override
  void onInit() {
    super.onInit();
    // The controller outlives a sign-out (it is registered with `fenix`), so without this the next
    // sign-in opens on the code step with the previous user's email still filled in.
    ever(session.status, (status) {
      if (status == AuthStatus.signedOut) reset();
    });
  }

  @override
  void onClose() {
    _cooldown?.cancel();
    super.onClose();
  }

  /// Back to a clean sign-in form.
  void reset() {
    _stopCooldown();
    email.value = '';
    password.value = '';
    phone.value = '';
    dialCode.value = defaultDialCode;
    phoneMinLength.value = defaultPhoneLength;
    phoneMaxLength.value = defaultPhoneLength;
    code.value = '';
    busy.value = false;
    failure.value = null;
    step.value = AuthStep.signIn;
  }

  /// Moves to another step, keeping the email typed so far — someone who tapped "Forgot password?"
  /// should not have to type it again.
  void goTo(AuthStep next) {
    failure.value = null;
    password.value = '';
    code.value = '';
    step.value = next;
  }

  // Deliberately loose: the server's `IsEmail` is the real check, and a strict pattern here is one
  // more way to refuse a valid address.
  bool get isEmailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.value.trim());
  bool get isPasswordValid => password.value.length >= minPasswordLength;
  bool get isCodeValid => RegExp('^\\d{$codeLength}\$').hasMatch(code.value);

  /// Long enough for the chosen country, and digits only. India keeps one extra rule: a mobile
  /// number starts 6-9, and one that does not is a landline nobody can be reached on for a receipt.
  bool get isPhoneValid {
    final number = phone.value;
    if (number.length < phoneMinLength.value || number.length > phoneMaxLength.value) return false;
    if (!RegExp(r'^\d+$').hasMatch(number)) return false;
    if (dialCode.value == defaultDialCode) return RegExp('^[6-9]').hasMatch(number);
    return true;
  }

  String get phoneE164 => '${dialCode.value}${phone.value}';
  String get _email => email.value.trim().toLowerCase();

  bool get canSignIn => isEmailValid && password.value.isNotEmpty && !busy.value;
  bool get canSignUp => isEmailValid && isPasswordValid && isPhoneValid && !busy.value;
  bool get canVerify => isCodeValid && !busy.value;
  bool get canResend => resendIn.value == 0 && !busy.value;
  bool get canSendReset => isEmailValid && !busy.value;

  /// Called when the country changes. The number is cleared with it: digits typed for one country
  /// are rarely valid for the next.
  void setCountry({required String dial, required int minLength, required int maxLength}) {
    dialCode.value = dial;
    phoneMinLength.value = minLength;
    phoneMaxLength.value = maxLength;
    phone.value = '';
    failure.value = null;
  }

  Future<void> signIn() async {
    if (!canSignIn) return;
    final result = await _run(() => auth.signIn(email: _email, password: password.value));
    await result?.fold((f) async {
      if (f is ApiFailure && f.code == emailNotVerified) {
        _toCodeStep();
        return;
      }
      failure.value = f;
    }, session.adopt);
  }

  Future<void> signUp() async {
    if (!canSignUp) return;
    final result = await _run(
      () => auth.register(email: _email, password: password.value, phoneE164: phoneE164),
    );
    result?.fold((f) => failure.value = f, (_) => _toCodeStep());
  }

  Future<void> verify() async {
    if (!canVerify) return;
    final result = await _run(() => auth.verifyEmail(email: _email, code: code.value));
    await result?.fold((f) async => failure.value = f, session.adopt);
  }

  Future<void> resendCode() async {
    if (!canResend) return;
    final result = await _run(() => auth.resendCode(_email));
    result?.fold((f) => failure.value = f, (_) => _startCooldown());
  }

  Future<void> sendReset() async {
    if (!canSendReset) return;
    final result = await _run(() => auth.forgotPassword(_email));
    result?.fold((f) => failure.value = f, (_) => step.value = AuthStep.forgotSent);
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
    await result.fold((f) async => failure.value = f, session.adopt);
  }

  /// One request at a time, with the last failure cleared first.
  Future<T?> _run<T>(Future<T> Function() request) async {
    if (busy.value) return null;
    busy.value = true;
    failure.value = null;
    try {
      return await request();
    } finally {
      busy.value = false;
    }
  }

  /// A code was just emailed — by sign-up, or by a sign-in to an unconfirmed address — so asking
  /// for another straight away would only spend the hourly allowance.
  void _toCodeStep() {
    code.value = '';
    password.value = '';
    step.value = AuthStep.verify;
    _startCooldown();
  }

  void _stopCooldown() {
    _cooldown?.cancel();
    _cooldown = null;
    resendIn.value = 0;
  }

  void _startCooldown() {
    _cooldown?.cancel();
    resendIn.value = resendCooldownSeconds;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (resendIn.value <= 1) {
        _stopCooldown();
        return;
      }
      resendIn.value -= 1;
    });
  }
}
