import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/food_image.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/plan.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/premium_widgets.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/plan/plan_controller.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

/// tabPlan. docs/14 §1, four states per CLAUDE.md rule 6.
///
/// Shows the day's energy split across meal slots rather than one calorie figure. docs/05 §6 is
/// the reason: "about 558 kcal at breakfast" is guidance a person can act on, where a lone daily
/// number with no food attached is closer to a score.
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = Get.put(PlanController(plans: Get.find<PlanRepository>()), permanent: true);
    // Absent in tests that are not about billing, and on any build where the repository is not
    // registered — every premium surface then simply stays away, which is also the failure mode.
    final billing = Get.isRegistered<BillingRepository>()
        ? Get.put(BillingController(billing: Get.find<BillingRepository>()), permanent: true)
        : null;

    return TabScaffold(
      title: l10n.tabPlan,
      titleIcon: Icons.eco,
      subtitle: l10n.planSubtitle,
      action: billing == null ? null : PremiumPill(billing: billing),
      child: Obx(
        () => switch (c.state.value) {
          Loading<Plan>() => const LoadingView(),
          Empty<Plan>() => _NoPlan(controller: c),
          Failed<Plan>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
            retryLabel: l10n.accountRetry,
          ),
          Ready<Plan>(:final data) => _PlanView(plan: data, controller: c),
        },
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.controller});

  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l.planEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(l.planEmptyBody, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xl),
          Obx(
            () => Column(
              children: [
                if (controller.error.value != null) ...[
                  // docs/05 §7 referral copy arrives here when a gate blocks the plan.
                  Text(
                    controller.error.value!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                FilledButton(
                  onPressed: controller.generating.value ? null : controller.generate,
                  child: Text(l.homeCreatePlan),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({required this.plan, required this.controller});

  final Plan plan;
  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = plan.targets;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.xxl),
      children: [
        if (targets != null) ...[
          _TargetCard(targets: targets, plan: plan),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Said once, quietly, and never as a rule about a person: docs/05 §6 rules out streaks and
        // scores, and "you have broken your run" is exactly the sentence they rule out.
        // One line, no heading (D-137): the tab is numbers, and a paragraph of encouragement
        // between the user and their meals is the thing being scrolled past, not read.
        HintCard(dense: true, icon: Icons.lightbulb_outline, text: l.planAdviceBody),
        const SizedBox(height: AppSpacing.lg),
        // docs/05 §7, verbatim. Rule 7 — the app never writes its own copy for a safety message;
        // the CHROME is ours, and a bare white rectangle read as a rendering fault between two
        // finished cards (D-135).
        // Every word stays — rule 7, it is the server's safety copy — but at note size, not
        // paragraph size. The words are the message; the point size is ours (D-137).
        for (final warning in plan.warnings) ...[
          const SizedBox(height: AppSpacing.sm),
          HintCard(dense: true, icon: Icons.info_outline, text: warning),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                l.planTodaysMeals,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            // To Home, because Home IS the full day — the diary with everything logged against
            // these targets. A second full-day screen inside this tab would be the same rows in a
            // third place.
            TextButton(
              onPressed: () {
                if (Get.isRegistered<NavController>()) {
                  Get.find<NavController>().current = ClientTab.home;
                }
              },
              child: Text(l.planViewFullDay),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final (i, meal) in plan.mealTargets.indexed) ...[
          // The first slot opens ready (the reference's own arrangement): the point of the list is
          // "here is what to eat next", and a screen of uniformly closed rows answers "what are my
          // numbers" instead. One open, the rest a tap away.
          _MealCard(meal: meal, initiallyExpanded: i == 0),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (Get.isRegistered<BillingController>())
          PremiumBanner(billing: Get.find<BillingController>()),
        const SizedBox(height: AppSpacing.xl),
        Text(
          l.planFrom(plan.rulePackVersion),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => OutlinedButton(
            onPressed: controller.generating.value ? null : controller.generate,
            child: Text(l.planRegenerate),
          ),
        ),
      ],
    );
  }
}

/// The day's target, and how much of it today has already used.
///
/// The eaten figures come from the diary Home is holding, never from anything worked out here — a
/// screen that added up its own totals would be a second answer to a question the server answers
/// (CLAUDE.md rule 2). With no diary in memory the card shows the targets alone rather than
/// inventing a zero.
class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.targets, required this.plan});

  final Macros targets;
  final Plan plan;

  static const _ringSize = 88.0;
  static const _artFraction = 0.26;
  static const _artMax = 120.0;

  DiaryDay? get _day {
    if (!Get.isRegistered<HomeController>()) return null;
    final state = Get.find<HomeController>().state.value;
    return state is Ready<DiaryDay> ? state.data : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = _day;
    final eaten = day?.totals;
    final ratio = eaten == null || targets.kcal == 0 ? null : eaten.kcal / targets.kcal;
    final left = eaten == null ? null : targets.kcal - eaten.kcal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasArt = constraints.maxWidth >= AppSizes.heroBreakpoint;
        final art = (constraints.maxWidth * _artFraction).clamp(0.0, _artMax);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The day at a glance on the brand tint — the reference's pale green card, with the
            // ring on its DEFAULT colours this time: brand green on a pale ground is exactly the
            // pairing the widget was measured for (D-135 was the dark header that broke it).
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.cardLarge),
                border: Border.all(color: scheme.secondaryContainer),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.planDailyTarget,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text.rich(
                              TextSpan(
                                text: targets.kcal.round().toString(),
                                style: theme.textTheme.displayLarge,
                                children: [
                                  TextSpan(
                                    text: ' kcal',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(l.planRecommended, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      // Only when there is a diary to measure against (D-43).
                      if (ratio != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ProgressRing(
                          size: _ringSize,
                          strokeWidth: 7,
                          progress: ratio,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(ratio * 100).round()}%',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                              Text(
                                l.planOfGoal,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (hasArt) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ExcludeSemantics(
                          child: Image.asset(
                            AppAssets.planHero,
                            width: art,
                            fit: BoxFit.contain,
                            errorBuilder: (context, _, _) => SizedBox(width: art),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // How the day is going, in the reference's own sentence: consumed on the left,
                  // what remains on the right, the bar between them.
                  if (eaten != null && left != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: (ratio ?? 0).clamp(0.0, 1.0),
                        minHeight: AppSizes.barHeight,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.planKcalConsumed(eaten.kcal.round()),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          // Over-target is said plainly, never as a negative number — and never
                          // in red (docs/05 §6: no judgement chips on a day).
                          left >= 0
                              ? l.planKcalLeft(left.round())
                              : l.planKcalOver((-left).round()),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // The three macros as TILES in a row, each in its own colour — the same three the
            // rings on Home use. IntrinsicHeight for the same reason as the pair below: stretch
            // needs a bounded height, and a ListView gives none.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MacroTile(
                      icon: Icons.egg_alt_outlined,
                      color: AppColors.macroProtein,
                      label: l.homeProtein,
                      eaten: eaten?.proteinG,
                      target: targets.proteinG,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MacroTile(
                      icon: Icons.grain,
                      color: AppColors.macroCarb,
                      label: l.homeCarbs,
                      eaten: eaten?.carbG,
                      target: targets.carbG,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MacroTile(
                      icon: Icons.water_drop_outlined,
                      color: AppColors.macroFat,
                      label: l.homeFat,
                      eaten: eaten?.fatG,
                      target: targets.fatG,
                    ),
                  ),
                ],
              ),
            ),
            if (plan.fibreG != null || plan.waterMl != null) ...[
              const SizedBox(height: AppSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (plan.fibreG != null)
                      Expanded(
                        child: _SmallTarget(
                          icon: Icons.eco_outlined,
                          label: l.planFibre,
                          color: AppColors.success,
                          // Eaten against target once the server sends the day's sum (D-136);
                          // the target alone from an older server, never an invented zero.
                          value: eaten?.fibreG != null
                              ? l.planEatenOf(eaten!.fibreG!.round(), plan.fibreG!.round())
                              : l.planTargetOnly(plan.fibreG!.round()),
                          progress: eaten?.fibreG != null && plan.fibreG! > 0
                              ? eaten!.fibreG! / plan.fibreG!
                              : null,
                        ),
                      ),
                    if (plan.fibreG != null && plan.waterMl != null)
                      const SizedBox(width: AppSpacing.sm),
                    if (plan.waterMl != null)
                      Expanded(
                        child: _SmallTarget(
                          icon: Icons.local_drink_outlined,
                          label: l.planWater,
                          color: AppColors.info,
                          value: l.planWaterOf(day?.waterLoggedMl ?? 0, plan.waterMl!.round()),
                          progress: plan.waterMl == 0
                              ? null
                              : (day?.waterLoggedMl ?? 0) / plan.waterMl!,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One macro as a tile: its colour, what today holds of it, and how far along that is.
class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.eaten,
    required this.target,
  });

  final IconData icon;
  final Color color;
  final String label;
  final double? eaten;
  final double target;

  static const _disc = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = target == 0 || eaten == null ? null : (eaten! / target * 100).round();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: scheme.outline),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: _disc,
                  width: _disc,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: AppSpacing.lg, color: color),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            eaten == null ? '${target.round()} g' : '${eaten!.round()} / ${target.round()} g',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: eaten == null || target == 0 ? 0 : (eaten! / target).clamp(0.0, 1.0),
              minHeight: AppSizes.barHeight * 0.6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.18),
            ),
          ),
          if (pct != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(child: Text('$pct%', style: theme.textTheme.bodySmall)),
          ],
        ],
      ),
    );
  }
}

/// Fibre and water: smaller than a macro because neither is a number to hit exactly.
class _SmallTarget extends StatelessWidget {
  const _SmallTarget({
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final double? progress;

  /// The tile's own colour — the reference draws fibre green and water blue. Null keeps the theme.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      // A tint, not an outlined box: these are footnotes to the macros above them, and a border
      // gave each footnote more visual weight than the rows it footnotes (D-135).
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: AppSpacing.lg, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: AppSizes.barHeight * 0.75,
                color: color,
                backgroundColor: color?.withValues(alpha: 0.18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, this.initiallyExpanded = false});

  final MealTarget meal;

  /// The first slot of the day opens ready; the rest are a tap away.
  final bool initiallyExpanded;

  /// Decoration; the row is not tappable on the disc alone.
  static const _disc = 40.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _slotLabel(l, meal.slot);
    final c = Get.find<PlanController>();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Obx(() {
          // Per slot (D-85): one list under every meal was the same foods four times over.
          final options = c.options[meal.slot] ?? const <FoodOption>[];

          return Theme(
            // The default divider makes an ExpansionTile inside a card read as a second card.
            data: theme.copyWith(dividerColor: Colors.transparent),
            // Its own Material: an ExpansionTile is a ListTile underneath, and a ListTile inside
            // the card's DecoratedBox asserts that its ink splash will be invisible.
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                initiallyExpanded: initiallyExpanded,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                // ONE row collapsed: the slot, its share, and what it costs. The macros and the
                // food strip were stacked under it whether or not anyone had opened the card, and
                // four cards of that is a screen of things nobody asked to see (D-133).
                title: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        height: _disc,
                        width: _disc,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _slotIcon(meal.slot),
                          size: AppSpacing.xl,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            // One fact per line — the suggestion count wrapped this once (D-135).
                            l.planShareOfDay((meal.pct * 100).round()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          // The macros in their own colours, the reference's third line.
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'P ${meal.proteinG.round()} g',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.macroProtein,
                                  ),
                                ),
                                TextSpan(text: ' · ', style: theme.textTheme.bodySmall),
                                TextSpan(
                                  text: 'C ${meal.carbG.round()} g',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.macroCarb,
                                  ),
                                ),
                                TextSpan(text: ' · ', style: theme.textTheme.bodySmall),
                                TextSpan(
                                  text: 'F ${meal.fatG.round()} g',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.macroFat,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${meal.kcal.round()} kcal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    // The first suggested dish's photograph — the reference puts a plate on every
                    // row, and a plate the user can actually be offered beats a stock one.
                    if (options.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: FoodImage(
                          url: options.first.imageUrl,
                          attribution: options.first.imageAttribution,
                          size: AppSizes.ringSmall,
                        ),
                      ),
                    ],
                  ],
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.planSuggestedCount(options.length),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _OptionStrip(options: options, slot: meal.slot, slotLabel: label),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Time of day, not food: a sunrise for the start of it, a moon for the end. Decoration —
  /// excluded from semantics — and the word beside it carries the meaning (rule 4).
  static IconData _slotIcon(String slot) => switch (slot) {
    'breakfast' => Icons.wb_twilight,
    'mid_morning' => Icons.local_cafe_outlined,
    'lunch' => Icons.wb_sunny_outlined,
    'snack' => Icons.bakery_dining_outlined,
    'evening' => Icons.wb_incandescent_outlined,
    'dinner' => Icons.nightlight_outlined,
    _ => Icons.bedtime_outlined,
  };

  /// CLAUDE.md rule 4: a slot is an enum on the wire and l10n on screen.
  String _slotLabel(AppLocalizations l, String slot) => switch (slot) {
    'breakfast' => l.slotBreakfast,
    'mid_morning' => l.slotMidMorning,
    'lunch' => l.slotLunch,
    'snack' => l.slotSnack,
    'evening' => l.slotEvening,
    'dinner' => l.slotDinner,
    _ => l.slotBedtime,
  };
}

/// The foods a user may choose for one slot (D-82), shown when the card is open.
///
/// Tapping logs ONE default household measure — "1 katori" — because that is the smallest honest
/// unit the food carries. It is not a portion recommendation: the entry appears in the diary where
/// the amount can be changed or removed, and nothing here computes how much anyone should eat.
class _OptionStrip extends StatelessWidget {
  const _OptionStrip({required this.options, required this.slot, required this.slotLabel});

  final List<FoodOption> options;
  final String slot;
  final String slotLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (options.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(l.planOptionsEmpty, style: theme.textTheme.bodySmall),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.planOptionsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        // A horizontal strip: eleven meal cards each stacking a dozen rows made the tab a wall of
        // text, and a food is chosen by looking at it rather than by reading a list.
        SizedBox(
          height: _OptionCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) =>
                _OptionCard(option: options[i], slot: slot, slotLabel: slotLabel),
          ),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, required this.slot, required this.slotLabel});

  final FoodOption option;
  final String slot;
  final String slotLabel;

  /// Wide enough for two Devanagari words, narrow enough that a second card peeks in and says the
  /// strip scrolls.
  static const width = 148.0;

  /// Landscape, not square: a square picture plus two lines of name and a measure overflowed the
  /// card by 8 px, and food photographs are wider than they are tall anyway.
  static const _imageHeight = 104.0;
  static const height = 188.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final measure = option.measureLabel;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => _log(context, l),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                FoodImage(
                  url: option.imageUrl,
                  attribution: option.imageAttribution,
                  size: width,
                  height: _imageHeight,
                ),
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: CircleAvatar(
                    radius: AppSpacing.md,
                    backgroundColor: theme.colorScheme.primary,
                    child: Icon(Icons.add, size: AppSpacing.lg, color: theme.colorScheme.onPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Expanded, not a fixed block: at 200 % font scale a hardcoded height is an overflow
            // waiting to happen, and the text ellipsises into whatever room is left instead.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      option.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (measure != null)
                    Flexible(
                      child: Text(
                        '${option.kcalPerMeasure} kcal · 1 $measure',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _log(BuildContext context, AppLocalizations l) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Get.find<DiaryRepository>().logFood(
      slot: slot,
      foodId: option.id,
      measure: option.measureLabel,
      // One measure, or 100 g when the food has none — the fallback the log sheet itself uses.
      measureCount: option.measureLabel == null ? null : 1,
      quantityG: option.measureLabel == null ? 100 : null,
    );

    // Rule 7: the server's own words on failure, never ours.
    final message = result.fold((f) => f.userMessage, (_) => l.planOptionLogged(slotLabel));
    messenger.showSnackBar(SnackBar(content: Text(message)));

    // Home shows the day; it has just changed.
    if (Get.isRegistered<HomeController>()) await Get.find<HomeController>().load();
  }
}
