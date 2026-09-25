import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// What the chosen portion gives: kcal, the three macros, and the micronutrients the food table
/// carries — fibre, sodium, added sugar, saturated fat (D-238).
///
/// Every figure is the SERVER's (`POST /logs/food/preview`), scaled by the same code that scales the
/// diary entry — so what this card promises is exactly what gets logged. Nothing here multiplies
/// (CLAUDE.md rule 2); a portion change asks again.
class NutritionCard extends StatefulWidget {
  const NutritionCard({required this.food, required this.measure, required this.count, super.key});

  final Food food;

  /// Null means [count] is grams.
  final HouseholdMeasure? measure;
  final double count;

  @override
  State<NutritionCard> createState() => _NutritionCardState();
}

class _NutritionCardState extends State<NutritionCard> {
  /// A stepper tapped three times is one question, not three.
  static const _debounce = Duration(milliseconds: 250);

  NutritionPreview? _value;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  /// Which request is current. A slow answer for "1 piece" must not land after the one for "3".
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(NutritionCard old) {
    super.didUpdateWidget(old);
    final changed =
        old.food.id != widget.food.id ||
        old.measure?.label != widget.measure?.label ||
        old.count != widget.count;
    if (!changed) return;
    _timer?.cancel();
    setState(() => _loading = true);
    _timer = Timer(_debounce, () => unawaited(_fetch()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final ask = ++_asked;
    final measure = widget.measure;
    final result = await Get.find<DiaryRepository>().previewFood(
      foodId: widget.food.id,
      measure: measure?.label,
      measureCount: measure == null ? null : widget.count,
      quantityG: measure == null ? widget.count : null,
    );
    if (!mounted || ask != _asked) return;
    setState(() {
      _loading = false;
      // A failed refresh keeps the last figures on screen: they are for a portion one tap away,
      // which is more use than an empty card.
      result.fold((f) => _error = f.userMessage, (v) {
        _value = v;
        _error = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return NutritionSummary(
      value: _value,
      // Dimmed, not blanked, while a new portion is priced: the numbers stay readable and the
      // card does not jump.
      dimmed: _loading && _value != null,
      footer: _error == null
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
                TextButton(onPressed: _fetch, child: Text(l.accountRetry)),
              ],
            ),
    );
  }
}

/// The nutrition of one portion or one plate: kcal, the three macros in their ring colours, and
/// the micronutrients — the same card whether the numbers are the server's scaling of a food
/// (the add sheet) or a model's estimate of a photo (the scan sheet, which says so in [note]).
class NutritionSummary extends StatelessWidget {
  const NutritionSummary({
    required this.value,
    super.key,
    this.dimmed = false,
    this.note,
    this.footer,
  });

  /// Null draws dashes: the figures are still coming.
  final NutritionPreview? value;
  final bool dimmed;

  /// A line under the title — "AI estimate…" for a scanned plate.
  final String? note;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final v = value;

    return AppCard(
      child: AnimatedOpacity(
        opacity: dimmed ? 0.5 : 1,
        duration: AppMotion.fast,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.logNutritionTitle, style: theme.textTheme.labelLarge),
            if (note != null)
              Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    v == null ? '—' : '${v.kcal.round()}',
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('kcal', style: theme.textTheme.bodyMedium),
                ),
                const Spacer(),
                if (v != null)
                  Flexible(
                    child: Text(
                      l.logNutritionPortion(_amount(v.grams)),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MacroTile(
                    label: l.homeProtein,
                    value: v == null ? '—' : '${_amount(v.proteinG)} g',
                    color: AppColors.macroProtein,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _MacroTile(
                    label: l.homeCarbs,
                    value: v == null ? '—' : '${_amount(v.carbG)} g',
                    color: AppColors.macroCarb,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _MacroTile(
                    label: l.homeFat,
                    value: v == null ? '—' : '${_amount(v.fatG)} g',
                    color: AppColors.macroFat,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(color: theme.colorScheme.outline),
            _MicroRow(label: l.logFibre, value: v == null ? '—' : '${_amount(v.fibreG)} g'),
            _MicroRow(label: l.logSodium, value: v == null ? '—' : '${v.sodiumMg.round()} mg'),
            _MicroRow(
              label: l.logAddedSugar,
              value: v == null ? '—' : '${_amount(v.addedSugarG)} g',
            ),
            _MicroRow(
              label: l.logSaturatedFat,
              value: v == null ? '—' : '${_amount(v.saturatedFatG)} g',
            ),
            if (footer != null) ...[const SizedBox(height: AppSpacing.sm), footer!],
          ],
        ),
      ),
    );
  }
}

/// One decimal under ten, whole numbers above — "6.2 g" of fibre matters, "64.2 g" of carbs is
/// noise. The value itself is the server's or the model's; this only decides how many digits to
/// print.
String _amount(double v) {
  if (v >= 10) return '${v.round()}';
  final fixed = v.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// A macro in its ring colour (D-61), so it reads as the same macro the Home rings show.
class _MacroTile extends StatelessWidget {
  const _MacroTile({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MicroRow extends StatelessWidget {
  const _MicroRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
