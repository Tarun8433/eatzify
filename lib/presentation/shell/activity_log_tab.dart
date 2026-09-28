import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/usecases/adjust_steps.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Manual activity entry (D-80): steps, and calories burned if the user happens to know them.
///
/// Deliberately NOT a calculator. Turning steps into calories needs a MET table and a stride
/// length, and the number it produced would go straight into "kcal left" — the app computing an
/// energy figure the user then eats against, which is the line CLAUDE.md rule 2 draws. Either the
/// user's watch tells them, or the figure stays unknown and Home keeps saying so.
///
/// Both fields are optional and either can be sent alone. Someone who walked and does not own a
/// watch has steps and nothing else, and that is a complete answer.
///
/// Steps are a CHANGE to today's count (D-220): it shows what the day already holds, and what is
/// typed is added to it or taken off it. The change is stored apart from what the phone counted
/// (D-221), so a later sync adds to it instead of wiping it. Calories burned stays a figure,
/// because nobody adds to a watch's calorie reading by hand.
class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab> {
  /// docs/03 §2 ranges. Named, because the same two numbers set the wheel, the bound check and the
  /// caption under each field — three copies of `100000` is how those three drift apart.
  static const _maxBurned = 8000;

  /// What one notch of the wheel moves. Steps are counted in thousands and kcal in tens; a
  /// step-of-one wheel for 100,000 steps is a wheel nobody can reach the end of.
  static const _stepsNotch = 500;
  static const _burnedNotch = 50;

  /// Where each wheel opens: a short walk, a light session. The middle of the range put steps at
  /// 50,000 and burned at 4,000 — numbers nobody means, one careless Done from being saved.
  static const _stepsOpensAt = 1000;
  static const _burnedOpensAt = 200;

  /// Today, for the count the change applies to. Always today's, whichever day Home is showing:
  /// this sheet writes to today.
  ViewState<DiaryDay> _today = const Loading();

  /// What was typed for steps, before it is applied. Zero is no change, so it is null too.
  int? _stepsChange;
  bool _removing = false;
  int? _burned;
  bool _saving = false;

  /// The server's `user_message`, verbatim (CLAUDE.md rule 7).
  String? _error;

  int? get _currentSteps => switch (_today) {
    Ready<DiaryDay>(:final data) => data.steps,
    _ => null,
  };

  int? get _addedSteps => switch (_today) {
    Ready<DiaryDay>(:final data) => data.stepsAdded,
    _ => null,
  };

  /// The day's count after the change, or null when there is nothing valid to save — including
  /// while today has not loaded, because a change to an unknown count has no total.
  int? get _stepsTotal {
    final change = _stepsChange;
    if (change == null || _today is! Ready<DiaryDay>) return null;
    return AdjustSteps.total(current: _currentSteps, amount: change, remove: _removing);
  }

  bool get _canSave => !_saving && (_stepsTotal != null || _burned != null);

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    setState(() => _today = const Loading());
    final result = await Get.find<DiaryRepository>().day();
    if (!mounted) return;
    setState(() => _today = result.fold(Failed.new, Ready.new));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final measurements = Get.find<MeasurementsRepository>();
    // Two rows, because they are two measurements. The server overwrites per kind per diary day,
    // so saving twice in one day corrects the figure rather than adding to it.
    final change = _stepsTotal == null ? null : _stepsChange;
    final results = [
      if (change != null)
        await measurements.record(
          kind: 'steps_added',
          value: AdjustSteps.added(
            previous: _addedSteps,
            amount: change,
            remove: _removing,
          ).toDouble(),
          unit: 'steps',
        ),
      if (_burned != null)
        await measurements.record(
          kind: 'energy_burned_kcal',
          value: _burned!.toDouble(),
          unit: 'kcal',
        ),
    ];

    final failure = results
        .map((r) => r.fold((f) => f.userMessage, (_) => null))
        .whereType<String>()
        .firstOrNull;

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = failure;
    });
    if (failure != null) return;

    // Home reads the day, and the day now carries the activity — so it has to be asked again.
    if (Get.isRegistered<HomeController>()) await Get.find<HomeController>().load();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ActivityHero(),
          const SizedBox(height: AppSpacing.xl),
          // One card per measurement, because they ARE two measurements: the server stores them
          // separately and either can be sent alone. Two fields stacked on the bare sheet read as
          // one form that has to be completed.
          _FieldCard(
            icon: Icons.directions_walk,
            title: l.logActivitySteps,
            child: _stepsEditor(l, theme),
          ),
          const SizedBox(height: AppSpacing.lg),
          _FieldCard(
            icon: Icons.local_fire_department_outlined,
            // Warm, not green: this is the optional one, and the one the hint below warns about.
            tint: AppColors.warmCoral,
            title: l.logActivityBurned,
            child: NumberField(
              label: l.logActivityBurnedHint,
              helperText: l.logActivityBurnedRange(_maxBurned),
              picker: const NumberPickerConfig(
                min: 0,
                max: _maxBurned,
                step: _burnedNotch,
                opensAt: _burnedOpensAt,
              ),
              onLiveChange: (v) => setState(() => _burned = _bounded(v, _maxBurned)),
              onCommit: (v) => setState(() => _burned = _bounded(v, _maxBurned)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // The warning that a guessed figure changes what the user is told to eat is the most
          // important sentence on the screen, and as a grey caption under a field it was the least
          // visible thing on it.
          HintCard(icon: Icons.lightbulb_outline, text: l.logActivityHint),
          const SizedBox(height: AppSpacing.xl),
          if (_error != null) ...[
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SizedBox(
            height: AppSizes.primaryButton,
            child: FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l.logActivitySave),
            ),
          ),
        ],
      ),
    );
  }

  /// What the day holds, which way the change goes, how much, and where that leaves the day.
  Widget _stepsEditor(AppLocalizations l, ThemeData theme) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final numbers = NumberFormat.decimalPattern(locale);
    final signed = NumberFormat('+#,##0;−#,##0', locale);
    final current = _currentSteps;
    final limit = AdjustSteps.limit(current: current, remove: _removing);
    final total = _stepsTotal;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final String? outcome;
    if (_stepsChange == null || _today is! Ready<DiaryDay>) {
      outcome = null;
    } else if (total != null) {
      outcome = l.logActivityStepsNewTotal(numbers.format(total));
    } else {
      outcome = _removing
          ? l.logActivityStepsTooFew(numbers.format(current ?? 0))
          : l.logActivityStepsTooMany(numbers.format(AdjustSteps.max));
    }

    final today = _today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (today) {
          Loading<DiaryDay>() => Text(l.logActivityStepsLoading, style: muted),
          Ready<DiaryDay>(:final data) => Text(
            // Rule 10: where the count came from, beside it — and how much of it is the person's.
            switch (data) {
              DiaryDay(steps: null) => l.logActivityStepsNone,
              DiaryDay(:final steps?, :final stepsAdded?) when data.stepsSource.isAutomatic =>
                l.logActivityStepsNowSplit(
                  numbers.format(steps),
                  numbers.format(steps - stepsAdded),
                  data.stepsSource.label(l),
                  signed.format(stepsAdded),
                ),
              DiaryDay(:final steps?) => l.logActivityStepsNow(
                numbers.format(steps),
                data.stepsSource.label(l),
              ),
            },
            style: theme.textTheme.bodyMedium,
          ),
          // Empty is not a state this read produces; a day always comes back.
          Empty<DiaryDay>() => Text(l.logActivityStepsNone, style: theme.textTheme.bodyMedium),
          Failed<DiaryDay>(:final failure) => Row(
            children: [
              Expanded(
                child: Text(
                  failure.userMessage,
                  style: muted?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              TextButton(onPressed: _loadToday, child: Text(l.accountRetry)),
            ],
          ),
        },
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.add), label: Text(l.logActivityAdd)),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.remove),
              label: Text(l.logActivityRemove),
              // Nothing to take off a day with no count.
              enabled: (current ?? 0) > 0,
            ),
          ],
          selected: {_removing},
          onSelectionChanged: (choice) => setState(() => _removing = choice.first),
        ),
        const SizedBox(height: AppSpacing.md),
        NumberField(
          label: _removing ? l.logActivityStepsRemoveHint : l.logActivityStepsAddHint,
          helperText: l.logActivityStepsRange(limit),
          // Typed OR scrolled (D-95). Someone who read 8,432 off a watch types it; someone
          // logging "about six thousand" spins to it.
          picker: NumberPickerConfig(
            min: 0,
            max: limit,
            step: _stepsNotch,
            // On a notch, or Done would commit a number the wheel is not showing.
            opensAt: math.min(_stepsOpensAt, limit - limit % _stepsNotch),
          ),
          onLiveChange: (v) => setState(() => _stepsChange = _change(v)),
          onCommit: (v) => setState(() => _stepsChange = _change(v)),
        ),
        if (outcome != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            outcome,
            style: theme.textTheme.titleSmall?.copyWith(
              color: total == null ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
        ],
        // Someone who just connected a watch will wonder whether the next sync undoes this. It
        // does not (D-221), and the place to say so is before they save.
        if (total != null && today is Ready<DiaryDay> && today.data.stepsSource.isAutomatic) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l.logActivityStepsKept(today.data.stepsSource.label(l)), style: muted),
        ],
      ],
    );
  }

  static int? _change(String raw) {
    final parsed = int.tryParse(raw);
    return parsed == 0 ? null : parsed;
  }

  /// Out of range reads as "not answered", not as a rejection — the server's bounds are the ones
  /// that matter, and 200,000 steps is a typo rather than something to write copy about.
  static int? _bounded(String raw, int max) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > max) return null;
    return parsed;
  }
}

/// The screen's opening line: what this tab is for, beside someone doing it.
class _ActivityHero extends StatelessWidget {
  const _ActivityHero();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The art takes its SHARE of the width rather than a size invented for this screen — the same
    // pair of numbers the sign-in and goal heroes use (D-111), with a ceiling so it does not
    // balloon on a tablet.
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = (constraints.maxWidth * AppSizes.heroArtFraction).clamp(
          0.0,
          AppSizes.heroArtMax,
        );

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.logActivityTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.logActivitySubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ExcludeSemantics(
              child: Image.asset(
                AppAssets.themed(AppAssets.activityHero, Theme.of(context).brightness),
                width: art,
                // The illustration is square once its empty canvas is trimmed off, and it is drawn
                // at the size it was encoded for — art scaled up is blurry art.
                fit: BoxFit.contain,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One measurement: what it is, and the field that takes it.
class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.icon, required this.title, required this.child, this.tint});

  final IconData icon;
  final String title;
  final Widget child;

  /// The disc's colour. Defaults to the brand tint; the optional measurement is warm.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = tint == null
        ? scheme.secondaryContainer.withValues(alpha: 0.6)
        : tint!.withValues(alpha: 0.14);
    final glyph = tint ?? scheme.onSecondaryContainer;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                  child: Icon(icon, size: AppSpacing.xl, color: glyph),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
