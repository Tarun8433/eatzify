import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// How a workout begins: resume the one in progress, or weigh in and start one — today's routine,
/// another, or freestyle. The session's numbers are the server's plan for that routine, sent ahead
/// in the overview, so this works with no signal.
abstract final class WorkoutLauncher {
  static Future<void> start(
    BuildContext context, {
    Routine? routine,
    bool freestyle = false,
    bool chooseFirst = false,
  }) async {
    final gym = Get.find<GymController>();
    final active = gym.active.value;
    if (active != null) {
      await WorkoutPage.open(active);
      return;
    }

    var chosen = routine;
    var isFreestyle = freestyle;
    // Nothing is planned for today, or another workout was asked for: pick the workout before the
    // weigh-in, so a rest day is still one tap from any routine.
    if (chooseFirst) {
      final pick = await StartChooserSheet.show(context);
      if (pick == null) return;
      chosen = pick.routine;
      isFreestyle = pick.routine == null;
    }
    while (true) {
      if (!context.mounted) return;
      final weighIn = await WeighInSheet.show(context);
      if (weighIn == null) return;
      if (weighIn.chooseOther) {
        if (!context.mounted) return;
        final pick = await StartChooserSheet.show(context);
        if (pick == null) return;
        chosen = pick.routine;
        isFreestyle = pick.routine == null;
        continue;
      }
      if (!context.mounted) return;
      final l = AppLocalizations.of(context);
      final session = WorkoutSession.start(
        name: isFreestyle || chosen == null ? l.gymFreestyle : chosen.name,
        routineId: isFreestyle ? null : chosen?.id,
        plan: isFreestyle || chosen == null
            ? const []
            : gym.ready?.sessionPlans[chosen.id] ?? const [],
        now: DateTime.now(),
        bodyWeightKg: weighIn.kg,
      );
      await gym.gym.saveActiveWorkout(session);
      gym.active.value = session;
      await WorkoutPage.open(session);
      return;
    }
  }
}

/// "Quick check-in": today's weight, which goes on the weight chart like any other and prices the
/// workout's energy estimate. Skipping it is a normal choice, not a lesser one.
class WeighInSheet extends StatefulWidget {
  const WeighInSheet({super.key});

  static Future<({double? kg, bool chooseOther})?> show(BuildContext context) =>
      showModalBottomSheet<({double? kg, bool chooseOther})>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => const WeighInSheet(),
      );

  @override
  State<WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<WeighInSheet> {
  static const _fallbackKg = 70.0;
  static const _step = 0.1;

  double _kg = _fallbackKg;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// The last weigh-in, so most mornings are one tap.
  Future<void> _prefill() async {
    if (!Get.isRegistered<MeasurementsRepository>()) return;
    final history = await Get.find<MeasurementsRepository>().history('weight');
    if (!mounted) return;
    history.fold((_) {}, (h) {
      if (h.points.isNotEmpty) setState(() => _kg = h.points.last.value);
    });
  }

  Future<void> _saveAndStart() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await Get.find<MeasurementsRepository>().record(
      kind: 'weight',
      value: _kg,
      unit: 'kg',
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _saving = false;
        _error = failure.userMessage;
      }),
      (_) => Navigator.pop(context, (kg: _kg, chooseOther: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.gymWeighInTitle,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(l.gymWeighInBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            GymStepper(
              label: l.gymWeightKg,
              value: _kg,
              step: _step,
              decimal: true,
              min: 20,
              max: 300,
              onChanged: (v) => setState(() => _kg = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _saving ? null : _saveAndStart, child: Text(l.gymSaveAndStart)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.pop(context, (kg: null, chooseOther: false)),
              child: Text(l.gymStartWithout),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.pop(context, (kg: null, chooseOther: true)),
              child: Text(l.gymChooseOther),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(l.gymCancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Another routine, or freestyle.
abstract final class StartChooserSheet {
  static Future<({Routine? routine})?> show(BuildContext context) {
    final l = AppLocalizations.of(context);
    final routines = Get.find<GymController>().ready?.routines ?? const <Routine>[];
    return showModalBottomSheet<({Routine? routine})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in routines)
              ListTile(
                leading: GymIconDisc(icon: GymLabels.iconFor(r.icon)),
                title: Text(r.name),
                subtitle: Text(l.gymExerciseCount(r.items.length)),
                onTap: () => Navigator.pop(context, (routine: r)),
              ),
            ListTile(
              leading: const GymIconDisc(icon: Icons.bolt_outlined),
              title: Text(l.gymFreestyle),
              subtitle: Text(l.gymFreestyleBody),
              onTap: () => Navigator.pop(context, (routine: null)),
            ),
          ],
        ),
      ),
    );
  }
}
