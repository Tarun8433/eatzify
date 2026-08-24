import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The centre `+` sheet. docs/14 §1: "Log sheet: food · water · weight · steps. One sheet, four tabs.
/// Nothing else." The "nothing else" is the point — this is where the old build's nine-tile
/// hamburger menu used to leak back in.
class LogSheet extends StatelessWidget {
  const LogSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const LogSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final tabs = <({IconData icon, String label})>[
      (icon: Icons.restaurant_outlined, label: l10n.logFood),
      (icon: Icons.local_drink_outlined, label: l10n.logWater),
      (icon: Icons.monitor_weight_outlined, label: l10n.logWeight),
      (icon: Icons.directions_walk_outlined, label: l10n.logSteps),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                tabs: [for (final t in tabs) Tab(icon: Icon(t.icon), text: t.label)],
              ),
              SizedBox(
                height: 220,
                child: TabBarView(
                  children: [
                    for (final t in tabs)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            // Not wired: logging needs the food DB (E2) and the logs API (E4).
                            l10n.notAvailableYet(t.label),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
