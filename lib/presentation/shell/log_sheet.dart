import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/activity_log_tab.dart';
import 'package:health_pro/presentation/shell/food_log_tab.dart';
import 'package:health_pro/presentation/shell/water_log_tab.dart';
import 'package:health_pro/presentation/shell/weight_log_tab.dart';

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

    final tabs = <({IconData icon, String label})>[
      (icon: Icons.restaurant_outlined, label: l10n.logFood),
      (icon: Icons.local_drink_outlined, label: l10n.logWater),
      (icon: Icons.monitor_weight_outlined, label: l10n.logWeight),
      (icon: Icons.directions_walk_outlined, label: l10n.logSteps),
    ];

    // The keyboard is the whole design constraint here: a fixed-height sheet leaves the search
    // results hidden behind it, which is exactly what the first build did. Take most of the screen
    // and subtract the keyboard, so the list always has room.
    final media = MediaQuery.of(context);
    final available = media.size.height * 0.9 - media.viewInsets.bottom - media.padding.top;

    return DefaultTabController(
      length: tabs.length,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: available.clamp(280.0, media.size.height),
            // No MainAxisSize.min: the height is already fixed above, and Expanded below needs
            // the column to fill it.
            child: Column(
              children: [
                // The reference lights the active tab rather than only underlining it (D-122): a
                // tinted pill behind the icon and label, with the underline kept so the change is
                // legible without relying on the tint alone (rule 12).
                TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  splashBorderRadius: BorderRadius.circular(AppRadius.card),
                  // Inside the bar, not around it: the tinted pill must not touch the sheet's
                  // edges — a rounded shape flush against a corner reads as a rendering fault —
                  // while the divider underneath still runs the full width, which is what makes
                  // it a rule under the tabs rather than a line of its own.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                    0,
                  ),
                  tabs: [for (final t in tabs) Tab(icon: Icon(t.icon), text: t.label)],
                ),
                // The tabs and the tab's own first control are two different things and need to
                // look it. Without this the search field sat on the divider.
                const SizedBox(height: AppSpacing.lg),
                const Expanded(
                  child: TabBarView(
                    children: [
                      FoodLogTab(),
                      // Water, entered a glass at a time (D-86).
                      WaterLogTab(),
                      // The Progress tab's own weight form, not a second one.
                      WeightLogTab(),
                      // Steps and calories burned, entered by hand (D-80).
                      ActivityLogTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
