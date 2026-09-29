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

/// The sign-in screen (D-250): email and password, a code emailed the first time, and a reset link.
///
/// The reactivity assertions are the point of most of these. The steps are separate widgets built
/// inside the page's `Obx`, which is exactly the arrangement that shipped a screen where tapping
/// changed the value and nothing rebuilt (D-88) — so every test taps and then asserts what the
/// user sees, never what the controller holds.
class StubAuth implements AuthRepository {
  String? lastIdToken;
  Either<Failure, Session> googleResult = const Left(ApiFailure('server said no', code: 'X'));
  Either<Failure, Session> signInResult = const Left(
    ApiFailure('Email or password is incorrect.', code: 'INVALID_CREDENTIALS'),
  );

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async {
    lastIdToken = idToken;
    return googleResult;
  }

  @override
  Future<Either<Failure, Session>> signIn({
    required String email,
    required String password,
  }) async => signInResult;

  @override
  Future<Either<Failure, Unit>> register({
    required String email,
    required String password,
    required String phoneE164,
  }) async => const Right(unit);

  @override
  Future<Either<Failure, Session>> verifyEmail({
    required String email,
    required String code,
  }) async => const Left(ApiFailure('that code is wrong', code: 'CODE_INVALID'));

  @override
  Future<Either<Failure, Unit>> resendCode(String email) async => const Right(unit);

  @override
  Future<Either<Failure, Unit>> forgotPassword(String email) async => const Right(unit);

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

/// The invisible field behind the six boxes owns the whole code — see `CodeStep`.
Finder get codeField => find.byType(TextField).first;

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

/// Typed, not poked into the controller: a button is only enabled by a rebuild that the field's
/// `onChanged` triggers, and that wiring is exactly what a reactivity bug would break.
Future<void> typeInto(WidgetTester tester, int field, String text) async {
  final target = find.byType(TextField).at(field);
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await settle(tester);
}

Future<void> reachSignUp(WidgetTester tester) => tapText(tester, l10n(tester).loginCreateAccount);

Future<void> reachCodeStep(WidgetTester tester) async {
  await reachSignUp(tester);
  await typeInto(tester, 0, 'asha@example.com');
  await typeInto(tester, 1, 'longenough');
  await typeInto(tester, 2, '9876543210');
  await tapText(tester, l10n(tester).loginCreateAccount);
  expect(Get.find<LoginController>().step.value, AuthStep.verify);
}

/// Runs the resend cooldown out.
///
/// Reaching the code step starts a periodic Timer, and the binding fails any test that ends with
/// one still pending — so every test that gets there has to reach the state a real user reaches by
/// waiting thirty seconds.
Future<void> waitOutCooldown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: LoginController.resendCooldownSeconds + 1));
  await settle(tester);
  expect(Get.find<LoginController>().resendIn.value, 0);
}

void main() {
  testWidgets('opens on email and password, with no phone or code in sight', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    expect(find.text(l.loginTitle), findsOneWidget);
    expect(find.text(l.loginEmailLabel), findsOneWidget);
    expect(find.text(l.loginPasswordLabel), findsOneWidget);
    expect(find.text(l.loginForgot), findsOneWidget);
    expect(find.text(l.loginPhoneLabel), findsNothing);
    expect(find.text(l.loginSecureBadge), findsOneWidget);
    // docs/05 §6: the disclaimer is on the first screen that collects anything, not buried.
    expect(find.text(l.copyDisclaimer), findsOneWidget);
    // Nothing to go back to behind this screen, so no arrow that would do nothing.
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('sign in lights up once both fields are typed, and shows the refusal', (
    tester,
  ) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    final c = Get.find<LoginController>();

    expect(c.canSignIn, isFalse);
    await typeInto(tester, 0, 'asha@example.com');
    await typeInto(tester, 1, 'wrongpass');
    await tapText(tester, l10n(tester).loginSignIn);

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('an unconfirmed address lands on the code boxes', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    auth.signInResult = const Left(
      ApiFailure('Confirm your email', code: LoginController.emailNotVerified),
    );

    await typeInto(tester, 0, 'asha@example.com');
    await typeInto(tester, 1, 'longenough');
    await tapText(tester, l10n(tester).loginSignIn);

    expect(find.text(l10n(tester).otpTitle), findsOneWidget);
    await waitOutCooldown(tester);
  });

  testWidgets('sign-up asks for the phone number, and its picker offers every country', (
    tester,
  ) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachSignUp(tester);
    final l = l10n(tester);

    expect(find.text(l.signUpTitle), findsOneWidget);
    expect(find.text(l.loginPrivacyNote), findsOneWidget);

    await tapText(tester, '+91');
    // Alphabetical, and Afghanistan heads it — not the one-entry list an India-only build shows.
    expect(find.text('Afghanistan'), findsOneWidget);
  });

  testWidgets('creating an account moves to the code, with a way back to the email', (
    tester,
  ) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachCodeStep(tester);
    final l = l10n(tester);

    expect(find.text(l.otpSubtitle('asha@example.com')), findsOneWidget);
    expect(find.text(l.otpChangeEmail), findsOneWidget);
    await tapText(tester, l.otpChangeEmail);
    expect(find.text(l.signUpTitle), findsOneWidget);
    await waitOutCooldown(tester);
  });

  testWidgets('the code the user types is what the boxes show', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachCodeStep(tester);

    await tester.enterText(codeField, '1234');
    await settle(tester);

    for (final digit in ['1', '2', '3', '4']) {
      expect(find.text(digit), findsOneWidget);
    }
    await waitOutCooldown(tester);
  });

  testWidgets('a wrong code shows the server message, verbatim (rule 7)', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await reachCodeStep(tester);

    await tester.enterText(codeField, '123456');
    await settle(tester);
    await tapText(tester, l10n(tester).otpVerify);

    expect(find.text('that code is wrong'), findsOneWidget);
    await waitOutCooldown(tester);
  });

  testWidgets('forgot password sends a link and answers the same either way', (tester) async {
    sizeAsPhone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    await typeInto(tester, 0, 'asha@example.com');
    await tapText(tester, l.loginForgot);
    expect(find.text(l.forgotTitle), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget, reason: 'the email carries over');

    await tapText(tester, l.forgotSend);
    expect(find.text(l.forgotSentBody('asha@example.com')), findsOneWidget);

    await tapText(tester, l.forgotBackToSignIn);
    expect(find.text(l.loginTitle), findsOneWidget);
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

  testWidgets('every step survives 200 % font scale without clipping (rule 12)', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(googleIdToken: () async => 't', scaler: const TextScaler.linear(2)),
    );
    await settle(tester);
    // A RenderFlex overflow throws into the binding, so a clean exception is the assertion.
    expect(tester.takeException(), isNull);

    await tapText(tester, l10n(tester).loginForgot);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);

    await reachCodeStep(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(l10n(tester).otpTitle), findsOneWidget);
    await waitOutCooldown(tester);
  });
}
