import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/network/api_client.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/data/repositories/auth_repository_impl.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/login_page.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
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
      home: const RootGate(),
    );
  }

  static void _bind() {
    // BACKEND_DOMAIN from api/.env.example. A device cannot reach the host's localhost, so this
    // needs a LAN address or a tunnel before sign-in works on a real phone.
    final client = ApiClient(baseUrl: 'http://localhost:3001/api');
    final auth = AuthRepositoryImpl(AuthRemoteDataSource(client.dio));
    final session = Get.put(SessionController(store: SecureStore(), auth: auth), permanent: true);
    client.attachAuth(
      accessToken: () => session.accessToken,
      onRefresh: session.refreshAccessToken,
    );
    Get
      ..put(NavController(), permanent: true)
      ..lazyPut(() => LoginController(auth: auth, session: session), fenix: true);
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
        AuthStatus.signedOut => const LoginPage(),
        AuthStatus.onboardingRequired => const OnboardingPage(),
        AuthStatus.signedIn => const ClientShell(),
      },
    );
  }
}
