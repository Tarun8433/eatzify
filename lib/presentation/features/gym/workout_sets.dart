import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/presentation/features/gym/exercise_detail_sheet.dart';
import 'package:health_pro/presentation/features/gym/exercise_media.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// One exercise on the workout screen: what it is, last time, why today's numbers are what they
/// are, and its sets.
class ExerciseBlock extends StatelessWidget {
  const ExerciseBlock({required this.controller, required this.index, super.key});

  final WorkoutController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entry = controller.session.value.entries[index];
    final why = entry.prescription;
    final best = entry.bestWeightKg;
    final perSideReps = entry.perSide ? (entry.target.reps ?? 0) ~/ 2 : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GymIconDisc(icon: GymLabels.bodyPartIcon(entry.bodyPart)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  GymLabels.name(entry.name),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: l.gymAboutExercise,
                onPressed: () =>
                    ExerciseDetailSheet.show(context, entry.exerciseId, readOnly: true),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          // Under the name, above the sets: the movement is what the name means.
          if (entry.mediaUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: ExerciseMedia(
                url: entry.mediaUrl,
                maxSide: 200,
                semanticsLabel: l.gymMediaLabel(GymLabels.name(entry.name)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (entry.mode != ExerciseMode.reps) Chip(label: Text(GymLabels.mode(l, entry.mode))),
              if (perSideReps != null) Chip(label: Text(l.gymPerSide(perSideReps))),
              if (best != null && best > 0) Chip(label: Text(l.gymBestKg(GymLabels.kg(best)))),
            ],
          ),
          if (entry.lastDate != null)
            Text(
              l.gymLastTimeSets(
                GymLabels.day(context, entry.lastDate!),
                GymLabels.sets(l, entry.mode, entry.lastSets),
              ),
              style: theme.textTheme.bodySmall,
            ),
          if (why != null && why.whyCode != 'off') ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              GymLabels.why(l, why),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (var s = 0; s < entry.sets.length; s++)
            _SetRow(controller: controller, entry: index, set: s),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: entry.sets.length > 1 ? () => controller.removeSet(index) : null,
                icon: const Icon(Icons.remove),
                label: Text(l.gymRemoveSet),
              ),
              TextButton.icon(
                onPressed: () => controller.addSet(index),
                icon: const Icon(Icons.add),
                label: Text(l.gymAddSet),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A set: its number, its values as tappable boxes, and the tick. Values edit in a sheet with a
/// stepper, so every target stays a finger's width at any text size.
class _SetRow extends StatelessWidget {
  const _SetRow({required this.controller, required this.entry, required this.set});

  final WorkoutController controller;
  final int entry;
  final int set;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = controller.session.value.entries[entry];
    final s = e.sets[set];
    final scale = controller.settings.effortScale;

    void edit(WorkoutSet next) => controller.setValue(entry, set, next);

    final boxes = switch (e.mode) {
      ExerciseMode.cardio => [
        _ValueBox(
          label: l.gymColMinutes,
          value: s.minutes ?? 0,
          step: 1,
          decimal: true,
          max: 600,
          onChanged: (v) => edit(s.copyWith(minutes: v)),
        ),
        _ValueBox(
          label: l.gymColSpeed,
          value: s.speedKmh ?? 0,
          step: 0.5,
          decimal: true,
          max: 40,
          onChanged: (v) => edit(s.copyWith(speedKmh: v)),
        ),
      ],
      ExerciseMode.time => [
        _ValueBox(
          label: l.gymColSeconds,
          value: (s.seconds ?? 0).toDouble(),
          step: 5,
          max: 3600,
          onChanged: (v) => edit(s.copyWith(seconds: v.round())),
        ),
        if (!e.isBodyweight || (s.weightKg ?? 0) > 0)
          _ValueBox(
            label: l.gymColKg,
            value: s.weightKg ?? 0,
            step: 2.5,
            decimal: true,
            max: 500,
            onChanged: (v) => edit(s.copyWith(weightKg: v)),
          ),
      ],
      ExerciseMode.reps => [
        if (!e.isBodyweight || (s.weightKg ?? 0) > 0)
          _ValueBox(
            label: l.gymColKg,
            value: s.weightKg ?? 0,
            step: 2.5,
            decimal: true,
            max: 500,
            onChanged: (v) => edit(s.copyWith(weightKg: v)),
          ),
        _ValueBox(
          label: l.gymColReps,
          value: (s.reps ?? 0).toDouble(),
          step: e.perSide ? 2 : 1,
          max: 500,
          onChanged: (v) => edit(s.copyWith(reps: v.round())),
        ),
        if (scale == EffortScale.rir)
          _ValueBox(
            label: l.gymColRir,
            value: s.rir,
            step: 0.5,
            decimal: true,
            max: 10,
            onChanged: (v) => edit(s.copyWith(rir: () => v)),
          ),
        if (scale == EffortScale.rpe)
          _ValueBox(
            label: l.gymColRpe,
            value: s.rpe,
            step: 0.5,
            decimal: true,
            min: 6,
            max: 10,
            onChanged: (v) => edit(s.copyWith(rpe: () => v)),
          ),
      ],
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: s.done ? 0.6 : 1,
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: AppSpacing.md + AppSpacing.xs,
                backgroundColor: s.done
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.secondaryContainer,
                child: Text(
                  '${set + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: s.done ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            for (final box in boxes) Expanded(child: box),
            if (e.mode == ExerciseMode.time && !s.done)
              IconButton(
                tooltip: l.gymStartHold,
                onPressed: () => controller.startHold(entry, set),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            IconButton(
              tooltip: s.done ? l.gymMarkNotDone(set + 1) : l.gymMarkDone(set + 1),
              onPressed: () => controller.toggle(entry, set),
              iconSize: AppSpacing.xl + AppSpacing.xs,
              icon: Icon(
                s.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: s.done ? theme.colorScheme.secondary : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A value on a set row. Null shows a dash — an effort not rated is not a zero.
class _ValueBox extends StatelessWidget {
  const _ValueBox({
    required this.label,
    required this.value,
    required this.step,
    required this.onChanged,
    this.decimal = false,
    this.min = 0,
    this.max = 999,
  });

  final String label;
  final double? value;
  final double step;
  final bool decimal;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final v = value;
    final shown = v == null ? '–' : (decimal ? GymLabels.kg(v) : v.round().toString());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Semantics(
        button: true,
        label: '${l.gymEditValue(label)}: $shown',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () async {
            final next = await _ValueSheet.show(
              context,
              label: label,
              value: v ?? min,
              step: step,
              decimal: decimal,
              min: min,
              max: max,
            );
            if (next != null) onChanged(next);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueSheet extends StatefulWidget {
  const _ValueSheet({
    required this.label,
    required this.value,
    required this.step,
    required this.decimal,
    required this.min,
    required this.max,
  });

  final String label;
  final double value;
  final double step;
  final bool decimal;
  final double min;
  final double max;

  static Future<double?> show(
    BuildContext context, {
    required String label,
    required double value,
    required double step,
    required bool decimal,
    required double min,
    required double max,
  }) => showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (_) =>
        _ValueSheet(label: label, value: value, step: step, decimal: decimal, min: min, max: max),
  );

  @override
  State<_ValueSheet> createState() => _ValueSheetState();
}

class _ValueSheetState extends State<_ValueSheet> {
  late double _value = widget.value.clamp(widget.min, widget.max);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GymStepper(
              label: widget.label,
              value: _value,
              step: widget.step,
              decimal: widget.decimal,
              min: widget.min,
              max: widget.max,
              onChanged: (v) => setState(() => _value = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: () => Navigator.pop(context, _value), child: Text(l.gymDone)),
          ],
        ),
      ),
    );
  }
}

/// The rest countdown, floating over the bottom of the screen: −15 s, +15 s, skip.
class RestBar extends StatelessWidget {
  const RestBar({required this.controller, super.key});

  final WorkoutController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final remaining = controller.restRemaining;
    final total = controller.restTotalSec <= 0 ? 1 : controller.restTotalSec;
    return _TimerCard(
      title: l.gymRestTitle,
      clock: GymLabels.clock(remaining),
      progress: remaining / total,
      actions: [
        OutlinedButton(onPressed: controller.cutRest, child: Text(l.gymRestMinus)),
        OutlinedButton(onPressed: controller.addRest, child: Text(l.gymRestPlus)),
        FilledButton(onPressed: controller.skipRest, child: Text(l.gymRestSkip)),
      ],
      liveLabel: '${l.gymRestTitle} ${GymLabels.clock(remaining)}',
      color: theme.colorScheme.secondary,
    );
  }
}

/// A timed hold counting down, with Cancel and Done (Done logs what was actually held).
class HoldBar extends StatelessWidget {
  const HoldBar({required this.controller, super.key});

  final WorkoutController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final w = controller.work.value!;
    final remaining = controller.workRemaining;
    final name = controller.session.value.entries[w.entry].name;
    return _TimerCard(
      title: '${l.gymHold} · ${GymLabels.name(name)}',
      clock: GymLabels.clock(remaining),
      progress: remaining / (w.target <= 0 ? 1 : w.target),
      actions: [
        OutlinedButton(onPressed: controller.cancelHold, child: Text(l.gymCancel)),
        FilledButton(onPressed: controller.finishHold, child: Text(l.gymDone)),
      ],
      liveLabel: '${l.gymHold} ${GymLabels.clock(remaining)}',
      color: theme.colorScheme.primary,
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.title,
    required this.clock,
    required this.progress,
    required this.actions,
    required this.liveLabel,
    required this.color,
  });

  final String title;
  final String clock;
  final double progress;
  final List<Widget> actions;
  final String liveLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            Semantics(
              liveRegion: true,
              label: liveLabel,
              excludeSemantics: true,
              child: Text(
                clock,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: progress.clamp(0, 1), color: color),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
