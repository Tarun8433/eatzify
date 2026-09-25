import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Workout complete!" — the server's own account of what was just saved: time, volume, records,
/// the energy estimate and what was worked. With no signal, it says the workout is safe on the
/// phone instead of guessing at numbers only the server computes.
class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({super.key, this.detail});

  final WorkoutDetail? detail;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final d = detail;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(l.gymSummaryTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxl,
        ),
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: AppSizes.ringMacro,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: AppSpacing.md),
          if (d == null)
            HintCard(icon: Icons.cloud_off_outlined, text: l.gymSavedOffline)
          else
            WorkoutDetailBody(detail: d),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.gymNice)),
        ],
      ),
    );
  }
}

/// A saved workout from the history, with the one thing a past workout allows: deleting it.
class WorkoutDetailPage extends StatefulWidget {
  const WorkoutDetailPage({required this.workoutId, super.key});

  final String workoutId;

  static Future<void>? open(String id) => Get.to<void>(() => WorkoutDetailPage(workoutId: id));

  @override
  State<WorkoutDetailPage> createState() => _WorkoutDetailPageState();
}

class _WorkoutDetailPageState extends State<WorkoutDetailPage> {
  ViewState<WorkoutDetail> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    final result = await Get.find<GymRepository>().workout(widget.workoutId);
    if (mounted) setState(() => _state = result.fold(Failed.new, Ready.new));
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final sure = await confirmGym(
      context,
      title: l.gymDeleteWorkout,
      body: l.gymDeleteWorkoutConfirm,
      confirm: l.gymDelete,
      destructive: true,
    );
    if (!sure) return;
    final result = await Get.find<GymRepository>().deleteWorkout(widget.workoutId);
    if (!mounted) return;
    result.fold(
      (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.userMessage))),
      (_) {
        Get.find<GymController>().load(quietly: true);
        Navigator.pop(context, true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_state) {
          Ready<WorkoutDetail>(:final data) => data.summary.name,
          _ => l.gymHistory,
        }),
        actions: [
          if (_state is Ready<WorkoutDetail>)
            IconButton(
              tooltip: l.gymDeleteWorkout,
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: switch (_state) {
        Loading<WorkoutDetail>() => const LoadingView(lines: 5),
        Empty<WorkoutDetail>() => EmptyView(title: l.gymNoWorkoutsYet),
        Failed<WorkoutDetail>(:final failure) => FailedView(
          failure: failure,
          onRetry: _load,
          retryLabel: l.accountRetry,
        ),
        Ready<WorkoutDetail>(:final data) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              GymLabels.day(context, data.summary.diaryDate),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            WorkoutDetailBody(detail: data),
          ],
        ),
      },
    );
  }
}

/// What a saved workout came to. Shared by the summary and the history.
class WorkoutDetailBody extends StatelessWidget {
  const WorkoutDetailBody({required this.detail, super.key});

  final WorkoutDetail detail;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = detail.summary;
    final kcal = s.energyKcal;
    final basis = detail.energyBasis;
    final female =
        Get.isRegistered<GymController>() &&
        Get.find<GymController>().ready?.settings.bodyFigure == BodyFigure.female;
    final worked = detail.muscles.where((m) => m.level > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Tile(label: l.gymDuration, value: l.gymDurationValue((s.durationSec / 60).round())),
            _Tile(label: l.gymVolume, value: l.gymKg(GymLabels.kg(s.volumeKg))),
            _Tile(label: l.gymSetsLabel, value: '${s.setsDone}'),
            _Tile(label: l.gymRecords, value: '${s.prCount}'),
            _Tile(label: l.gymEnergy, value: kcal == null ? '—' : l.gymKcalValue(kcal)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(switch (basis?.weightSource) {
          null => l.gymEnergyNone,
          'weigh_in' => l.gymEnergyWeighIn(GymLabels.kg(basis!.weightKg)),
          'measurement' => l.gymEnergyMeasurement(GymLabels.kg(basis!.weightKg)),
          _ => l.gymEnergyProfile(GymLabels.kg(basis!.weightKg)),
        }, style: theme.textTheme.bodySmall),
        if (detail.bodyWeightKg != null)
          Text(
            l.gymBodyWeight(GymLabels.kg(detail.bodyWeightKg!)),
            style: theme.textTheme.bodySmall,
          ),
        for (final r in detail.records)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: HintCard(
              icon: Icons.emoji_events_outlined,
              text: r.isWeight
                  ? l.gymNewPr(GymLabels.name(r.name), GymLabels.kg(r.valueKg))
                  : l.gymNewE1rm(GymLabels.name(r.name), GymLabels.kg(r.valueKg)),
            ),
          ),
        if (worked.isNotEmpty) ...[
          GymHeading(l.gymWhatYouTrained),
          AppCard(
            child: BodyMap(
              levels: {for (final m in detail.muscles) m.muscle: m.level},
              female: female,
              semanticsLabel: l.gymMuscleMapLabel(
                worked.map((m) => GymLabels.muscle(l, m.muscle)).join(', '),
              ),
            ),
          ),
        ],
        GymHeading(l.gymTabExercises),
        for (final e in detail.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const GymIconDisc(icon: Icons.fitness_center),
            title: Text(GymLabels.name(e.name)),
            subtitle: Text(GymLabels.sets(l, e.mode, e.sets)),
          ),
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
