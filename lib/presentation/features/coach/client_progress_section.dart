import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/trend_chart.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/dashboard_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// What one client has actually been logging (D-203).
///
/// Loaded separately from the profile fields because it is a separate permission and a separate
/// audited read. A client who shared only the basics never triggers this call at all.
class ClientProgressController extends GetxController {
  ClientProgressController({required this.coach, required this.clientUserId});

  final CoachRepository coach;
  final int clientUserId;

  final state = Rx<ViewState<ClientProgress>>(const Loading());

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await coach.clientProgress(clientUserId);

    state.value = result.fold(
      // A 404 here means the grant does not carry `progress`, which is the client's decision
      // rather than a fault. Empty rather than Failed: there is nothing to retry.
      (f) => f is ApiFailure && f.status == 404 ? const Empty() : Failed(f),
      (p) => p.isEmpty ? const Empty() : Ready(p),
    );
  }
}

/// The charts and figures, under the profile facts on the client detail page.
class ClientProgressSection extends StatelessWidget {
  const ClientProgressSection({required this.clientUserId, super.key});

  final int clientUserId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.put(
      ClientProgressController(coach: Get.find<CoachRepository>(), clientUserId: clientUserId),
      tag: 'progress-$clientUserId',
    );

    return Obx(
      () => switch (c.state.value) {
        Loading<ClientProgress>() => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
        // Says which of the two it is: nothing logged, or nothing shared. They look the same on
        // screen and mean entirely different things to a coach deciding what to do next.
        Empty<ClientProgress>() => HintCard(
          icon: Icons.insights_outlined,
          text: l.coachProgressNotShared,
        ),
        Failed<ClientProgress>(:final failure) => HintCard.important(
          icon: Icons.error_outline,
          title: l.coachProgressTitle,
          text: failure.userMessage,
        ),
        Ready<ClientProgress>(:final data) => _Progress(progress: data),
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final ClientProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.coachProgressTitle,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AdherenceRing(pct: progress.adherencePct),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.coachDaysLogged(progress.daysLogged, progress.windowDays),
                          style: theme.textTheme.bodySmall,
                        ),
                        // Said out loud, because the ring beside it looks like a compliance score
                        // and is not one. docs/02 FR-4.2 defines this as logging FREQUENCY, and a
                        // coach reading it as "follows the plan 64 % of the time" would be wrong.
                        Text(
                          l.coachLoggedDaysNote,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Absent at zero. docs/05 §6 — "0 day streak" is the failure banner these
                        // rules exist to prevent.
                        if (progress.streakDays > 0)
                          Text(
                            '${l.coachStreak}  '
                            '${l.coachStreakDays(progress.streakDays)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (progress.weightChange30d case final change?)
                          Text(
                            // Same voice for a gain and a loss, no colour (docs/05 §6, D-39).
                            '${l.coachWeightChange}  '
                            '${change >= 0 ? '+' : ''}'
                            '${change.toStringAsFixed(1)} kg',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // What they ate against what the plan asked for. Above the charts, because this is the
        // question a nutritionist opens the screen with — the weight line answers whether it is
        // working, and this answers why.
        if (progress.avgKcal != null || progress.targetKcal != null) ...[
          const SizedBox(height: AppSpacing.md),
          _AgainstPlan(progress: progress),
        ],

        // One card per kind the client records. A kind they never logged is absent, so a coach sees
        // what this person actually tracks rather than a wall of empty charts.
        for (final MapEntry(key: kind, value: points) in progress.series.entries)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _SeriesCard(kind: kind, points: points),
          ),
      ],
    );
  }
}

/// One measured thing, its latest reading, and how it moved.
///
/// A sparkline rather than a full chart: the question a coach asks at a glance is "which way is
/// this going", and the number beside it answers "where is it now".
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.kind, required this.points});

  final String kind;
  final List<SeriesPoint> points;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final latest = points.isEmpty ? null : points.last;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.choiceDisc,
                  width: AppSizes.choiceDisc,
                  decoration: BoxDecoration(
                    color: seriesTint(kind).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(seriesIcon(kind), size: AppSpacing.lg, color: seriesTint(kind)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seriesLabel(l, kind),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      l.coachReadingCount(points.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (latest != null)
                Text(
                  _reading(latest.value),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          // The chart, full width and the same shape the client sees on their own Progress tab.
          // A reading says where somebody is; the line says where they are going, and a coach
          // reads the second one first.
          if (points.length >= 2) ...[
            const SizedBox(height: AppSpacing.md),
            TrendChart(
              values: points.map((p) => p.value).toList(),
              color: seriesTint(kind),
              height: AppSizes.coachChart,
            ),
            const SizedBox(height: AppSpacing.xs),
            // The window the line covers, so nobody reads a fortnight as a quarter.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  points.first.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  points.last.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Whole numbers for counts, one decimal for measurements. 8200.0 steps reads as a bug.
  String _reading(double value) => value == value.roundToDouble() && value.abs() >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// Every measurement kind docs/03 defines, through l10n (rule 4). An unknown kind falls back to
/// its own key rather than being dropped — a newer server adding a kind should show something.
String seriesLabel(AppLocalizations l, String kind) => switch (kind) {
  'weight' => l.coachSeriesWeight,
  'steps' => l.coachSeriesSteps,
  'distance_m' => l.coachSeriesDistance,
  'water_ml' || 'water' => l.coachSeriesWater,
  'waist' => l.coachSeriesWaist,
  'hip' => l.coachSeriesHip,
  'thigh' => l.coachSeriesThigh,
  'chest' => l.coachSeriesChest,
  'bp_sys' => l.coachSeriesBpSys,
  'bp_dia' => l.coachSeriesBpDia,
  'hba1c' => l.coachSeriesHba1c,
  'energy_burned_kcal' || 'calories_burned' || 'burned' => l.coachSeriesBurned,
  _ => kind,
};

IconData seriesIcon(String kind) => switch (kind) {
  'weight' => Icons.monitor_weight_outlined,
  'steps' => Icons.directions_walk,
  'distance_m' => Icons.route_outlined,
  'water_ml' || 'water' => Icons.water_drop_outlined,
  'bp_sys' || 'bp_dia' => Icons.favorite_outline,
  'hba1c' => Icons.bloodtype_outlined,
  'energy_burned_kcal' || 'calories_burned' || 'burned' => Icons.local_fire_department_outlined,
  _ => Icons.straighten_outlined,
};

/// The tint identifies the measurement, never judges it — the same rule the macro rings follow.
Color seriesTint(String kind) => switch (kind) {
  'weight' => AppColors.macroFat,
  'steps' || 'distance_m' => AppColors.success,
  'water_ml' || 'water' => AppColors.macroFat,
  'bp_sys' || 'bp_dia' => AppColors.danger,
  'hba1c' => AppColors.warning,
  'energy_burned_kcal' || 'calories_burned' || 'burned' => AppColors.warmCoral,
  _ => AppColors.macroCarb,
};

/// Average intake beside the plan's target.
///
/// The two always appear together. A day of 2,400 kcal means nothing until you know the plan asked
/// for 1,859, and a number without its target invites a coach to guess.
class _AgainstPlan extends StatelessWidget {
  const _AgainstPlan({required this.progress});

  final ClientProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.coachIntakeTitle,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          // A plan with no targets fired a blocking gate (docs/04 §2), so there is nothing to
          // compare against and the card says so rather than comparing against zero.
          if (progress.targetKcal == null)
            Text(
              l.coachNoPlanYet,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else ...[
            _Against(
              label: l.coachAvgCalories,
              eaten: progress.avgKcal,
              target: progress.targetKcal,
              icon: Icons.local_fire_department_outlined,
              tint: AppColors.warmCoral,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Against(
              label: l.coachAvgProtein,
              eaten: progress.avgProteinG,
              target: progress.targetProteinG,
              unit: 'g',
              icon: Icons.egg_outlined,
              tint: AppColors.macroProtein,
            ),
          ],
        ],
      ),
    );
  }
}

class _Against extends StatelessWidget {
  const _Against({
    required this.label,
    required this.eaten,
    required this.target,
    required this.icon,
    required this.tint,
    this.unit = '',
  });

  final String label;
  final int? eaten;
  final int? target;
  final IconData icon;
  final Color tint;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ate = eaten;
    final goal = target;

    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            height: AppSizes.choiceDisc,
            width: AppSizes.choiceDisc,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(icon, size: AppSpacing.lg, color: tint),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          // Nothing logged is an em dash, not a zero — zero would say they ate nothing.
          ate == null || goal == null ? '\u2014' : l.coachOfTarget('$ate$unit', '$goal$unit'),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
