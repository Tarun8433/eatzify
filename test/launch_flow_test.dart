import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/main.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/login_page.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/features/splash/splash_page.dart';
import 'package:health_pro/presentation/features/welcome/welcome_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// The order the app opens in (D-92): splash → intro → sign-in → registration.
///
/// The user reported landing on the registration screen at launch. It was correct for their stored
/// state — signed in, no profile — but three destinations before it had no way to be reached, so
/// this asserts the whole ladder rather than one rung.

class FakeStorage extends FlutterSecureStorage {
  FakeStorage() : super();
  final data = <String, String>{};

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
  }) async => value == null ? data.remove(key) : data[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

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
  @override
  Future<Either<Failure, Session>> refresh(Session c) async =>
      const Left(ApiFailure('no', code: 'X', status: 401));
  @override
  Future<Either<Failure, Unit>> logout(Session c) async => const Right(unit);
  @override
  Future<Either<Failure, Unit>> requestOtp(String phone) async => const Right(unit);
  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async => const Left(ApiFailure('no', code: 'X', status: 401));
  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async => const Left(ApiFailure('no', code: 'X', status: 401));
}

late FakeStorage storage;
late SessionController session;

/// [RootGate] under the real app scaffolding, with the keychain and network faked.
///
/// A real splash floor is kept — the point of the screen is that it is visible for longer than a
/// frame, so a test that zeroed it could not tell the fix from the bug.
Widget appUnderTest({Duration splashFloor = SessionController.splashMinimum, FakeStorage? reuse}) {
  Get.reset();
  // `reuse` is the same keychain surviving a restart — the only way to test "shown once" as
  // something that outlives the process rather than something a live object remembers.
  storage = reuse ?? FakeStorage();
  final auth = _FakeAuth();
  session = Get.put(
    SessionController(
      store: SecureStore(storage: storage),
      auth: auth,
      // `Right(null)` — the server has no profile either — so a session cached as needing
      // onboarding stays that way. The reconciliation itself is tested in session_controller_test.
      profile: FakeProfileRepository(profileResult: const Right(null)),
      splashFloor: splashFloor,
    ),
    permanent: true,
  );
  // The onboarding page is one of RootGate's four destinations, so its dependencies have to
  // resolve even in the tests that never reach it.
  Get
    ..lazyPut(() => LoginController(auth: auth, session: session), fenix: true)
    ..put<ProfileRepository>(FakeProfileRepository(), permanent: true)
    ..put<PlanRepository>(FakePlanRepository(plan: samplePlan), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const RootGate(),
  );
}

void main() {
  testWidgets('a fresh install opens on the splash, not on a form', (tester) async {
    await tester.pumpWidget(appUnderTest());
    await tester.pump();

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing, reason: 'the reported bug');

    // Still there most of a second later. Without the floor the splash was one frame — long enough
    // to flicker, not long enough to be a screen.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(SplashPage), findsOneWidget);

    await settle(tester);
    expect(find.byType(WelcomePage), findsOneWidget, reason: 'splash hands over to the intro');
  });

  testWidgets('the splash shows the walker, not an empty screen', (tester) async {
    await tester.pumpWidget(appUnderTest());
    await tester.pump();

    // The frame sequence mounts an Image per frame. Asserting on the widget rather than on pixels:
    // bundled PNGs do not decode under `flutter test`, so a golden of this screen is blank whether
    // the asset path is right or wrong.
    expect(
      find.descendant(of: find.byType(SplashPage), matching: find.byType(Image)),
      findsWidgets,
    );
    expect(find.text('Eatzify'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('the intro comes before sign-in, and finishing it reaches sign-in', (tester) async {
    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero));
    await settle(tester);

    final l = AppLocalizations.of(tester.element(find.byType(WelcomePage)));
    expect(find.textContaining(l.welcomeSlide1Title, findRichText: true), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing, reason: 'the phone number is not asked for first');

    // `textContaining` because the headline carries a decorative leaf as an inline WidgetSpan
    // (D-102 art direction), which puts an object-replacement character in its plain text.
    // Through all three cards.
    await tester.tap(find.text(l.welcomeNext));
    await settle(tester);
    expect(find.textContaining(l.welcomeSlide2Title, findRichText: true), findsOneWidget);
    await tester.tap(find.text(l.welcomeNext));
    await settle(tester);
    expect(find.textContaining(l.welcomeSlide3Title, findRichText: true), findsOneWidget);

    await tester.tap(find.text(l.welcomeStart));
    await settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('skipping the intro also reaches sign-in', (tester) async {
    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero));
    await settle(tester);

    await tester.tap(
      find.text(AppLocalizations.of(tester.element(find.byType(WelcomePage))).welcomeSkip),
    );
    await settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the intro is shown once — a second launch goes straight to sign-in', (tester) async {
    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero));
    await settle(tester);
    await session.markIntroSeen();
    final disk = storage;

    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero, reuse: disk));
    await settle(tester);

    expect(find.byType(WelcomePage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('signing out does not replay the intro', (tester) async {
    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero));
    await settle(tester);
    await session.markIntroSeen();
    await session.adopt(
      const Session(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'u',
        roles: ['client'],
        onboardingRequired: false,
      ),
    );

    await session.signOut(revokeOnServer: false);
    await settle(tester);

    expect(
      find.byType(WelcomePage),
      findsNothing,
      reason: 'signing out is not the same as never having used the app',
    );
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('a signed-in user with no profile still lands on registration', (tester) async {
    await tester.pumpWidget(appUnderTest(splashFloor: Duration.zero));
    await settle(tester);
    await session.adopt(
      const Session(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'u',
        roles: ['client'],
        onboardingRequired: true,
      ),
    );
    await settle(tester);

    expect(find.byType(OnboardingPage), findsOneWidget, reason: 'the last rung of the ladder');
  });
}
