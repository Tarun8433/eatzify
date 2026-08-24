import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/account/account_page.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/features/plan/plan_page.dart';
import 'package:health_pro/presentation/features/progress/progress_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/log_sheet.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

/// The ONE client shell. docs/14 §1:
///
///     Home    Plan    [ + ]    Progress    You
///
/// Deleted on purpose and not to be reintroduced: the hamburger menu, the separate Diary and Log
/// tabs, the Reports/Trends split, the Tracker/Diet Plan/Progress shell, and the per-screen
/// back-arrow-plus-Menu-pill pattern. Adding a tab requires an ADR.
class ClientShell extends StatelessWidget {
  const ClientShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavController>();
    final l10n = AppLocalizations.of(context);

    return Obx(() {
      final tab = nav.selected.value;
      return Scaffold(
        body: SafeArea(
          child: switch (tab) {
            ClientTab.home => const HomePage(),
            ClientTab.plan => const PlanPage(),
            ClientTab.progress => const ProgressPage(),
            ClientTab.you => const AccountPage(),
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => LogSheet.show(context),
          tooltip: l10n.logEntry,
          child: const Icon(Icons.add, size: AppSpacing.xl),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: NavigationBar(
          selectedIndex: nav.indexOf(tab),
          onDestinationSelected: (i) => nav.current = ClientTab.values[i],
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.tabHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.restaurant_menu_outlined),
              selectedIcon: const Icon(Icons.restaurant_menu),
              label: l10n.tabPlan,
            ),
            NavigationDestination(
              icon: const Icon(Icons.show_chart_outlined),
              selectedIcon: const Icon(Icons.show_chart),
              label: l10n.tabProgress,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.tabYou,
            ),
          ],
        ),
      );
    });
  }
}
