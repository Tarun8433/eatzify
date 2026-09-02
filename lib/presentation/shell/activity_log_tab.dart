import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Manual activity entry (D-80): steps, and calories burned if the user happens to know them.
///
/// Deliberately NOT a calculator. Turning steps into calories needs a MET table and a stride
/// length, and the number it produced would go straight into "kcal left" — the app computing an
/// energy figure the user then eats against, which is the line CLAUDE.md rule 2 draws. Either the
/// user's watch tells them, or the figure stays unknown and Home keeps saying so.
///
/// Both fields are optional and either can be sent alone. Someone who walked and does not own a
/// watch has steps and nothing else, and that is a complete answer.
class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab> {
  /// docs/03 §2 ranges. Named, because the same two numbers set the wheel, the bound check and the
  /// caption under each field — three copies of `100000` is how those three drift apart.
  static const _maxSteps = 100000;
  static const _maxBurned = 8000;

  /// What one notch of the wheel moves. Steps are counted in thousands and kcal in tens; a
  /// step-of-one wheel for 100,000 steps is a wheel nobody can reach the end of.
  static const _stepsNotch = 500;
  static const _burnedNotch = 50;

  int? _steps;
  int? _burned;
  bool _saving = false;

  /// The server's `user_message`, verbatim (CLAUDE.md rule 7).
  String? _error;

  bool get _canSave => !_saving && (_steps != null || _burned != null);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final measurements = Get.find<MeasurementsRepository>();
    // Two rows, because they are two measurements. The server overwrites per kind per diary day,
    // so saving twice in one day corrects the figure rather than adding to it.
    final results = [
      if (_steps != null)
        await measurements.record(kind: 'steps', value: _steps!.toDouble(), unit: 'steps'),
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
            child: NumberField(
              label: l.logActivityStepsHint,
              helperText: l.logActivityStepsRange(_maxSteps),
              // Typed OR scrolled (D-95). Someone who read 8,432 off a watch types it; someone
              // logging "about six thousand" spins to it.
              picker: const NumberPickerConfig(min: 0, max: _maxSteps, step: _stepsNotch),
              onLiveChange: (v) => setState(() => _steps = _bounded(v, _maxSteps)),
              onCommit: (v) => setState(() => _steps = _bounded(v, _maxSteps)),
            ),
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
              picker: const NumberPickerConfig(min: 0, max: _maxBurned, step: _burnedNotch),
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
                AppAssets.activityHero,
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
