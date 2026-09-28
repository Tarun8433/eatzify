import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// How a workout behaves: rest length, screen on, sounds, effort rating, and the body diagram.
/// Each change is saved to the account as it is made.
class GymSettingsPage extends StatelessWidget {
  const GymSettingsPage({super.key});

  static Future<void>? open() => Get.to<void>(() => const GymSettingsPage());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<GymController>();
    return Scaffold(
      appBar: AppBar(title: Text(l.gymSettings)),
      body: Obx(
        () => switch (c.overview.value) {
          Loading<GymOverview>() => const LoadingView(),
          Empty<GymOverview>() => EmptyView(title: l.gymSettings),
          Failed<GymOverview>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
            retryLabel: l.accountRetry,
          ),
          Ready<GymOverview>(:final data) => _Settings(settings: data.settings, controller: c),
        },
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.settings, required this.controller});

  final GymSettings settings;
  final GymController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = settings;
    final c = controller;
    Future<void> save(GymSettings next) => c.saveSettings(next);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      children: [
        GymHeading(l.gymRestTimer),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final seconds in GymSettings.restOptions)
              ChoiceChip(
                label: Text(GymLabels.clock(seconds)),
                selected: s.restSec == seconds,
                onSelected: (_) => save(s.copyWith(restSec: seconds)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l.gymKeepAwake),
                  value: s.keepAwake,
                  onChanged: (on) => save(s.copyWith(keepAwake: on)),
                ),
                SwitchListTile(
                  title: Text(l.gymSound),
                  value: s.sound,
                  onChanged: (on) => save(s.copyWith(sound: on)),
                ),
              ],
            ),
          ),
        ),
        GymHeading(l.gymEffortSetting),
        RadioGroup<EffortScale>(
          groupValue: s.effortScale,
          onChanged: (scale) {
            if (scale != null) save(s.copyWith(effortScale: scale));
          },
          child: Column(
            children: [
              for (final scale in EffortScale.values)
                RadioListTile<EffortScale>(
                  contentPadding: EdgeInsets.zero,
                  value: scale,
                  title: Text(GymLabels.effortScale(l, scale)),
                ),
            ],
          ),
        ),
        Text(l.gymEffortHelp, style: theme.textTheme.bodySmall),
        GymHeading(l.gymBodyFigure),
        SegmentedButton<BodyFigure>(
          segments: [
            ButtonSegment(value: BodyFigure.male, label: Text(l.gymFigureMale)),
            ButtonSegment(value: BodyFigure.female, label: Text(l.gymFigureFemale)),
          ],
          selected: {s.bodyFigure},
          onSelectionChanged: (set) => save(s.copyWith(bodyFigure: set.first)),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l.gymCredits, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}
