import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/client_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

void main() {
  runApp(const EatzifyApp());
}

/// Root. docs/14: GetX for state, routing and DI.
///
/// The app opens straight into the client shell. Onboarding, auth and the coach shell come with E1
/// and E6 — routing them here before they exist would be scaffolding for its own sake.
class EatzifyApp extends StatelessWidget {
  const EatzifyApp({super.key});

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
      initialBinding: BindingsBuilder<NavController>(() {
        Get.put(NavController(), permanent: true);
      }),
      // docs/14 §6: onboarding precedes the shell. Routing is a straight swap until E1 lands auth
      // and the real OnboardingGuard — a guard that checks nothing is worse than no guard.
      home: const OnboardingPage(),
      getPages: [
        GetPage(name: '/onboarding', page: OnboardingPage.new),
        GetPage(name: '/home', page: ClientShell.new),
      ],
    );
  }
}
