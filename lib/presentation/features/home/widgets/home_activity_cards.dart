import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/presentation/features/account/reminders_page.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/home/home_health_sync.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/log_sheet.dart';
import 'package:intl/intl.dart';

/// The white panel on the calorie card's foot: the plan's target, what was eaten, and what is
/// left, over one bar. Remaining never goes below nought and the bar clamps at full; going over is
/// stated by the percentage, never scored in red (docs/05 §6).
class HomeCalorieTargets extends StatelessWidget {
  const HomeCalorieTargets({required this.day, super.key});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final target = day.targets!.kcal;
    final eaten = day.totals.kcal;
    final share = target == 0 ? 0.0 : eaten / target;
    final remaining = (target - eaten).clamp(0, target);

    Widget figure(Color dot, String label, num kcal) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: _dot,
                height: _dot,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
        Text(
          '${kcal.round()} kcal',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One scale for all three: shrinking each to its own width left them in three sizes.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                figure(AppColors.info, l.homeTarget, target),
                const SizedBox(width: AppSpacing.md),
                figure(AppColors.macroCarb, l.homeConsumed, eaten),
                const SizedBox(width: AppSpacing.md),
                figure(AppColors.warning, l.homeRemaining, remaining),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Bar(share: share, color: AppColors.success),
        ],
      ),
    );
  }

  static const _dot = 8.0;
}

/// Hydration (D-86), full width: the figure against the engine's goal, a bar, and a round + that
/// opens the log sheet on its Water tab. "Remind me" sits beside the title where reminders are
/// set up (D-222). The percentage may honestly pass 100; the bar clamps, nothing goes red.
class HomeWaterCard extends StatelessWidget {
  const HomeWaterCard({required this.day, super.key});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final logged = day.waterLoggedMl ?? 0;
    final target = day.waterTargetMl!;

    return _WhiteCard(
      tint: AppColors.info,
      child: Row(
        children: [
          const _Disc(icon: Icons.water_drop_rounded, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.homeWaterIntake, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$logged / $target ml',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _Bar(share: target == 0 ? 0 : logged / target, color: AppColors.info),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            children: [
              if (Get.isRegistered<RefreshReminders>())
                // Default density: compact would shrink the target below 48 dp (rule 12).
                IconButton(
                  tooltip: l.remindersTitle,
                  onPressed: RemindersPage.open,
                  icon: const Icon(
                    Icons.notifications_none_outlined,
                    size: AppSpacing.xl,
                    color: AppColors.info,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                tooltip: l.homeLogWater,
                onPressed: () => LogSheet.show(context, initialTab: LogSheet.waterTab),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: AppColors.lightSurface,
                  minimumSize: const Size.square(_plus),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _plus = AppSpacing.minTouchTarget;
}

/// The day's steps, full width. Rule 10: the source travels with the number. On the right, the
/// share of the server's steps goal in a ring — only when the server sends one, never a goal of
/// the app's own (rule 2). Sync sits beside the figure; Connect stays offered under it (D-218).
class HomeStepsCard extends StatelessWidget {
  const HomeStepsCard({required this.day, required this.controller, super.key});

  final DiaryDay day;
  final HomeController controller;

  static const _ring = 64.0;
  static const _ringStroke = 6.0;
  static const _trackAlpha = 0.15;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final steps = day.steps;
    // No count yet: only the offer to connect, which may itself be absent — so no card around it,
    // or the page would carry an empty white box.
    if (steps == null) return HomeHealthSync(controller: controller);

    final goal = day.stepsGoal;
    final number = NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag());

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Disc(icon: Icons.directions_run_rounded, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.homeSteps, style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.xs),
                    // Alone on its line: sharing it with the 48 dp sync button made the line that
                    // tall and opened a gap under the figure.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        number.format(steps),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.link_rounded,
                            size: AppSpacing.lg,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            // "+ you" once the person has added to a phone's count (D-221).
                            // The card is already titled Steps, so only the source.
                            day.stepsAdded != null && day.stepsSource.isAutomatic
                                ? l.homeSourceWithYou(day.stepsSource.label(l))
                                : day.stepsSource.label(l),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // At the card's right edge, centred on the row, as water's + is.
              HomeHealthSync.inline(controller: controller),
              if (goal != null && goal > 0) ...[
                const SizedBox(width: AppSpacing.sm),
                ProgressRing(
                  size: _ring,
                  strokeWidth: _ringStroke,
                  progress: steps / goal,
                  color: AppColors.macroCarb,
                  trackColor: AppColors.macroCarb.withValues(alpha: _trackAlpha),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: FittedBox(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              Icons.directions_walk_rounded,
                              size: AppSpacing.lg,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${(steps / goal * 100).round()}%',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            l.homeStepsOfGoal(number.format(goal)),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          HomeHealthSync(controller: controller, syncShownInline: true),
        ],
      ),
    );
  }
}

/// The white, shadowed card every one of these sits on.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, this.tint});

  final Widget child;

  /// A faint wash of the card's own colour over the surface — the reference's blue water card.
  /// Blended over the surface, so dark mode gets a dark card with the same hint of colour.
  final Color? tint;

  static const _tintAlpha = 0.07;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint == null
            ? theme.colorScheme.surface
            : Color.alphaBlend(tint!.withValues(alpha: _tintAlpha), theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: child,
    );
  }
}

/// A large tinted disc with the card's glyph — the reference's water drop and shoe.
class _Disc extends StatelessWidget {
  const _Disc({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  static const _size = 44.0;
  static const _washAlpha = 0.14;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _washAlpha),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: AppSpacing.xl, color: color),
    ),
  );
}

/// A rounded bar and its percentage. The bar clamps at full; the number does not.
class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.color});

  final double share;
  final Color color;

  static const _trackAlpha = 0.18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: AppSizes.barHeight,
              color: color,
              backgroundColor: color.withValues(alpha: _trackAlpha),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${(share * 100).round()}%',
          style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
