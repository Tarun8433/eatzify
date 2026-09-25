import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/food_scan.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/nutrition_card.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart';

/// How a scan ended, for the food tab to act on.
sealed class ScanOutcome {
  const ScanOutcome();
}

/// "Yes, I'm having this": log the items at [keep] of scan [scanId] to [slot], as one entry with
/// the photo. The server sums them from its own stored estimate.
class ScanConfirmed extends ScanOutcome {
  const ScanConfirmed({required this.scanId, required this.slot, required this.keep});

  final int scanId;
  final String slot;
  final List<int> keep;
}

/// "No", or nothing recognised: back to search, with the plate's name typed in when there was one.
class ScanSearchInstead extends ScanOutcome {
  const ScanSearchInstead([this.query]);

  final String? query;
}

/// "Are you having this?" (D-240). The user's photo, what the model thinks is on the plate — each
/// item can be unticked when it is wrong — the estimated nutrition of what is kept, and the meal.
/// Nothing is logged until "Yes".
class ScanResultSheet extends StatefulWidget {
  const ScanResultSheet({required this.photoPath, required this.estimate, super.key});

  final String photoPath;

  /// Recognised — an unrecognised scan gets [ScanNoMatchSheet] instead.
  final ScanEstimate estimate;

  @override
  State<ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends State<ScanResultSheet> {
  late final Set<int> _kept = {for (var i = 0; i < widget.estimate.items.length; i++) i};
  late String _slot = slotForHour(DateTime.now().hour);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final estimate = widget.estimate;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ScanPhoto(path: widget.photoPath),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.scanConfirmTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(l.scanLooksLike(estimate.dishName), style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l.scanOnYourPlate, style: theme.textTheme.labelLarge),
          Text(
            l.scanUntickHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final (i, item) in estimate.items.indexed)
            CheckboxListTile(
              value: _kept.contains(i),
              onChanged: (on) => setState(() => on! ? _kept.add(i) : _kept.remove(i)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(item.name),
              subtitle: Text(
                '${item.nutrition.grams.round()} g · ${item.nutrition.kcal.round()} kcal',
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          NutritionSummary(value: estimate.totalOf(_kept), note: l.scanEstimateNote),
          const SizedBox(height: AppSpacing.lg),
          MealChips(slot: _slot, onChanged: (s) => setState(() => _slot = s)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop<ScanOutcome>(ScanSearchInstead(estimate.dishName)),
                  child: Text(l.scanNo),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: FilledButton(
                  // Nothing kept is nothing to log — the button says so by being off.
                  onPressed: _kept.isEmpty
                      ? null
                      : () => Navigator.of(context).pop<ScanOutcome>(
                          ScanConfirmed(
                            scanId: estimate.scanId!,
                            slot: _slot,
                            keep: _kept.toList()..sort(),
                          ),
                        ),
                  child: Text(l.scanYes(slotLabel(l, _slot))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nothing on the plate was recognised. Never a guess: a heading, one sentence, one action
/// (ui-standards: empty states).
class ScanNoMatchSheet extends StatelessWidget {
  const ScanNoMatchSheet({required this.photoPath, super.key});

  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanPhoto(path: photoPath),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l.scanNoMatchTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l.scanNoMatchBody, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop<ScanOutcome>(const ScanSearchInstead()),
              child: Text(l.scanSearchInstead),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user's own photo, rounded — so they can see what the answer is about.
class ScanPhoto extends StatelessWidget {
  const ScanPhoto({required this.path, super.key});

  final String path;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: Image.file(
        File(path),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        // Decoration: the words beside it say what was found.
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => Container(
          width: _size,
          height: _size,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.photo_camera_outlined, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
