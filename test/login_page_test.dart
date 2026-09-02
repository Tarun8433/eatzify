import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/login_page.dart';
import 'package:health_pro/presentation/features/auth/widgets/google_button.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// The sign-in screen (D-109): two steps on one page, plus the Google route beside the phone one.
///
/// The reactivity assertions are the point of most of these. The steps are separate widgets built
/// inside the page's `Obx`, which is exactly the arrangement that shipped a screen where tapping
/// changed the value and nothing rebuilt (D-88) — so every test taps and then asserts what the
/// user sees, never what the controller holds.
class StubAuth implements AuthRepository {
  String? lastIdToken;
  Either<Failure, Session> googleResult = const Left(ApiFailure('server said no', code: 'X'));

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async {
    lastIdToken = idToken;
    return googleResult;
  }

  @override
  Future<Either<Failure, Unit>> requestOtp(String phoneE164) async => const Right(unit);

  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async => const Left(ApiFailure('that code is wrong', code: 'OTP_INVALID'));

  @override
  Future<Either<Failure, Session>> refresh(Session current) async =>
      const Left(ApiFailure('x', code: 'X'));

  @override
  Future<Either<Failure, Unit>> logout(Session current) async => const Right(unit);
}

late StubAuth auth;

/// [googleIdToken] null is the unconfigured build — no OAuth client id, so no button.
Widget app({Future<String?> Function()? googleIdToken, TextScaler? scaler}) {
  Get.reset();
  auth = StubAuth();
  final session = putFakeSession();
  Get.put(LoginController(auth: auth, session: session, googleIdToken: googleIdToken));

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: scaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          ),
    home: const LoginPage(),
  );
}

/// A phone-shaped surface. The default 800x600 test window puts the whole page above the fold, so
/// nothing scrolls and a `ListView` never unbuilds the top row the way it does on a real device.
void sizeAsPhone(WidgetTester tester, {double height = 900}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LoginPage)));

/// The invisible field behind the six boxes owns the whole code — see `OtpStep`.
Finder get codeField => find.byType(TextField).first;

Future<void> reachOtpStep(WidgetTester tester) async {
  // Typed, not poked into the controller: the button is only enabled by a rebuild that the field's
  // `onChanged` triggers, and that wiring is exactly what a reactivity bug would break.
  //
  // Scrolled to first because at 200 % font scale the field is below the fold, and a `ListView`
  // does not build what is off-screen — the widget a finder cannot see does not exist yet.
  await scrollTo(tester, find.byType(TextField));
  await tester.enterText(find.byType(TextField).first, '9876543210');
  await settle(tester);

  final send = find.text(l10n(tester).loginSendCode);
  await tester.ensureVisible(send);
  await settle(tester);
  await tester.tap(send);
  await settle(tester);
  expect(Get.find<LoginController>().codeSent.value, isTrue);
}

/// Runs the resend cooldown out.
///
/// Sending a code starts a periodic Timer, and the binding fails any test that ends with one still
/// pending — so every test that sends has to reach the state a real user reaches by waiting thirty
/// seconds. Asserting the button comes back is the point of doing it this way rather than reaching
/// into the controller to cancel.
Future<void> waitOutCooldown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: LoginController.resendCooldownSeconds + 1));
  await settle(tester);
  expect(Get.find<LoginController>().resendIn.value, 0);
}

void main() {
  testWidgets('the phone step asks for a number and says what happens to it', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    expect(find.text(l.loginTitle), findsOneWidget);
    expect(find.text(l.loginPrivacyNote), findsOneWidget);
    expect(find.text(l.loginSecureBadge), findsOneWidget);
    // docs/05 §6: the disclaimer is on the first screen that collects anything, not buried.
    expect(find.text(l.copyDisclaimer), findsOneWidget);
    // Nothing to go back to behind this screen, so no arrow that would do nothing.
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('the country picker offers every country, not just India', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    // The prefix is the picker. India is the default because it is the market, not a fence.
    await tester.tap(find.text('+91'));
    await settle(tester);

    // The list is alphabetical and Afghanistan heads it — proof the picker is not the one-entry
    // list an India-only build would show.
    expect(find.text('Afghanistan'), findsOneWidget);
  });

  testWidgets('a number is capped at the length its country actually uses', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    final c = Get.find<LoginController>();

    // India: ten. The eleventh digit is refused by the field, not merely rejected on submit.
    await tester.enterText(find.byType(TextField).first, '98765432109');
    await settle(tester);
    expect(c.phone.value.length, 10);
    expect(c.isPhoneValid, isTrue);

    // A shorter country takes its own length, and clears what was typed for the last one.
    c.setCountry(dial: '+34', minLength: 9, maxLength: 9);
    await settle(tester);
    expect(c.phone.value, isEmpty);
    expect(find.text('9876543210'), findsNothing, reason: 'and the field on screen is cleared too');
  });

  testWidgets('sending a code moves to the six boxes and offers a way back', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachOtpStep(tester);
    final l = l10n(tester);

    expect(find.text(l.otpTitle), findsOneWidget);
    expect(find.text(l.otpChangeNumber), findsOneWidget);
    // The arrow appears only here, where "back" means "fix the number".
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    expect(find.text(l.loginTitle), findsOneWidget, reason: 'back returns to the number');
    await waitOutCooldown(tester);
  });

  testWidgets('the code the user types is what the boxes show', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachOtpStep(tester);

    await tester.enterText(codeField, '1234');
    await settle(tester);

    // Rendered digits, not controller state: the boxes are drawn by a widget that could easily
    // stop rebuilding without any test of the controller noticing.
    for (final digit in ['1', '2', '3', '4']) {
      expect(find.text(digit), findsOneWidget);
    }
    await waitOutCooldown(tester);
  });

  testWidgets('a wrong code shows the server message, verbatim (rule 7)', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachOtpStep(tester);

    await tester.enterText(codeField, '123456');
    await settle(tester);
    final verify = find.text(l10n(tester).otpVerify);
    await tester.ensureVisible(verify);
    await settle(tester);
    await tester.tap(verify);
    await settle(tester);

    expect(find.text('that code is wrong'), findsOneWidget);
    await waitOutCooldown(tester);
  });

  group('Google', () {
    testWidgets('is absent when the build carries no OAuth client id', (tester) async {
      sizeAsPhone(tester);
      await tester.pumpWidget(app());
      await settle(tester);

      // A sign-in option that cannot possibly succeed is worse than no option.
      expect(find.byType(GoogleButton), findsNothing);
      expect(find.text(l10n(tester).loginOr), findsNothing);
    });

    testWidgets('sends the token it was given to the server', (tester) async {
      sizeAsPhone(tester);
      await tester.pumpWidget(app(googleIdToken: () async => 'id-token-1'));
      await settle(tester);

      await tester.ensureVisible(find.byType(GoogleButton));
      await settle(tester);
      await tester.tap(find.byType(GoogleButton));
      await settle(tester);

      expect(auth.lastIdToken, 'id-token-1');
      expect(find.text('server said no'), findsOneWidget, reason: 'and renders what came back');
    });

    testWidgets('says nothing when the user backs out of the Google sheet', (tester) async {
      // Cancelling returns null. It is a decision, not a fault, and answering it with red text
      // reads as something the user has to fix.
      sizeAsPhone(tester);
      await tester.pumpWidget(app(googleIdToken: () async => null));
      await settle(tester);

      await tester.ensureVisible(find.byType(GoogleButton));
      await settle(tester);
      await tester.tap(find.byType(GoogleButton));
      await settle(tester);

      expect(auth.lastIdToken, isNull);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(Get.find<LoginController>().busy.value, isFalse, reason: 'and is not left spinning');
    });

    testWidgets('explains itself when the plugin throws', (tester) async {
      sizeAsPhone(tester);
      await tester.pumpWidget(app(googleIdToken: () async => throw Exception('no play services')));
      await settle(tester);

      await tester.ensureVisible(find.byType(GoogleButton));
      await settle(tester);
      await tester.tap(find.byType(GoogleButton));
      await settle(tester);

      // Client-owned copy, because this failure never reached the server — and never the
      // exception's own text.
      expect(find.text(l10n(tester).loginGoogleFailed), findsOneWidget);
      expect(find.textContaining('no play services'), findsNothing);
    });
  });

  testWidgets('both steps survive 200 % font scale without clipping (rule 12)', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(googleIdToken: () async => 't', scaler: const TextScaler.linear(2)),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);

    await reachOtpStep(tester);
    // A RenderFlex overflow throws into the binding, so a clean exception is the assertion: the
    // six boxes and the two link buttons have to survive doubling, not just fit at 100 %.
    expect(tester.takeException(), isNull);
    expect(find.text(l10n(tester).otpTitle), findsOneWidget);
    await waitOutCooldown(tester);
  });
}
