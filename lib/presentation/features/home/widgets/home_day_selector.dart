import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Which diary day is on screen: round arrows either side of a "Today ⌄" pill that opens a
/// calendar (D-128).
///
/// The arrows and the calendar all speak in days BACK from today — never a date the app sends —
/// because the server owns where a day begins (04:00 IST, rule 8). The calendar only turns the
/// picked date into that count.
class HomeDaySelector extends StatelessWidget {
  const HomeDaySelector({required this.controller, super.key});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Obx(() {
      final back = controller.daysBack.value;
      final label = switch (back) {
        0 => l.homeDayToday,
        1 => l.homeDayYesterday,
        _ => DateFormat.MMMEd(locale).format(DateTime.now().subtract(Duration(days: back))),
      };

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundArrow(
                icon: Icons.chevron_left_rounded,
                tooltip: l.homeDayEarlier,
                onPressed: back >= HomeController.maxDaysBack ? null : controller.showEarlierDay,
              ),
              Expanded(
                child: Center(
                  child: _DayPill(label: label, onTap: () => _pick(context, back)),
                ),
              ),
              _RoundArrow(
                icon: Icons.chevron_right_rounded,
                // Dead on today, because there is no diary for tomorrow — and a control that is
                // present but does nothing is worse than one that says it cannot.
                tooltip: l.homeDayLater,
                onPressed: controller.isToday ? null : controller.showLaterDay,
              ),
            ],
          ),
          // The `+` writes to today wherever the user is standing (the server decides the day), so
          // a past day has to say so before somebody logs breakfast into the wrong one.
          if (!controller.isToday)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l.homeDayPast,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      );
    });
  }

  Future<void> _pick(BuildContext context, int back) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      helpText: AppLocalizations.of(context).homePickDay,
      initialDate: today.subtract(Duration(days: back)),
      firstDate: today.subtract(const Duration(days: HomeController.maxDaysBack)),
      lastDate: today,
    );
    if (picked == null) return;
    await controller.showDaysBack(today.difference(picked).inDays);
  }
}

/// A round, raised arrow — the reference's own, rather than a bare chevron.
class _RoundArrow extends StatelessWidget {
  const _RoundArrow({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surface.withValues(alpha: _glass),
        disabledBackgroundColor: scheme.surface.withValues(alpha: _glass / 2),
        foregroundColor: scheme.primary,
        minimumSize: const Size.square(AppSpacing.minTouchTarget),
        elevation: 0,
      ),
      icon: Icon(icon),
    );
  }
}

/// The day's name in a white pill with a calendar mark and a down-arrow, saying it opens a picker.
class _DayPill extends StatelessWidget {
  const _DayPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: Icon(Icons.calendar_month_outlined, color: scheme.primary)),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                ExcludeSemantics(
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The arrows sit on the landscape; a little see-through, as the reference has them.
const _glass = 0.75;
