import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/animated_count.dart';
import 'package:health_pro/core/widgets/day_dot.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// The Progress dashboard's cards (D-143), modelled on the reference mock. Everything here reads
/// figures the server sent — sums, targets, diary dates — and the one liberty taken is display
/// arithmetic (a mean, a ratio) in the controller, never a target or a judgement.

/// The section chips: Overview · Nutrition · Weight · Activity · Habits, one white bar.
class SectionChips extends StatelessWidget {
  const SectionChips({required this.controller, super.key});

  final ProgressController controller;

  static IconData _icon(String section) => switch (section) {
    'overview' => Icons.bar_chart,
    'nutrition' => Icons.restaurant_outlined,
    'weight' => Icons.monitor_weight_outlined,
    'activity' => Icons.directions_run,
    _ => Icons.track_changes,
  };

  /// CLAUDE.md rule 4: a section is a wire-ish key and l10n on screen.
  static String _label(AppLocalizations l, String section) => switch (section) {
    'overview' => l.progressSectionOverview,
    'nutrition' => l.progressSectionNutrition,
    'weight' => l.progressWeight,
    'activity' => l.progressSectionActivity,
    _ => l.progressSectionHabits,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Its own Obx: an ancestor's does not track reads made in a child's build.
    return Obx(() {
      final active = controller.section.value;

      return Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        // Scrolls sideways rather than clipping: five labels at 200 % text are wider than any
        // phone (rule 12).
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final section in ProgressController.sections)
                Semantics(
                  button: true,
                  selected: section == active,
                  child: InkWell(
                    onTap: () => controller.section.value = section,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.minTouchTarget,
                        minWidth: AppSpacing.minTouchTarget + AppSpacing.lg,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: section == active ? scheme.secondaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              _icon(section),
                              size: AppSpacing.lg,
                              color: section == active
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs / 2),
                          Text(
                            _label(l, section),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: section == active
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                              fontWeight: section == active ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// The heading's period pill: a calendar glyph, the window's name, a menu of the two windows.
class PeriodPill extends StatelessWidget {
  const PeriodPill({required this.controller, super.key});

  final ProgressController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Obx(() {
      final label = controller.period.value == 0
          ? l.progressPeriodThisWeek
          : l.progressPeriodLastWeek;

      return Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: PopupMenuButton<int>(
          tooltip: label,
          onSelected: (value) => controller.period.value = value,
          itemBuilder: (context) => [
            PopupMenuItem(value: 0, child: Text(l.progressPeriodThisWeek)),
            PopupMenuItem(value: 1, child: Text(l.progressPeriodLastWeek)),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: AppSpacing.lg, color: scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                Icon(Icons.expand_more, size: AppSpacing.lg, color: scheme.primary),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The calorie card: the period's average, the goal, the ring, and the seven days as bars under
/// a dashed goal line. Bars and figures stay one colour whatever the day did — the mock paints
/// an under-goal day amber, and docs/05 §6 is why this build does not.
class CalorieProgressCard extends StatelessWidget {
  const CalorieProgressCard({required this.controller, super.key});

  final ProgressController controller;

  static const _ring = 76.0;
  static const _chartHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Obx(() {
      final period = controller.period.value;
      final avg = controller.avgKcal(period);
      final goal = controller.goalKcal;
      final delta = controller.vsLastWeekPct;
      final days = controller.week(period);
      final dates = controller.weekDates(period);
      if (avg == null && days.whereType<DiaryDay>().isEmpty) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.progressCalorieTitle,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (avg != null) ...[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              AnimatedCount(
                                value: avg,
                                semanticsLabel: '${avg.round()} kcal',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: AppSpacing.xs,
                                  bottom: AppSpacing.xs / 2,
                                ),
                                child: Text('kcal', style: theme.textTheme.bodySmall),
                              ),
                            ],
                          ),
                        ),
                        Text(l.progressAvgConsumed, style: theme.textTheme.bodySmall),
                      ],
                      if (goal != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l.progressGoalKcal(goal.round()),
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  children: [
                    ProgressRing(
                      size: _ring,
                      strokeWidth: 6,
                      // Two server figures or nothing (rule 2): no goal, no fill.
                      progress: avg == null || goal == null ? null : avg / goal,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              avg == null || goal == null ? '—' : '${(avg / goal * 100).round()}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(l.progressOfGoal, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    if (delta != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              delta >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                              size: AppSpacing.md,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          // Stated, not scored: eating more than last week is a fact, so the line
                          // keeps the caption's own ink (docs/05 §6).
                          Text(l.progressVsLastWeek(delta.abs()), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _WeekBars(
              days: days,
              dates: dates,
              goal: goal,
              isCurrentWeek: period == 0,
              locale: locale,
              height: _chartHeight,
              goalLabel: goal == null
                  ? null
                  : '${NumberFormat.decimalPattern(locale).format(goal.round())} kcal ${l.progressGoalLabel}',
            ),
          ],
        ),
      );
    });
  }
}

/// Seven days as bars: the figure above each bar, the weekday under it, today's chip filled, and
/// the goal as a dashed line. A day the server has nothing for draws no bar and no figure —
/// absent is not zero.
class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.days,
    required this.dates,
    required this.goal,
    required this.isCurrentWeek,
    required this.locale,
    required this.height,
    required this.goalLabel,
  });

  final List<DiaryDay?> days;
  final List<String> dates;
  final double? goal;
  final bool isCurrentWeek;
  final String locale;
  final double height;
  final String? goalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numbers = NumberFormat.decimalPattern(locale);

    final values = [for (final d in days) d != null && d.entries.isNotEmpty ? d.totals.kcal : null];
    final peak = [
      goal ?? 0,
      ...values.whereType<double>(),
    ].fold<double>(0, (top, v) => v > top ? v : top);
    if (peak <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (goalLabel != null)
          Align(
            alignment: Alignment.centerRight,
            child: Text(goalLabel!, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: height,
          child: Stack(
            children: [
              if (goal != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * (goal! / peak).clamp(0.0, 1.0) - 1,
                  child: CustomPaint(
                    size: const Size(double.infinity, 1),
                    painter: _DashedLinePainter(color: scheme.outline),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, value) in values.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (value != null) ...[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  numbers.format(value.round()),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs / 2),
                              Flexible(
                                child: FractionallySizedBox(
                                  // Against the tallest thing on the chart, floored so a light
                                  // day still reads as logged.
                                  heightFactor: (value / peak).clamp(0.06, 1.0),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      // Today is the paler bar in the mock — in progress, not
                                      // yet a day to compare.
                                      color: isCurrentWeek && i == values.length - 1
                                          ? scheme.primary.withValues(alpha: 0.35)
                                          : scheme.primary.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(AppRadius.card / 2),
                                    ),
                                    child: const SizedBox(width: double.infinity),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final (i, date) in dates.indexed)
              Expanded(
                child: Center(
                  child: _dayLabel(context, date, isToday: isCurrentWeek && i == dates.length - 1),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _dayLabel(BuildContext context, String iso, {required bool isToday}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateTime.tryParse(iso);
    final label = date == null ? '' : DateFormat.E(locale).format(date);

    if (!isToday) {
      return Text(label, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs / 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + _dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// The three macros averaged over the period, each a bar against the server's target with the
/// ratio as a tinted chip — the mock's row, in the app's macro colours.
class MacroBalanceCard extends StatelessWidget {
  const MacroBalanceCard({required this.controller, this.onDetails, super.key});

  final ProgressController controller;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Obx(() {
      final avg = controller.avgMacros(controller.period.value);
      final targets = controller.latestTargets;
      if (avg == null || targets == null) return const SizedBox.shrink();

      final macros = [
        (l.homeProtein, avg.protein, targets.proteinG, AppColors.macroProtein),
        (l.homeCarbs, avg.carb, targets.carbG, AppColors.macroCarb),
        (l.homeFat, avg.fat, targets.fatG, AppColors.macroFat),
      ];

      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.progressMacroTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(l.progressMacroWindow, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (onDetails != null)
                  TextButton(
                    onPressed: onDetails,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.homeDetails),
                        const Icon(Icons.chevron_right, size: AppSpacing.lg),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                // Side by side like the mock, stacked when 200 % text needs the width (rule 12).
                final stacked = constraints.maxWidth < AppSizes.heroBreakpoint;
                final children = [
                  for (final (label, value, target, color) in macros)
                    _MacroColumn(label: label, value: value, target: target, color: color),
                ];

                if (stacked) {
                  return Column(
                    children: [
                      for (final child in children)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: child,
                        ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, child) in children.indexed) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.lg),
                      Expanded(child: child),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
    });
  }
}

class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = target <= 0 ? null : (value / target * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${value.round()} g / ${target.round()} g',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            // The bar clamps; the chip's number does not (docs/05 §6).
            value: target <= 0 ? 0 : (value / target).clamp(0.0, 1.0),
            minHeight: AppSizes.barHeight * 0.75,
            color: color,
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
        if (pct != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs / 2,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$pct%',
              style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

/// Days-with-anything-logged out of the last seven, with the week as the shared [DayDot] chips.
/// A logging count, never a weight streak (docs/05 §6) — and at nought the card is simply not
/// there, because "0 / 7" is the failure banner the tone rules exist to prevent.
class ConsistencyCard extends StatelessWidget {
  const ConsistencyCard({required this.controller, super.key});

  final ProgressController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Obx(() {
      final dates = controller.weekDates(0);
      final logged = controller.loggedThisWeek;
      if (dates.isEmpty || logged.isEmpty) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: scheme.secondaryContainer),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.local_fire_department,
                    size: AppSpacing.xl,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.progressConsistencyTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        l.progressConsistencyCount(logged.length, dates.length),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(l.homeStreakBody, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (i, iso) in dates.indexed)
                  if (DateTime.tryParse(iso) case final date?)
                    DayDot(
                      date: date,
                      isLogged: logged.contains(iso),
                      isToday: i == dates.length - 1,
                      locale: locale,
                    ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
