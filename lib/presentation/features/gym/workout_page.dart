import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';
import 'package:health_pro/presentation/features/gym/exercise_about.dart';
import 'package:health_pro/presentation/features/gym/exercise_browser.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_controller.dart';
import 'package:health_pro/presentation/features/gym/workout_feedback.dart';
import 'package:health_pro/presentation/features/gym/workout_sets.dart';
import 'package:health_pro/presentation/features/gym/workout_summary_page.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The guided workout (ADR-013): one exercise — or one superset — at a time, sets ticked off with
/// rest in between, and a summary from the server at the end.
class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  static Future<void>? open(WorkoutSession session, {WorkoutFeedback? feedback}) {
    final gym = Get.find<GymController>();
    return Get.to<void>(
      () => const WorkoutPage(),
      binding: BindingsBuilder<void>(() {
        final l = lookupAppLocalizations(Get.locale ?? const Locale('en'));
        Get.lazyPut(
          () => WorkoutController(
            gym: Get.find<GymRepository>(),
            feedback: feedback ?? DeviceWorkoutFeedback(),
            session: session,
            settings: gym.ready?.settings ?? const GymSettings(),
            restAlert: (title: l.gymRestNotificationTitle, body: l.gymRestNotificationBody),
          ),
        );
      }),
    );
  }

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  final c = Get.find<WorkoutController>();
  late final Worker _events;

  @override
  void initState() {
    super.initState();
    _events = ever(c.event, (e) => e == null ? null : _onEvent(e));
  }

  @override
  void dispose() {
    _events.dispose();
    super.dispose();
  }

  Future<void> _onEvent(WorkoutEvent e) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    void say(String text) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    switch (e.kind) {
      case WorkoutEventKind.restOver:
        say(l.gymRestOver);
      case WorkoutEventKind.cardioLogged:
        say(l.gymCardioLogged);
      case WorkoutEventKind.holdLogged:
        say(l.gymHoldLogged);
      case WorkoutEventKind.askWorkingWeight:
        await _askWorkingWeight(e.entry!);
      case WorkoutEventKind.allDone:
        final finish = await confirmGym(
          context,
          title: l.gymAllDoneTitle,
          body: l.gymAllDoneBody,
          confirm: l.gymFinish,
        );
        if (finish) await _finish(skipChecks: true);
    }
  }

  Future<void> _askWorkingWeight(int entry) async {
    final s = c.session.value;
    final best = s.entries[entry].bestWeightKg ?? 0;
    final heaviest = s.heaviestDone(entry);
    final kg = await _WorkingWeightSheet.show(
      context,
      initial: heaviest > best ? heaviest : (best > 0 ? best : heaviest),
      best: best,
      last: s.allDone || s.currentGroupIndex >= s.groupCount - 1,
    );
    if (kg == null) {
      c.skipWorkingWeight(entry);
    } else {
      c.confirmWorkingWeight(entry, kg);
    }
  }

  Future<void> _finish({bool skipChecks = false}) async {
    final l = AppLocalizations.of(context);
    final s = c.session.value;
    if (!skipChecks) {
      final unchecked = s.totalSets - s.doneSets;
      final question = s.doneSets == 0
          ? l.gymNothingDone
          : unchecked > 0
          ? l.gymUncheckedLeft(unchecked)
          : null;
      if (question != null && !await confirmGym(context, title: question, confirm: l.gymFinish)) {
        return;
      }
    }
    final result = await c.finish();
    if (!mounted) return;
    final failure = result.failure;
    if (failure != null && failure is! OfflineFailure) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      return;
    }
    final gym = Get.find<GymController>();
    gym.active.value = null;
    unawaited(gym.load(quietly: true));
    if (Get.isRegistered<HomeController>()) {
      unawaited(Get.find<HomeController>().load(quietly: true));
    }
    await Get.off<void>(() => WorkoutSummaryPage(detail: result.detail));
  }

  Future<void> _discard() async {
    final l = AppLocalizations.of(context);
    final sure = await confirmGym(
      context,
      title: l.gymDiscardWorkout,
      body: l.gymDiscardWorkoutBody,
      confirm: l.gymDiscard,
      destructive: true,
    );
    if (!sure) return;
    await c.discard();
    Get.find<GymController>().active.value = null;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addExercise() async {
    final picked = await ExercisePickerPage.pick();
    if (picked == null) return;
    final detail = await Get.find<GymRepository>().exercise(picked.id);
    c.addEntry(
      detail.fold(
        (_) => offlineEntry(
          exerciseId: picked.id,
          name: picked.name,
          bodyPart: picked.bodyPart,
          isCardio: picked.isCardio,
          isBodyweight: picked.isBodyweight,
          mediaUrl: picked.mediaUrl,
        ),
        (d) => d.planEntry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      // Leaving keeps the workout: it is on the phone and Resume brings it back.
      child: Obx(() {
        final s = c.session.value;
        final group = s.currentGroup;
        final groupIndex = s.currentGroupIndex;
        final isSuperset = group.length > 1;
        final last = groupIndex >= s.groupCount - 1;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: l.gymDiscardWorkout,
              onPressed: _discard,
              icon: const Icon(Icons.close),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name),
                Text(
                  '${GymLabels.clock(c.elapsed.inSeconds)} · ${l.gymSetsProgress(s.doneSets, s.totalSets)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l.gymFinish,
                onPressed: c.saving.value ? null : _finish,
                icon: const Icon(Icons.check),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(AppSpacing.xs),
              child: LinearProgressIndicator(
                value: s.totalSets == 0 ? 0 : s.doneSets / s.totalSets,
              ),
            ),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.xxl * 6,
                ),
                children: [
                  if (s.groupCount > 0)
                    Text(
                      isSuperset
                          ? l.gymSupersetOf(groupIndex + 1, s.groupCount)
                          : l.gymExerciseOf(groupIndex + 1, s.groupCount),
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final entry in group) ...[
                    ExerciseBlock(controller: c, index: entry),
                    const SizedBox(height: AppSpacing.md),
                    ExerciseAbout(entry: s.entries[entry]),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (s.entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Text(
                        l.gymFreestyleBody,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addExercise,
                    icon: const Icon(Icons.add),
                    label: Text(l.gymAddExercise),
                  ),
                  if (c.saving.value) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(l.gymSaving, textAlign: TextAlign.center),
                  ],
                ],
              ),
              if (c.work.value != null)
                Positioned(
                  left: AppSpacing.screenH,
                  right: AppSpacing.screenH,
                  bottom: AppSpacing.md,
                  child: HoldBar(controller: c),
                )
              else if (c.restEndsAt.value != null)
                Positioned(
                  left: AppSpacing.screenH,
                  right: AppSpacing.screenH,
                  bottom: AppSpacing.md,
                  child: RestBar(controller: c),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: groupIndex > 0 ? c.previous : null,
                      child: Text(l.gymPrev),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: last
                        ? FilledButton(
                            onPressed: c.saving.value ? null : _finish,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                s.allDone
                                    ? l.gymFinish
                                    : l.gymFinishEarly(s.startedEntries, s.entries.length),
                              ),
                            ),
                          )
                        : FilledButton(onPressed: c.next, child: Text(l.gymNext)),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// After an exercise's last set: the weight the person can now work at. Asked once per exercise.
class _WorkingWeightSheet extends StatefulWidget {
  const _WorkingWeightSheet({required this.initial, required this.best, required this.last});

  final double initial;
  final double best;
  final bool last;

  static Future<double?> show(
    BuildContext context, {
    required double initial,
    required double best,
    required bool last,
  }) => showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _WorkingWeightSheet(initial: initial, best: best, last: last),
  );

  @override
  State<_WorkingWeightSheet> createState() => _WorkingWeightSheetState();
}

class _WorkingWeightSheetState extends State<_WorkingWeightSheet> {
  late double _kg = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.gymWorkingWeightTitle,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(l.gymWorkingWeightBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            GymStepper(
              label: l.gymWeightKg,
              value: _kg,
              step: 2.5,
              decimal: true,
              max: 500,
              onChanged: (v) => setState(() => _kg = v),
            ),
            if (widget.best > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _kg > widget.best
                    ? '${l.gymPreviousBest(GymLabels.kg(widget.best))} — ${l.gymNewRecord}'
                    : l.gymPreviousBest(GymLabels.kg(widget.best)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.pop(context, _kg),
              child: Text(widget.last ? l.gymSave : l.gymSaveNext),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.gymJustClose)),
          ],
        ),
      ),
    );
  }
}
