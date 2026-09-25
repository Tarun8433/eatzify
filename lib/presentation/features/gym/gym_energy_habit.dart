import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/presentation/features/gym/gym_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Progress's workout-energy row (D-242): the last week as bars, beside the other daily habits.
/// Its own figure, from the server's estimate — never folded into calories burned. Draws nothing
/// until there is something to draw, or where no Gym is registered.
class GymEnergyHabit extends StatefulWidget {
  const GymEnergyHabit({super.key});

  @override
  State<GymEnergyHabit> createState() => _GymEnergyHabitState();
}

class _GymEnergyHabitState extends State<GymEnergyHabit> {
  static const _days = 7;
  List<int?>? _week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Get.isRegistered<GymRepository>()) return;
    final result = await Get.find<GymRepository>().stats();
    if (!mounted) return;
    result.fold((_) {}, (stats) {
      final days = stats.energyDays;
      final week = days.sublist(days.length > _days ? days.length - _days : 0);
      if (week.any((d) => d.kcal != null)) setState(() => _week = [for (final d in week) d.kcal]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    if (week == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final peak = week.fold<int>(0, (top, k) => (k ?? 0) > top ? k! : top);
    final total = week.fold<int>(0, (sum, k) => sum + (k ?? 0));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => GymPage.open(initialTab: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.gymKcalTitle, style: theme.textTheme.bodyMedium)),
                Text(
                  l.gymKcalValue(total),
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: AppSizes.habitBar,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final kcal in week)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: kcal == null || peak == 0
                              ? 0
                              : (kcal / peak).clamp(0.06, 1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(AppRadius.card),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(l.gymThisWeek, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
