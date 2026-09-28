import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/estimate_one_rm.dart';
import 'package:health_pro/presentation/features/gym/custom_exercise_sheet.dart';
import 'package:health_pro/presentation/features/gym/exercise_about.dart';
import 'package:health_pro/presentation/features/gym/exercise_media.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/routine_edit_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// One exercise in full: what it works (drawn, since the animations are unlicensed — D-243), how
/// to do it, the person's best and last time, a one-rep-max calculator, and a way into a routine.
class ExerciseDetailSheet extends StatefulWidget {
  const ExerciseDetailSheet({required this.exerciseId, super.key, this.readOnly = false});

  final String exerciseId;

  /// Opened from inside a workout: no routine or edit actions.
  final bool readOnly;

  static Future<void> show(BuildContext context, String exerciseId, {bool readOnly = false}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, scroll) => PrimaryScrollController(
            controller: scroll,
            child: ExerciseDetailSheet(exerciseId: exerciseId, readOnly: readOnly),
          ),
        ),
      );

  @override
  State<ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<ExerciseDetailSheet> {
  ViewState<ExerciseDetail> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    final result = await Get.find<GymRepository>().exercise(widget.exerciseId);
    if (!mounted) return;
    setState(() => _state = result.fold(Failed.new, Ready.new));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (_state) {
      Loading<ExerciseDetail>() => const LoadingView(lines: 5),
      Empty<ExerciseDetail>() => EmptyView(title: l.gymNoMatches),
      Failed<ExerciseDetail>(:final failure) => FailedView(
        failure: failure,
        onRetry: _load,
        retryLabel: l.accountRetry,
      ),
      Ready<ExerciseDetail>(:final data) => _Detail(detail: data, readOnly: widget.readOnly),
    };
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.detail, required this.readOnly});

  final ExerciseDetail detail;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = detail.exercise;
    final gym = Get.find<GymController>();
    final figure = gym.ready?.settings.bodyFigure ?? BodyFigure.male;
    final steps = detail.stepsFor(Localizations.localeOf(context).languageCode);
    final best = detail.bestWeightKg;

    return ListView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Row(
          children: [
            GymIconDisc(icon: GymLabels.bodyPartIcon(e.bodyPart)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    GymLabels.name(e.name, custom: e.isCustom),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${GymLabels.bodyPart(l, e.bodyPart)} · ${GymLabels.equipment(l, e.equipment)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: ExerciseMedia(
            url: e.mediaUrl,
            thumbUrl: e.thumbUrl,
            semanticsLabel: l.gymMediaLabel(GymLabels.name(e.name, custom: e.isCustom)),
          ),
        ),
        if (e.mediaUrl != null || e.thumbUrl != null) const SizedBox(height: AppSpacing.lg),
        if (e.muscles.isNotEmpty)
          BodyMap(
            female: figure == BodyFigure.female,
            levels: {for (final m in e.muscles) m.muscle: m.isPrimary ? 4 : 2},
            semanticsLabel: l.gymMuscleMapLabel(
              e.muscles.map((m) => GymLabels.muscle(l, m.muscle)).join(', '),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (e.target.isNotEmpty)
              Chip(label: Text(l.gymTargetTag(GymLabels.target(l, e.target)))),
            for (final m in e.muscles.where((m) => !m.isPrimary))
              Chip(label: Text(GymLabels.muscle(l, m.muscle))),
            if (e.isCustom) Chip(label: Text(l.gymCustomTag)),
          ],
        ),
        if (best != null || detail.lastDate != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (best != null)
                  Text(l.gymBestKg(GymLabels.kg(best)), style: theme.textTheme.bodyLarge),
                if (detail.lastDate != null)
                  Text(
                    l.gymLastTimeSets(
                      GymLabels.day(context, detail.lastDate!),
                      GymLabels.sets(l, detail.planEntry.mode, detail.lastSets),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
        if (!e.isCardio) _OneRmCard(detail: detail),
        GymHeading(l.gymHowTo),
        HowToSteps(steps: steps, description: e.description),
        if (!readOnly) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () => _addToRoutine(context, gym),
            icon: const Icon(Icons.playlist_add),
            label: Text(l.gymAddToRoutine),
          ),
          if (e.isCustom) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final edited = await CustomExerciseSheet.show(context, editing: e);
                if (edited != null && context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.gymEditExercise),
            ),
            TextButton.icon(
              onPressed: () async {
                final sure = await confirmGym(
                  context,
                  title: l.gymDeleteExercise,
                  body: l.gymDeleteExerciseConfirm,
                  confirm: l.gymDelete,
                  destructive: true,
                );
                if (sure && await gym.deleteExercise(e.id) && context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(l.gymDeleteExercise),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(l.gymCredits, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }

  Future<void> _addToRoutine(BuildContext context, GymController gym) async {
    final l = AppLocalizations.of(context);
    final routines = gym.ready?.routines ?? const <Routine>[];
    final choice = await showModalBottomSheet<Routine?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in routines)
              ListTile(
                leading: GymIconDisc(icon: GymLabels.iconFor(r.icon)),
                title: Text(r.name),
                trailing: detail.routineIds.contains(r.id)
                    ? Chip(label: Text(l.gymAlreadyIn))
                    : null,
                onTap: () => Navigator.pop(context, r),
              ),
            ListTile(
              leading: const GymIconDisc(icon: Icons.add),
              title: Text(l.gymNewRoutine),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final item = RoutineItem(
      config: detail.planEntry.target,
      name: detail.exercise.name,
      bodyPart: detail.exercise.bodyPart,
      equipment: detail.exercise.equipment,
      isBodyweight: detail.exercise.isBodyweight,
      isCardio: detail.exercise.isCardio,
    );
    if (choice == null) {
      Navigator.pop(context);
      await RoutineEditPage.open(initialItems: [item]);
      return;
    }
    if (await gym.addToRoutine(choice, item.config) && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.gymAddedTo(choice.name))));
    }
  }
}

/// The best estimate from the log, and a calculator for sets not yet done — answered as the
/// steppers move (see `estimate_one_rm.dart` for why that one formula lives on the phone too).
class _OneRmCard extends StatefulWidget {
  const _OneRmCard({required this.detail});

  final ExerciseDetail detail;

  @override
  State<_OneRmCard> createState() => _OneRmCardState();
}

class _OneRmCardState extends State<_OneRmCard> {
  static const _weightStep = 2.5;
  static const _startReps = 5.0;
  late double _weight = widget.detail.bestWeightKg ?? 20;
  double _reps = _startReps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final best = widget.detail.bestE1rm;
    final estimate = estimateOneRm(_weight, _reps.round());
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.gymOneRm, style: theme.textTheme.titleMedium),
            if (best != null)
              Text(
                l.gymOneRmBest(GymLabels.kg(best.valueKg), GymLabels.kg(best.weightKg), best.reps),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: GymStepper(
                    label: l.gymWeightKg,
                    value: _weight,
                    step: _weightStep,
                    decimal: true,
                    max: 500,
                    onChanged: (v) => setState(() => _weight = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: GymStepper(
                    label: l.gymReps,
                    value: _reps,
                    step: 1,
                    min: 1,
                    max: oneRmMaxReps.toDouble(),
                    onChanged: (v) => setState(() => _reps = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              estimate == null ? l.gymOneRmLimit : l.gymOneRmResult(GymLabels.kg(estimate)),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
