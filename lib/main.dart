import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/network/api_client.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/billing_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/diary_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/google_auth_data_source.dart';
import 'package:health_pro/data/datasources/remote/measurements_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/plan_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/profile_remote_data_source.dart';
import 'package:health_pro/data/repositories/auth_repository_impl.dart';
import 'package:health_pro/data/repositories/billing_repository_impl.dart';
import 'package:health_pro/data/repositories/diary_repository_impl.dart';
import 'package:health_pro/data/repositories/measurements_repository_impl.dart';
import 'package:health_pro/data/repositories/pedometer_repository_impl.dart';
import 'package:health_pro/data/repositories/plan_repository_impl.dart';
import 'package:health_pro/data/repositories/profile_repository_impl.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/login_page.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/features/plan/plan_controller.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/features/splash/splash_page.dart';
import 'package:health_pro/presentation/features/welcome/welcome_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/client_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

void main() {
  runApp(const EatzifyApp());
}

/// Root. docs/14: GetX for state, routing and DI.
class EatzifyApp extends StatelessWidget {
  const EatzifyApp({super.key});

  /// Overridable so tests can inject fakes without touching the keychain or the network.
  static void Function()? bindingOverride;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // No themeMode: the default already follows the phone. docs/14 §5 wants a switch on the
      // settings screen; until that exists the OS setting is the user's stated preference, and
      // overriding it is the wrong default. Both themes are contrast-measured and render-tested.
      // docs/14 §5: the settings screen advertises a theme switch, so both themes must work.
      // themeMode defaults to ThemeMode.system — the honest default until that switch exists.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      initialBinding: BindingsBuilder<SessionController>(bindingOverride ?? _bind),
      // Tapping anywhere outside a field dismisses the keyboard, app-wide. Doing it here rather
      // than per-screen means a new page cannot forget it.
      builder: (context, child) => GestureDetector(
        // Translucent so the tap still reaches whatever was underneath — this dismisses the
        // keyboard without swallowing the button the user was actually aiming for.
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: const RootGate(),
    );
  }

  static void _bind() {
    // BACKEND_DOMAIN from api/.env.example. A device cannot reach the host's localhost, so this
    // needs a reachable address before sign-in works.
    //
    // The dev default is the Mac's BONJOUR NAME, not its LAN IP (D-93). A baked IP is wrong the
    // first time the machine changes network: this one was 192.168.2.18, became 172.20.10.4 on a
    // phone hotspot, and was back on 192.168.2.18 an hour later — each change is a 20-second
    // connection timeout with no clue as to why. `.local` is resolved by mDNS and follows the
    // machine, so it survives all of that without a rebuild. On a physical iPhone it needs the
    // local-network permission declared in ios/Runner/Info.plist.
    //
    // ponytail: override per-machine with --dart-define=API_BASE_URL=... — a tunnel URL, or
    // another developer's own hostname.
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://THINKs-MacBook-Air.local:3001/api/v1',
    );
    final client = ApiClient(baseUrl: baseUrl);
    final auth = AuthRepositoryImpl(AuthRemoteDataSource(client.dio));
    // Held rather than only registered: SessionController reads it on boot to check a cached
    // `onboarding_required` against the server.
    final profile = ProfileRepositoryImpl(ProfileRemoteDataSource(client.dio));
    Get
      ..put<ProfileRepository>(profile, permanent: true)
      ..put<MeasurementsRepository>(
        MeasurementsRepositoryImpl(MeasurementsRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<DiaryRepository>(
        DiaryRepositoryImpl(DiaryRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<PlanRepository>(PlanRepositoryImpl(PlanRemoteDataSource(client.dio)), permanent: true)
      ..put<BillingRepository>(
        BillingRepositoryImpl(BillingRemoteDataSource(client.dio)),
        permanent: true,
      )
      // CMPedometer over our own channel (D-99). Registered on every platform; it reports
      // `unsupported` where there is nothing behind it, and Home simply carries no step count.
      ..put<HealthRepository>(PedometerRepositoryImpl(), permanent: true);
    final session = Get.put(
      SessionController(store: SecureStore(), auth: auth, profile: profile),
      permanent: true,
    );
    client.attachAuth(
      accessToken: () => session.accessToken,
      onRefresh: session.refreshAccessToken,
    );
    Get
      ..put(NavController(), permanent: true)
      ..lazyPut(
        () => LoginController(
          auth: auth,
          session: session,
          // Only when the OAuth client id was built in — see GoogleAuthDataSource. Unconfigured,
          // this is null and the sign-in screen simply has no Google button on it.
          googleIdToken: GoogleAuthDataSource.isConfigured ? GoogleAuthDataSource().idToken : null,
        ),
        fenix: true,
      );

    attachSessionCleanup(session);
  }

  /// Wires [clearUserScopedState] to the end of a session.
  ///
  /// The worker is never disposed on purpose: it lives exactly as long as the app, and a binding
  /// that quietly stopped listening would bring the bug straight back.
  static void attachSessionCleanup(SessionController session) {
    ever(session.status, (status) {
      if (status == AuthStatus.signedOut) clearUserScopedState();
    });
  }

  /// Drops everything holding one user's data.
  ///
  /// Every tab controller is registered `permanent: true`, and `Get.put` hands back an existing
  /// instance WITHOUT re-running `onInit`. So after a sign-out and a sign-in as somebody else, the
  /// same four controllers were still holding the previous user's diary, plan, measurements and
  /// profile, and nothing ever asked them to reload — the data only changed on a restart. Deleting
  /// them means the next `Get.put` builds a fresh one, which loads for whoever is signed in now.
  ///
  /// docs/13 also wants it gone at sign-out rather than at the next sign-in: health data must not
  /// sit in memory after the person it belongs to has left.
  static void clearUserScopedState() {
    void drop<T>() {
      if (Get.isRegistered<T>()) Get.delete<T>(force: true);
    }

    drop<HomeController>();
    drop<PlanController>();
    drop<ProgressController>();
    drop<AccountController>();
    // Holds a half-finished set of answers, which the next person must not inherit.
    drop<OnboardingController>();

    // Not user data, so it is reset rather than dropped: the next sign-in should open on Home, not
    // on whichever tab the last person happened to leave behind.
    if (Get.isRegistered<NavController>()) Get.find<NavController>().current = ClientTab.home;
  }
}

/// The only place routing depends on auth state. docs/14 §3 asks for guards declared on routes
/// rather than checks inside pages; with four states and three destinations, one exhaustive switch
/// at the root is the same guarantee with less machinery — and it cannot be forgotten on a new page.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionController>();
    return Obx(
      () => switch (session.status.value) {
        AuthStatus.restoring => const SplashPage(),
        // Splash → intro → sign-in → registration (D-92). `signedOut` covers the first two
        // destinations because being signed out is the only thing they have in common; the
        // carousel is not an auth state and must not become one.
        AuthStatus.signedOut => session.introSeen.value ? const LoginPage() : const WelcomePage(),
        // Signed in with a number the server has no profile for — the registration screen.
        AuthStatus.onboardingRequired => const OnboardingPage(),
        AuthStatus.signedIn => const ClientShell(),
      },
    );
  }
}
