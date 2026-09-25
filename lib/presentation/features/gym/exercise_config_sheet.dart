import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// How one exercise is done in a routine: by reps, by time, or — for cardio — minutes at a speed,
/// plus its own progression rule if it should not follow the routine's.
class ExerciseConfigSheet extends StatefulWidget {
  const ExerciseConfigSheet({required this.item, required this.routineRule, super.key});

  final RoutineItem item;
  final ProgressionRule routineRule;

  static Future<RoutineExercise?> show(
    BuildContext context,
    RoutineItem item,
    ProgressionRule routineRule,
  ) => showModalBottomSheet<RoutineExercise>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => PrimaryScrollController(
        controller: scroll,
        child: ExerciseConfigSheet(item: item, routineRule: routineRule),
      ),
    ),
  );

  @override
  State<ExerciseConfigSheet> createState() => _ExerciseConfigSheetState();
}

class _ExerciseConfigSheetState extends State<ExerciseConfigSheet> {
  late RoutineExercise _c = widget.item.config;

  static const _weightStep = 2.5;
  static const _secondsStep = 5.0;
  static const _speedStep = 0.5;

  bool get _bodyweight => _c.bodyweight ?? widget.item.isBodyweight;
  bool get _perSide => _c.perSide ?? false;

  ProgressionRule get _effectiveRule {
    final rule = _c.progression ?? widget.routineRule;
    return ProgressionRule.allowedFor(_c.mode).contains(rule) ? rule : ProgressionRule.off;
  }

  double get _defaultStep => _c.mode == ExerciseMode.time
      ? _secondsStep
      : const {'upper legs', 'lower legs', 'back'}.contains(widget.item.bodyPart)
      ? 5
      : _weightStep;

  void _set(RoutineExercise next) => setState(() => _c = next);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cardio = widget.item.isCardio;
    final repsStep = _perSide ? 2.0 : 1.0;

    return ListView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text(
          GymLabels.name(widget.item.name),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!cardio)
          SegmentedButton<ExerciseMode>(
            segments: [
              ButtonSegment(value: ExerciseMode.reps, label: Text(l.gymModeReps)),
              ButtonSegment(value: ExerciseMode.time, label: Text(l.gymModeTime)),
            ],
            selected: {_c.mode},
            onSelectionChanged: (s) => _set(
              _c.copyWith(
                mode: s.first,
                seconds: () => _c.seconds ?? 45,
                reps: () => _c.reps ?? 10,
                // Per side is a rep split; a hold has none.
                perSide: () => s.first == ExerciseMode.time ? null : _c.perSide,
                progression: () => null,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        GymStepper(
          label: cardio ? l.gymIntervals : l.gymSets,
          value: _c.sets.toDouble(),
          step: 1,
          min: 1,
          max: 20,
          onChanged: (v) => _set(_c.copyWith(sets: v.round())),
        ),
        const SizedBox(height: AppSpacing.md),
        ...switch (_c.mode) {
          ExerciseMode.cardio => [
            GymStepper(
              label: l.gymMinutes,
              value: _c.minutes ?? 20,
              step: 1,
              min: 1,
              max: 600,
              onChanged: (v) => _set(_c.copyWith(minutes: () => v)),
            ),
            const SizedBox(height: AppSpacing.md),
            GymStepper(
              label: l.gymSpeed,
              value: _c.speedKmh ?? 8,
              step: _speedStep,
              decimal: true,
              max: 40,
              onChanged: (v) => _set(_c.copyWith(speedKmh: () => v)),
            ),
          ],
          ExerciseMode.time => [
            GymStepper(
              label: l.gymSeconds,
              value: (_c.seconds ?? 45).toDouble(),
              step: _secondsStep,
              min: 5,
              max: 3600,
              onChanged: (v) => _set(_c.copyWith(seconds: () => v.round())),
            ),
            const SizedBox(height: AppSpacing.md),
            _weight(l, added: true),
          ],
          ExerciseMode.reps => [
            GymStepper(
              label: l.gymReps,
              value: (_c.reps ?? 10).toDouble(),
              step: repsStep,
              min: repsStep,
              max: 200,
              onChanged: (v) => _set(_c.copyWith(reps: () => v.round())),
            ),
            const SizedBox(height: AppSpacing.md),
            _weight(l, added: _bodyweight),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.gymBodyweight),
              subtitle: Text(l.gymBodyweightBody),
              value: _bodyweight,
              onChanged: (v) => _set(_c.copyWith(bodyweight: () => v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.gymPerSideSwitch),
              subtitle: Text(l.gymPerSideBody),
              value: _perSide,
              onChanged: (v) {
                final reps = _c.reps ?? 10;
                _set(
                  _c.copyWith(
                    perSide: () => v ? true : null,
                    reps: () => v && reps.isOdd ? reps + 1 : reps,
                  ),
                );
              },
            ),
            if (_bodyweight && (_c.weightKg ?? 0) <= 0)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.gymRepsMax),
                subtitle: Text(l.gymRepsMaxBody),
                value: _c.repsMax != null,
                onChanged: (v) => _set(_c.copyWith(repsMax: () => v ? (_c.reps ?? 10) + 5 : null)),
              ),
            if (_bodyweight && (_c.weightKg ?? 0) <= 0 && _c.repsMax != null)
              GymStepper(
                label: l.gymRepsMax,
                value: _c.repsMax!.toDouble(),
                step: repsStep,
                min: (_c.reps ?? 1).toDouble(),
                max: 200,
                onChanged: (v) => _set(_c.copyWith(repsMax: () => v.round())),
              ),
          ],
        },
        if (_c.mode != ExerciseMode.cardio) ...[
          GymHeading(l.gymProgression),
          DropdownButtonFormField<ProgressionRule?>(
            initialValue: _c.progression,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.gymRule),
            items: [
              DropdownMenuItem(
                child: Text(l.gymFollowRoutine(GymLabels.rule(l, widget.routineRule))),
              ),
              for (final rule in ProgressionRule.allowedFor(_c.mode))
                DropdownMenuItem(value: rule, child: Text(GymLabels.rule(l, rule))),
            ],
            onChanged: (rule) => _set(_c.copyWith(progression: () => rule)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(GymLabels.ruleBody(l, _effectiveRule), style: theme.textTheme.bodySmall),
          if (_effectiveRule != ProgressionRule.off) ...[
            const SizedBox(height: AppSpacing.md),
            GymStepper(
              label: l.gymStep,
              value: _c.increment ?? _defaultStep,
              step: _c.mode == ExerciseMode.time ? _secondsStep : 1.25,
              decimal: _c.mode != ExerciseMode.time,
              min: _c.mode == ExerciseMode.time ? _secondsStep : 1.25,
              max: 50,
              onChanged: (v) => _set(_c.copyWith(increment: () => v)),
            ),
          ],
          if (_effectiveRule == ProgressionRule.doubleProgression) ...[
            const SizedBox(height: AppSpacing.md),
            GymStepper(
              label: l.gymRepsMin,
              value: (_c.repsMin ?? ((_c.reps ?? 10) - 2)).toDouble(),
              step: 1,
              min: 1,
              max: (_c.reps ?? 10).toDouble(),
              onChanged: (v) => _set(_c.copyWith(repsMin: () => v.round())),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: () => Navigator.pop(context, _c), child: Text(l.gymDone)),
      ],
    );
  }

  Widget _weight(AppLocalizations l, {required bool added}) => GymStepper(
    label: added ? l.gymAddedWeightKg : l.gymWeightKg,
    value: _c.weightKg ?? 0,
    step: _weightStep,
    decimal: true,
    max: 500,
    onChanged: (v) => _set(_c.copyWith(weightKg: () => v)),
  );
}
