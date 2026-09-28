import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/gym/gym_energy_habit.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/progress/log_weight_sheet.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/features/progress/progress_dashboard.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// tabProgress. docs/14 §1, all four states per CLAUDE.md rule 6.
///
/// docs/05 §6 is what shapes this screen more than anything: no streaks on weight, no leaderboard,
/// no red marker on a day without an entry. A weight chart is precisely where those creep in, so
/// this stays a plain line and a plain sentence.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = Get.put(
      ProgressController(
        measurements: Get.find<MeasurementsRepository>(),
        // Resolved rather than required (the D-99 pattern): tests about weight and habits
        // register no diary, and those cards simply are not there without one.
        diary: Get.isRegistered<DiaryRepository>() ? Get.find<DiaryRepository>() : null,
      ),
      permanent: true,
    );

    return TabScaffold(
      title: l10n.tabProgress,
      subtitle: l10n.progressSubtitle,
      action: c.diary == null ? null : PeriodPill(controller: c),
      child: Column(
        children: [
          Expanded(
            child: Obx(
              () => switch (c.state.value) {
                Loading<MeasurementHistory>() => const LoadingView(),
                Empty<MeasurementHistory>() => EmptyView(
                  title: l10n.progressEmptyTitle,
                  body: l10n.progressEmptyBody,
                ),
                Failed<MeasurementHistory>(:final failure) => FailedView(
                  failure: failure,
                  onRetry: c.load,
                  retryLabel: l10n.accountRetry,
                ),
                Ready<MeasurementHistory>(:final data) => _Progress(history: data, controller: c),
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => LogWeightSheet.show(context, c),
                child: Text(l10n.progressLogWeight),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

/// Weight, then the body measurements (D-87).
///
/// The screen used to be one number and, on a first reading, a sentence over half a blank page. The
/// measurements were already kinds the API served — waist, hip, thigh, chest — and nothing asked
/// for them.
class _Progress extends StatelessWidget {
  const _Progress({required this.history, required this.controller});

  final MeasurementHistory history;
  final ProgressController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // One Obx over the whole list: it reads the section chip, the dashboard's diary days and the
    // measurement maps, and any of them changing is a different page.
    return Obx(() {
      final sec = controller.section.value;
      bool show(String s) => sec == 'overview' || sec == s;
      final hasDiary = controller.diary != null;

      // Which habit rows a section wants: activity is what the body did, habits is what the user
      // keeps up; overview is everything.
      final habitKinds = switch (sec) {
        'activity' => const ['steps', 'distance_m', 'energy_burned_kcal'],
        'habits' => const ['water_ml'],
        _ => ProgressController.habitKinds,
      };

      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        children: [
          if (hasDiary) ...[
            SectionChips(controller: controller),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (hasDiary && show('nutrition')) ...[
            CalorieProgressCard(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            MacroBalanceCard(
              controller: controller,
              onDetails: sec == 'nutrition' ? null : () => controller.section.value = 'nutrition',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (show('weight')) ...[
            _WeightTrend(
              history: history,
              onSeeAll: sec == 'weight' ? null : () => controller.section.value = 'weight',
            ),
            const SizedBox(height: AppSpacing.lg),
            // Said once, on the reading that prompts it. A first entry with no trend is the state
            // that looks broken, so it explains itself rather than leaving the page empty.
            if (history.change == null && history.points.length == 1) ...[
              AppCard(child: Text(l.progressFirstReading, style: theme.textTheme.bodyMedium)),
              const SizedBox(height: AppSpacing.lg),
            ],
            // The full date-wise report, on the section "See all" leads to — not on Overview,
            // which stays a summary.
            if (sec == 'weight' && history.points.isNotEmpty) ...[
              Text(l.progressHistoryTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _WeightHistory(history: history),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
          if (hasDiary && show('habits')) ...[
            ConsistencyCard(controller: controller),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (show('weight')) ...[
            Text(l.progressBodyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final kind in ProgressController.bodyKinds)
              _BodyMeasurement(kind: kind, history: controller.body[kind], controller: controller),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (show('activity') || show('habits')) ...[
            // What the `+` sheet writes every day. It was visible on Home for today and nowhere
            // at all tomorrow, which is a display rather than tracking.
            Text(l.progressHabitsTitle, style: theme.textTheme.titleMedium),
            Text(l.progressHabitsSubtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            for (final kind in habitKinds) _Habit(kind: kind, history: controller.habits[kind]),
            // D-242: workout energy, its own row — never folded into calories burned.
            const GymEnergyHabit(),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      );
    });
  }
}

/// One daily habit: what it reads now, how many days of it there are, and the last week as bars.
///
/// Bars, not a curve: steps and glasses of water are counts that reset at the diary boundary, and a
/// line between two of them implies a value in between that nobody measured. Weight is the opposite
/// — it exists continuously — which is why it gets the curve.
class _Habit extends StatelessWidget {
  const _Habit({required this.kind, required this.history});

  final String kind;
  final MeasurementHistory? history;

  /// A week. Long enough to see a habit, short enough to fit a phone's width as bars.
  static const _days = 7;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = history?.points ?? const <Measurement>[];
    final recent = points.length <= _days ? points : points.sublist(points.length - _days);
    // The tallest bar in the week sets the scale. An absolute scale would draw a 6,000-step day as
    // a sliver against a 100,000-step ceiling nobody walks.
    final peak = recent.fold<double>(0, (top, p) => p.value > top ? p.value : top);
    final latest = points.lastOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(_label(l, kind), style: theme.textTheme.bodyMedium)),
                Text(
                  // Never a zero for "not recorded": nought steps and no answer are different
                  // claims, and only one of them is the user's.
                  latest == null ? l.progressHabitNone : _value(context, kind, latest.value),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: latest == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: AppSizes.habitBar,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final point in recent)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            // A day with a reading is never a bar of nothing — a hairline still
                            // says "logged", and an empty slot still says "did not".
                            heightFactor: peak == 0 ? 0.06 : (point.value / peak).clamp(0.06, 1.0),
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
              // Rule 10: where the headline figure came from, beside it. A count the phone reported
              // and one somebody typed are different claims.
              Text(
                l.habitDaysFrom(l.habitDaysLogged(points.length), latest!.source.label(l)),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// CLAUDE.md rule 4: a kind is a wire value and l10n on screen.
  static String _label(AppLocalizations l, String kind) => switch (kind) {
    'steps' => l.habitSteps,
    'distance_m' => l.habitDistance,
    'water_ml' => l.habitWater,
    _ => l.habitBurned,
  };

  /// Grouped by the reader's locale — 8,432 in English and 8,432 in Hindi, and neither of them
  /// 8432.0. The unit comes from the kind, not from the row, because the server refuses a mismatch.
  static String _value(BuildContext context, String kind, double value) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale).format(value.round());
    return switch (kind) {
      'steps' => number,
      // Metres on the wire, kilometres to a reader: 6,100 m is a number, 6.1 km is a walk.
      'distance_m' => '${NumberFormat('#,##0.0', locale).format(value / 1000)} km',
      'water_ml' => '$number ml',
      _ => '$number kcal',
    };
  }
}

/// One body measurement: its latest value and change, or an invitation to start it.
class _BodyMeasurement extends StatelessWidget {
  const _BodyMeasurement({required this.kind, required this.history, required this.controller});

  final String kind;
  final MeasurementHistory? history;
  final ProgressController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = _kindLabel(l, kind);
    final latest = history?.points.lastOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(
                    // Never a zero: a measurement nobody has taken is not a measurement of nought.
                    latest == null
                        ? l.progressMeasurementNone
                        : '${latest.value.toStringAsFixed(1)} cm',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: latest == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => LogWeightSheet.show(
                context,
                controller,
                kind: kind,
                unit: 'cm',
                title: l.progressLogKind(label),
              ),
              child: Text(l.progressAddMeasurement),
            ),
          ],
        ),
      ),
    );
  }

  /// CLAUDE.md rule 4: a kind is a wire value and l10n on screen.
  static String _kindLabel(AppLocalizations l, String kind) => switch (kind) {
    'waist' => l.measurementWaist,
    'hip' => l.measurementHip,
    'thigh' => l.measurementThigh,
    _ => l.measurementChest,
  };
}

/// The reference's one weight card (D-143): title and See all, the current weight on the left,
/// the trend line on the right — merged from the old accent card and chart card pair.
class _WeightTrend extends StatelessWidget {
  const _WeightTrend({required this.history, this.onSeeAll});

  final MeasurementHistory history;

  /// Narrows the dashboard to the weight section; null hides the button (already there).
  final VoidCallback? onSeeAll;

  static const _chartHeight = 132.0;
  static const _disc = 36.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Suspect points are excluded from the line — docs/08 keeps them, docs/16 keeps them out of the
    // trend. Drawing them would reintroduce the "−30.0 kg" cliff the constraint exists to prevent.
    final plotted = history.points.where((p) => !p.isSuspect).toList();
    final latest = history.points.isEmpty ? null : history.points.last;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.progressWeightTrend,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.progressSeeAll),
                      const Icon(Icons.chevron_right, size: AppSpacing.lg),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < AppSizes.heroBreakpoint;

              final figures = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (latest != null) ...[
                    ExcludeSemantics(
                      child: Container(
                        height: _disc,
                        width: _disc,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.monitor_weight_outlined,
                          size: AppSpacing.lg,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${latest.value.toStringAsFixed(1)} ${latest.unit}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(l.progressCurrentWeight, style: theme.textTheme.bodySmall),
                    // Only when a trend exists: the chart side already says "log a few more
                    // days", and saying it twice on a first reading reads as a bug.
                    if (history.change != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(_changeText(l), style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ],
              );

              final chart = plotted.length >= 2
                  ? SizedBox(
                      height: _chartHeight,
                      child: _Chart(points: plotted),
                    )
                  : Text(l.progressNoTrend, style: theme.textTheme.bodyMedium);

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    figures,
                    const SizedBox(height: AppSpacing.md),
                    chart,
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: constraints.maxWidth * 0.38, child: figures),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: chart),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Null change is "not enough data", NOT zero — rendering it as 0.0 kg would be a made-up fact.
  String _changeText(AppLocalizations l) {
    // The last 30 days first (docs/21 §3): a month-old loss must not caption a visible recent
    // rise as "down". Since-start is the fallback when the window has no trend yet.
    final recent = history.change30d;
    if (recent != null) {
      final kg = recent.abs().toStringAsFixed(1);
      if (recent.abs() < 0.1) return l.progressChange30Flat;
      // Neutral in both directions: docs/05 §6 forbids framing a gain as a failure.
      return recent < 0 ? l.progressChange30Down(kg) : l.progressChange30Up(kg);
    }

    final change = history.change;
    if (change == null) return l.progressNoTrend;

    final kg = change.abs().toStringAsFixed(1);
    if (change.abs() < 0.1) return l.progressChangeFlat;
    return change < 0 ? l.progressChangeDown(kg) : l.progressChangeUp(kg);
  }
}

/// Every reading, date-wise, newest first (the user's "full report"): the day, where the number
/// came from (rule 10), and the value. A suspect reading is SHOWN — docs/08 keeps it — with a
/// neutral note that the trend leaves it out; never a red mark (docs/05 §6).
class _WeightHistory extends StatelessWidget {
  const _WeightHistory({required this.history});

  final MeasurementHistory history;

  /// Two months of every-other-day weigh-ins; beyond that a user is browsing, not tracking.
  static const _maxRows = 30;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rows = history.points.reversed.take(_maxRows).toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (final (i, point) in rows.indexed)
            if (DateTime.tryParse(point.diaryDate) case final date?) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.MMMEd(locale).format(date),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            point.isSuspect ? l.progressHistoryExcluded : point.source.label(l),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${point.value.toStringAsFixed(1)} ${point.unit}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points});

  final List<Measurement> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = points.map((p) => p.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    // A flat series would otherwise collapse to a zero-height axis.
    final pad = (max - min) < 1 ? 1.0 : (max - min) * 0.2;

    return LineChart(
      LineChartData(
        minY: min - pad,
        maxY: max + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
            isCurved: true,
            color: theme.colorScheme.primary,
            // The reference marks each reading and grounds the line on a soft fill.
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
