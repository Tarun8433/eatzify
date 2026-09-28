import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/trend_chart.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_history_page.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_stats_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_summary_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Stats: totals, a year of training days, which muscles got the work, effort, one exercise over
/// time, and workout energy. Nothing here scores anyone — a muscle not trained is listed, not red.
class GymStatsTab extends StatelessWidget {
  const GymStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<GymStatsController>();
    return Obx(
      () => switch (c.state.value) {
        Loading<GymStats>() => const LoadingView(lines: 6),
        Empty<GymStats>() => EmptyView(title: l.gymStatsEmptyTitle, body: l.gymStatsEmptyBody),
        Failed<GymStats>(:final failure) => FailedView(
          failure: failure,
          onRetry: c.load,
          retryLabel: l.accountRetry,
        ),
        Ready<GymStats>(:final data) => RefreshIndicator(
          onRefresh: () => c.load(quietly: true),
          child: _Stats(stats: data, controller: c),
        ),
      },
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.controller});

  final GymStats stats;
  final GymStatsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = stats;
    final kcal = s.weekKcal;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Tile(label: l.gymStatWorkouts, value: '${s.totalWorkouts}'),
            _Tile(label: l.gymStatThisMonth, value: '${s.thisMonth}'),
            _Tile(label: l.gymStatStreak, value: '${s.streakWeeks}'),
            _Tile(label: l.gymStatWeekKcal, value: kcal == null ? '—' : l.gymKcalValue(kcal)),
          ],
        ),
        GymHeading(l.gymActivity),
        AppCard(child: _Heatmap(weeks: s.heatmap)),
        _MuscleCard(stats: s, controller: controller),
        if (s.effort != null) _EffortCard(effort: s.effort!, controller: controller),
        if (s.exercises.isNotEmpty) _ProgressCard(stats: s, controller: controller),
        GymHeading(l.gymEnergyDays),
        AppCard(child: _EnergyBars(days: s.energyDays)),
        GymHeading(
          l.gymRecent,
          trailing: TextButton(onPressed: GymHistoryPage.open, child: Text(l.gymSeeAll)),
        ),
        for (final w in s.recent)
          WorkoutTile(workout: w, onTap: () => WorkoutDetailPage.open(w.id)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: AppSizes.nutrientTile),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// 53 weeks of squares, newest at the right and scrolled into view, shaded by minutes trained
/// against the person's own spread (the server's levels).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.weeks});

  final List<List<HeatCell>> weeks;

  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _alpha = [0.3, 0.5, 0.75, 1.0];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trainedDays = weeks.expand((w) => w).where((c) => c.workouts > 0).length;
    Color shade(int level) => level == 0
        ? scheme.surfaceContainerHighest
        : scheme.secondary.withValues(alpha: _alpha[level - 1]);

    return Semantics(
      label: l.gymHeatmapLabel(trainedDays),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final week in weeks)
                  Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: Column(
                      children: [
                        for (final cell in week)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: Opacity(
                              opacity: cell.future ? 0.3 : 1,
                              child: Container(
                                width: _cell,
                                height: _cell,
                                decoration: BoxDecoration(
                                  color: shade(cell.level.clamp(0, _alpha.length)),
                                  borderRadius: BorderRadius.circular(_gap),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(l.gymLessTime, style: theme.textTheme.bodySmall),
              const SizedBox(width: AppSpacing.xs),
              for (var level = 0; level <= _alpha.length; level++)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: Container(
                    width: _cell,
                    height: _cell,
                    decoration: BoxDecoration(
                      color: shade(level),
                      borderRadius: BorderRadius.circular(_gap),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Text(l.gymMoreTime, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _MuscleCard extends StatelessWidget {
  const _MuscleCard({required this.stats, required this.controller});

  final GymStats stats;
  final GymStatsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = stats.muscles;
    final c = controller;
    final female = Get.find<GymController>().ready?.settings.bodyFigure == BodyFigure.female;
    final windows = {
      'week': l.gymWindowWeek,
      '30d': l.gymWindow30,
      '90d': l.gymWindow90,
      'all': l.gymWindowAll,
    };
    final maxSets = m.top.isEmpty ? 1.0 : m.top.map((t) => t.sets).reduce(max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GymHeading(l.gymMuscleBalance),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final entry in windows.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: c.muscleWindow.value == entry.key,
                      onSelected: (_) => c.setMuscleWindow(entry.key),
                    ),
                  if (m.hasHardSets || c.hardOnly.value)
                    FilterChip(
                      label: Text(l.gymHardOnly),
                      selected: c.hardOnly.value,
                      onSelected: (on) => c.setHardOnly(on: on),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (m.workouts == 0)
                Text(l.gymNoWorkoutsWindow, style: theme.textTheme.bodySmall)
              else ...[
                BodyMap(
                  levels: m.levelByMuscle,
                  female: female,
                  semanticsLabel: l.gymMuscleMapLabel(
                    m.top.map((t) => GymLabels.muscle(l, t.muscle)).join(', '),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final t in m.top)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(GymLabels.muscle(l, t.muscle))),
                            Text(
                              l.gymMuscleSets(GymLabels.kg(t.sets)),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        LinearProgressIndicator(value: t.sets / maxSets),
                      ],
                    ),
                  ),
                if (m.untrained.isNotEmpty) ...[
                  Text(l.gymNotTrained, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final u in m.untrained) Chip(label: Text(GymLabels.muscle(l, u))),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EffortCard extends StatelessWidget {
  const _EffortCard({required this.effort, required this.controller});

  final EffortSummary effort;
  final GymStatsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = effort;
    final c = controller;
    final windows = {
      '30d': l.gymWindow30,
      '90d': l.gymWindow90,
      '1y': l.gymWindowYear,
      'all': l.gymWindowAll,
    };
    final maxCount = e.histogram.isEmpty ? 1 : max(1, e.histogram.map((b) => b.count).reduce(max));
    final scaleLabel = e.scale == EffortScale.rpe ? l.gymColRpe : l.gymColRir;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GymHeading(l.gymEffort),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final entry in windows.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: c.effortWindow.value == entry.key,
                      onSelected: (_) => c.setEffortWindow(entry.key),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (e.average == null)
                Text(l.gymEffortTooFew, style: theme.textTheme.bodySmall)
              else
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: '${l.gymEffortAverage} ($scaleLabel)',
                        value: GymLabels.kg(e.average!),
                      ),
                    ),
                    Expanded(
                      child: _Figure(label: l.gymEffortHard, value: '${e.hardPct}%'),
                    ),
                  ],
                ),
              Text(l.gymEffortRated(e.rated, e.finished), style: theme.textTheme.bodySmall),
              if (e.weekly.length >= 2) ...[
                const SizedBox(height: AppSpacing.md),
                TrendChart(
                  values: [for (final w in e.weekly) w.average],
                  height: AppSizes.coachChart,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: AppSizes.coachChart,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in e.histogram)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${b.count}', style: theme.textTheme.bodySmall),
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: b.count / maxCount,
                                  child: Container(color: theme.colorScheme.secondary),
                                ),
                              ),
                              Text('${l.gymColRir} ${b.bucket}', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.stats, required this.controller});

  final GymStats stats;
  final GymStatsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GymHeading(l.gymExerciseProgress),
        AppCard(
          child: Obx(() {
            final selected = c.exerciseId.value;
            final state = c.progress.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: stats.exercises.any((e) => e.id == selected) ? selected : null,
                  isExpanded: true,
                  items: [
                    for (final e in stats.exercises)
                      DropdownMenuItem(value: e.id, child: Text(GymLabels.name(e.name))),
                  ],
                  onChanged: (id) {
                    if (id != null) c.pickExercise(id);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                switch (state) {
                  null || Loading<ExerciseProgress>() => const LoadingView(lines: 2),
                  Empty<ExerciseProgress>() => Text(l.gymNeedsTwoSessions),
                  Failed<ExerciseProgress>(:final failure) => FailedView(
                    failure: failure,
                    onRetry: () => c.pickExercise(selected ?? ''),
                    retryLabel: l.accountRetry,
                  ),
                  Ready<ExerciseProgress>(:final data) => _ProgressBody(
                    progress: data,
                    controller: c,
                  ),
                },
                const SizedBox(height: AppSpacing.xs),
                Text('', style: theme.textTheme.bodySmall),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.progress, required this.controller});

  final ExerciseProgress progress;
  final GymStatsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = progress;
    final hasE1rm = p.points.any((x) => x.e1rm != null);
    final hasEffort = p.points.where((x) => x.effort != null).length >= 3;
    String unit(double v) => switch (p.mode) {
      ExerciseMode.cardio => l.gymSpeedValue(GymLabels.kg(v)),
      ExerciseMode.time => GymLabels.clock(v.round()),
      ExerciseMode.reps => l.gymKg(GymLabels.kg(v)),
    };

    return Obx(() {
      final metric = controller.metric.value;
      final values = [
        for (final point in p.points)
          switch (metric) {
            ProgressMetric.top => point.top,
            ProgressMetric.e1rm => point.e1rm,
            ProgressMetric.effort => point.effort,
          },
      ].whereType<double>().toList();
      final best = p.bestValue;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: Text(l.gymMetricTop),
                selected: metric == ProgressMetric.top,
                onSelected: (_) => controller.metric.value = ProgressMetric.top,
              ),
              if (hasE1rm)
                ChoiceChip(
                  label: Text(l.gymMetricE1rm),
                  selected: metric == ProgressMetric.e1rm,
                  onSelected: (_) => controller.metric.value = ProgressMetric.e1rm,
                ),
              if (hasEffort)
                ChoiceChip(
                  label: Text(l.gymMetricEffort),
                  selected: metric == ProgressMetric.effort,
                  onSelected: (_) => controller.metric.value = ProgressMetric.effort,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (values.length >= 2)
            TrendChart(values: values, height: AppSizes.coachChart)
          else
            Text(l.gymNeedsTwoSessions, style: theme.textTheme.bodySmall),
          if (best != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l.gymBest(unit(best)), style: theme.textTheme.bodyLarge),
          ],
          if (p.bestE1rm != null)
            Text(
              l.gymOneRmBest(
                GymLabels.kg(p.bestE1rm!.valueKg),
                GymLabels.kg(p.bestE1rm!.weightKg),
                p.bestE1rm!.reps,
              ),
              style: theme.textTheme.bodySmall,
            ),
          if (p.sessions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l.gymLastSessions, style: theme.textTheme.bodySmall),
            for (final s in p.sessions)
              Text(
                '${GymLabels.day(context, s.date)} · ${GymLabels.sets(l, p.mode, s.sets)}',
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ],
      );
    });
  }
}

/// Workout energy per diary day, last 30: a bar where something was estimated, nothing where not.
class _EnergyBars extends StatelessWidget {
  const _EnergyBars({required this.days});

  final List<({String date, int? kcal})> days;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final top = days.map((d) => d.kcal ?? 0).fold(0, max);
    final total = days.fold(0, (sum, d) => sum + (d.kcal ?? 0));
    return Semantics(
      label: '${l.gymEnergyDays}: ${l.gymKcalValue(total)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.gymKcalValue(total), style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSizes.habitBar * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: top == 0 ? 0 : (d.kcal ?? 0) / top,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary,
                            borderRadius: BorderRadius.circular(AppSpacing.xs),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
