import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/progress/log_weight_sheet.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Weight, in the centre `+` sheet. docs/14 §1 lists it as one of the four tabs, and it was the one
/// still saying "not connected yet" while the Progress tab had been logging weight all along.
///
/// It is [LogWeightForm] rather than a form of its own: the suspect confirmation (docs/09 §4) and
/// the server's own error text (rule 7) live in one place, and a weight typed here lands in the
/// same history the Progress tab draws.
class WeightLogTab extends StatefulWidget {
  const WeightLogTab({super.key});

  @override
  State<WeightLogTab> createState() => _WeightLogTabState();
}

class _WeightLogTabState extends State<WeightLogTab> {
  /// `Get.put` hands back the Progress tab's controller when one is already registered, so saving
  /// here refreshes that trend instead of building a second, divergent history.
  late final _controller = Get.put(
    ProgressController(measurements: Get.find<MeasurementsRepository>()),
    permanent: true,
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    // The form owns its own padding; this is only the room under the button at 200 % font scale.
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The headline lives HERE and not in the form: the form is also the Progress tab's bottom
        // sheet, and a sheet that opens with a hero has spent half its height before the field.
        const Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: _WeightHero(),
        ),
        LogWeightForm(controller: _controller, autofocus: false),
      ],
    ),
  );
}

/// What this tab is for, beside the scales.
class _WeightHero extends StatelessWidget {
  const _WeightHero();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                    l.logWeightTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.logWeightSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ExcludeSemantics(
              child: Image.asset(AppAssets.weightHero, width: art, fit: BoxFit.contain),
            ),
          ],
        );
      },
    );
  }
}
