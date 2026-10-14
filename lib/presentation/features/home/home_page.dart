import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/animated_count.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/day_dot.dart';
import 'package:health_pro/core/widgets/food_image.dart';
import 'package:health_pro/core/widgets/press_scale.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/store_gateway.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/premium_widgets.dart';
import 'package:health_pro/presentation/features/gym/gym_today_card.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/home/home_health_sync.dart';
import 'package:health_pro/presentation/features/home/home_skeleton.dart';
import 'package:health_pro/presentation/features/home/widgets/announcements_strip.dart';
import 'package:health_pro/presentation/features/home/widgets/home_activity_cards.dart';
import 'package:health_pro/presentation/features/home/widgets/home_day_selector.dart';
import 'package:health_pro/presentation/features/home/widgets/home_header.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/log_sheet.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:intl/intl.dart';

/// tabHome. docs/14 §1, four states per CLAUDE.md rule 6.
///
/// docs/05 §6 shapes the tone: no red for going over, no "you failed today". A number over target
/// is stated, not scored.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = Get.put(
      HomeController(
        diary: Get.find<DiaryRepository>(),
        plans: Get.find<PlanRepository>(),
        // Resolved rather than required: tests that are not about syncing register none, and Home
        // must work without it — activity is something the day may carry, never something it
        // depends on.
        syncHealth: Get.isRegistered<SyncHealth>() ? Get.find<SyncHealth>() : null,
        reminders: Get.isRegistered<RefreshReminders>() ? Get.find<RefreshReminders>() : null,
      ),
      permanent: true,
    );

    final billing = Get.isRegistered<BillingRepository>()
        ? Get.put(
            BillingController(
              billing: Get.find<BillingRepository>(),
              // Absent in tests and in any build with no SDK linked; the controller then says
              // checkout cannot be opened rather than leaving a dead button.
              gateway: Get.isRegistered<PaymentGateway>() ? Get.find<PaymentGateway>() : null,
              store: Get.isRegistered<StoreGateway>() ? Get.find<StoreGateway>() : null,
            ),
            permanent: true,
          )
        : null;

    return Stack(
      children: [
        // Draws nothing; puts up the once-per-account connect sheet when Home asks for it.
        HomeHealthPrompt(controller: c),
        TabScaffold(
          title: homeGreeting(l10n, DateTime.now()),
          titleIcon: Icons.waving_hand,
          subtitle: l10n.homeTagline,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (billing != null) Flexible(child: PremiumPill(billing: billing)),
              const HomeNotificationBell(),
            ],
          ),
          child: Obx(
            () => switch (c.state.value) {
              Loading<DiaryDay>() => const HomeSkeleton(),
              Empty<DiaryDay>() => EmptyView(title: l10n.homeEmptyTitle, body: l10n.homeEmptyBody),
              Failed<DiaryDay>(:final failure) => FailedView(
                failure: failure,
                onRetry: c.load,
                retryLabel: l10n.accountRetry,
              ),
              Ready<DiaryDay>(:final data) => _Today(day: data, controller: c),
            },
          ),
        ),
      ],
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.day, required this.controller});

  final DiaryDay day;
  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = day.targets;

    return ListView(
      // No top inset: the day bar sits directly under the heading (the header's own padding is
      // the whole gap).
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl),
      children: [
        // Which day this is, and the way to yesterday. Without it the diary is a display of the
        // last few hours: everything logged before 04:00 this morning was unreachable (D-128).
        HomeDaySelector(controller: controller),
        const SizedBox(height: AppSpacing.sm),
        // Admin panel plan, Phase C: the team's news. Draws nothing when there is none.
        const AnnouncementsStrip(),
        // D-57: the hero is the screen, not a card on it — the summary cards on the left, the
        // walker on his stage to the right, both painted in their own layers.
        _Hero(day: day, controller: controller),
        // Full width, under the hero, as the reference stacks them: water, then steps.
        if (day.waterTargetMl != null) ...[
          const SizedBox(height: AppSpacing.md),
          HomeWaterCard(day: day),
        ],
        const SizedBox(height: AppSpacing.md),
        HomeStepsCard(day: day, controller: controller),
        if (targets == null) ...[
          const SizedBox(height: AppSpacing.lg),
          Obx(
            () => Column(
              children: [
                if (controller.planError.value != null) ...[
                  Text(
                    // docs/05 §7 referral copy arrives here when a gate blocks the plan.
                    controller.planError.value!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                FilledButton(
                  onPressed: controller.generating.value ? null : controller.generatePlan,
                  child: Text(l.homeCreatePlan),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // No spacer here: the water card's upward overlap already leaves its translate's worth of
        // space, and the heading's own button height does the rest.
        if (targets != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l.homeMacros,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (Get.isRegistered<NavController>()) {
                    Get.find<NavController>().current = ClientTab.plan;
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.homeDetails),
                    const Icon(Icons.chevron_right, size: AppSpacing.lg),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _NutrientTiles(day: day),
          // `sm`, not `lg`: the row now carries `sm` of shadow room of its own, and the gap to the
          // next heading is the two together. The shadow used to paint into this spacer.
          const SizedBox(height: AppSpacing.sm),
        ],
        // D-241: the Gym's door on Home — today's routine and a one-tap Start. It carries its own
        // gap, so a Home with no Gym registered is laid out exactly as before.
        const GymTodayCard(),
        // What was EATEN, by slot (D-140) — the plan's prescription lives on the Plan tab; this
        // is the diary's answer to it. Each slot heads its entries with the slot's own sums.
        Text(
          l.planTodaysMeals,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (day.isEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l.homeNothingLogged, style: theme.textTheme.bodyMedium),
        ] else
          for (final slot in _slotOrder)
            if (day.entries.any((e) => e.slot == slot)) ...[
              _SlotSummary(
                slot: slot,
                label: _slotLabel(l, slot),
                entries: day.entries.where((e) => e.slot == slot).toList(),
                targetKcal: targets?.kcal,
              ),
              for (final entry in day.entries.where((e) => e.slot == slot)) _EntryRow(entry: entry),
            ],
        const SizedBox(height: AppSpacing.sm),
        _StreakCard(controller: controller, day: day),
        _TargetsHitCard(day: day),
      ],
    );
  }
}

/// The hero (D-55, rebuilt D-138): the day's summary cards on the left, the walker on his stage
/// to the right. Both the walker and the stage are painted in their own layers (D-60, D-63) —
/// this column only has to keep the words out from under him.
class _Hero extends StatelessWidget {
  const _Hero({required this.day, required this.controller});

  final DiaryDay day;
  final HomeController controller;

  /// The words' share of the hero; the rest is the walker's.
  static const _textFraction = 0.56;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < AppSizes.heroBreakpoint ||
            textScale >= AppSizes.heroStackTextScale;

        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalorieSummaryCard(day: day),
            // Layered over the green card's foot, the reference's own overlap: the plan's target,
            // what was eaten, what is left. Only with a plan — never a target of nought.
            if (day.targets != null)
              Transform.translate(
                offset: const Offset(0, -AppSpacing.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: HomeCalorieTargets(day: day),
                ),
              ),
          ],
        );

        if (stacked) {
          // At 200 % text the column takes the full width and the walker keeps the space below —
          // rule 12: the layout gives way, not the text.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              column,
            ],
          );
        }

        // Natural height, no reservation (D-140): the old minHeight held a screen of cream open
        // under the cards, and it existed to keep content out from under a walker who now sits
        // BEHIND the page — the cards scroll over him, which is the point.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SizedBox(width: constraints.maxWidth * _textFraction, child: column)],
        );
      },
    );
  }
}

/// Energy in and energy out, on the brand green (D-138).
///
/// "Supplied" is the diary's sum; "burned" is the em dash until the user or their watch says
/// otherwise — a zero would claim "you burned nothing" where the truth is "you have not told us"
/// (D-50, D-80). The ring carries its own colours: the theme's default paints this exact green
/// and would vanish here (D-135).
class _CalorieSummaryCard extends StatelessWidget {
  const _CalorieSummaryCard({required this.day});

  final DiaryDay day;

  // 72: between D-157's 64 and the reference's fifth of the screen — at 80 the card dwarfed the
  // rest of Home on a 360 dp phone. `_ringInner` is the side of the square inscribed in the
  // ring's inner circle — the box the number must actually fit.
  static const _ring = 72.0;
  static const _ringInner = 40.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // D-246 (amends D-242): one figure for energy out. The device's own number and the day's
    // workouts are added together here rather than shown as two rivals — with the split named
    // under the card, because the workout half is an estimate and the device half is measured.
    final device = day.energyBurnedKcal;
    final workout = day.workoutKcal;
    final burned = device == null && workout == null ? null : (device ?? 0) + (workout ?? 0);
    final target = day.targets?.kcal;

    return Container(
      // The extra foot is the white targets panel's overlap (`_Hero`): without it the panel sat
      // on "burned" and cut it in half.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        // Lit from the top-left, the reference's own card — flat primary read as a slab.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.local_fire_department,
                  size: AppSpacing.lg,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l.homeCalorieSummary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.darkOnSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      // The reference sets the figure huge and the unit small beside it — one
                      // size for both read as a label, not a headline.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedCount(
                            value: day.totals.kcal,
                            semanticsLabel: '${day.totals.kcal.round()} kcal',
                            // The app's largest size (26). `displaySmall` is not in the app's
                            // theme and fell back to Material's 36 sp.
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: AppColors.darkOnSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: AppSpacing.xs,
                              bottom: AppSpacing.xs,
                            ),
                            child: Text(
                              'kcal',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.darkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      l.homeSupplied,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.darkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The seam between energy in and energy out, straight off the reference card.
              Container(
                width: 1,
                height: _ring * 0.8,
                color: AppColors.darkMuted.withValues(alpha: 0.35),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                children: [
                  ProgressRing(
                    size: _ring,
                    strokeWidth: 6,
                    // Division on two server figures, never a target the app invented (rule 2):
                    // with no plan or nothing reported there is no fill, only the track.
                    progress: burned == null || target == null || target == 0
                        ? null
                        : burned / target,
                    color: AppColors.accentBright,
                    trackColor: AppColors.accentBright.withValues(alpha: 0.25),
                    // Inscribed in the ring's INNER circle (D-157): fitted to the full diameter,
                    // "4,000" ran stroke to stroke. The number alone lives inside — the unit is
                    // already on the figure to the left, and "burned" captions it below.
                    child: SizedBox(
                      width: _ringInner,
                      height: _ringInner,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: burned == null
                            ? Text(
                                '—',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkOnSurface,
                                ),
                              )
                            // The figure over its unit, as the reference sets it in the ring.
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    NumberFormat.decimalPattern().format(burned),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.darkOnSurface,
                                    ),
                                  ),
                                  Text(
                                    'kcal',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.darkMuted,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l.homeBurned,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.darkMuted),
                  ),
                ],
              ),
            ],
          ),
          // What the figure above is made of, when part of it was estimated rather than measured.
          if (workout != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.fitness_center,
                    size: AppSpacing.lg,
                    color: AppColors.darkMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    l.homeWorkoutKcal(workout),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.darkOnSurface),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The nutrients as a two-column grid (D-138): protein, carbs, fat — the ring palette Home has
/// always used — and fibre when the day carries it (D-136). A grid rather than a sideways-scrolling
/// row, which cut the fourth tile off at the screen's edge. One column at large text (rule 12).
class _NutrientTiles extends StatelessWidget {
  const _NutrientTiles({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final targets = day.targets!;

    final tiles = [
      (
        Icons.egg_alt_outlined,
        AppColors.macroProtein,
        l.homeProtein,
        day.totals.proteinG,
        targets.proteinG,
      ),
      (Icons.grain, AppColors.macroCarb, l.homeCarbs, day.totals.carbG, targets.carbG),
      (Icons.water_drop_outlined, AppColors.macroFat, l.homeFat, day.totals.fatG, targets.fatG),
      if (day.totals.fibreG != null && targets.fibreG != null)
        (Icons.eco_outlined, AppColors.success, l.planFibre, day.totals.fibreG!, targets.fibreG!),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale
            ? 1
            : 2;
        final width = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;

        return Padding(
          // Room for the tiles' drop shadow, which paints below their own box.
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (icon, color, label, eaten, target) in tiles)
                SizedBox(
                  width: width,
                  child: _NutrientTile(
                    icon: icon,
                    color: color,
                    label: label,
                    eaten: eaten,
                    target: target,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One nutrient across its tile: the coloured disc, the name over eaten-against-target, and the
/// ring with its percentage on the right.
class _NutrientTile extends StatelessWidget {
  const _NutrientTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.eaten,
    required this.target,
  });

  final IconData icon;
  final Color color;
  final String label;
  final double eaten;
  final double target;

  static const _disc = 36.0;
  static const _ring = 44.0;
  static const _ringStroke = 5.0;
  static const _trackAlpha = 0.18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = target == 0 ? null : (eaten / target * 100).round();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        // No border — the reference tiles sit on shadow alone.
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: _disc,
                  width: _disc,
                  // Solid disc, white glyph — the reference's chip.
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, size: AppSpacing.lg, color: AppColors.lightSurface),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${eaten.round()} / ${target.round()} g',
                        // The figure in ink, not in the macro colour: the disc and the ring carry the
                        // identity, the number stays a number.
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ProgressRing(
                size: _ring,
                strokeWidth: _ringStroke,
                progress: target == 0 ? null : eaten / target,
                color: color,
                trackColor: color.withValues(alpha: _trackAlpha),
                child: pct == null
                    ? null
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Text(
                            '$pct%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // The reference's bar under each macro: the same ratio as the ring, clamped at full.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: target == 0 ? 0 : (eaten / target).clamp(0.0, 1.0),
              minHeight: AppSizes.barHeight * _barScale,
              color: color,
              backgroundColor: color.withValues(alpha: _trackAlpha),
            ),
          ),
        ],
      ),
    );
  }

  static const _barScale = 0.75;
}

/// Consecutive days with anything logged, and the week as NEUTRAL dots (D-138).
///
/// Walking the edge docs/05 §6 draws: streaks on WEIGHT are banned outright; this one counts
/// LOGGING, an unlogged day is a hollow circle — never a red mark, never the word "missed" — and
/// at zero the card simply is not there, because "0 day streak" is the failure banner the tone
/// rules exist to prevent.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.controller, required this.day});

  final HomeController controller;
  final DiaryDay day;

  static const _days = 7;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Obx(() {
      // Touched so the Obx subscribes; the computation reads it again inside.
      final _ = controller.loggedDates.length;
      final streak = controller.streakEndingAt(day.diaryDate);
      if (streak == 0) return const SizedBox.shrink();

      final today = DateTime.tryParse(day.diaryDate);
      if (today == null) return const SizedBox.shrink();

      final logged = {...controller.loggedDates};
      if (day.entries.isNotEmpty) logged.add(day.diaryDate);

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: scheme.secondaryContainer),
          ),
          // The reference puts the words and the week on ONE line — text left, dots right. A Wrap
          // rather than a Row so 200 % text drops the dots to their own line instead of clipping.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.local_fire_department,
                      size: AppSpacing.xl,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.homeStreakTitle(streak),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(l.homeStreakBody, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = _days - 1; i >= 0; i--) ...[
                    DayDot(
                      date: today.subtract(Duration(days: i)),
                      isLogged: logged.contains(
                        HomeController.isoDate(today.subtract(Duration(days: i))),
                      ),
                      isToday: i == 0,
                      locale: locale,
                    ),
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The day, met (D-138). Every ratio the server gave is at or past its goal — said once, warmly,
/// and never inverted: there is no card for the other days, because docs/05 §6 bans the failure
/// banner, not the celebration.
class _TargetsHitCard extends StatelessWidget {
  const _TargetsHitCard({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final targets = day.targets;
    if (targets == null) return const SizedBox.shrink();

    // ponytail: "met" is ratio >= 1 on the four figures the server sent. A band ("within 5 %")
    // would be the app inventing a threshold — rule 2 territory — so overshoot still counts as met.
    bool met(double eaten, double target) => target > 0 && eaten >= target;
    final hit =
        met(day.totals.kcal, targets.kcal) &&
        met(day.totals.proteinG, targets.proteinG) &&
        met(day.totals.carbG, targets.carbG) &&
        met(day.totals.fatG, targets.fatG);
    if (!hit) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: scheme.secondaryContainer),
        ),
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.celebration_outlined,
                size: AppSpacing.xl,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.homeTargetsHitTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(l.homeTargetsHitBody, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                if (Get.isRegistered<NavController>()) {
                  Get.find<NavController>().current = ClientTab.progress;
                }
              },
              child: Text(l.homeSeeInsights),
            ),
          ],
        ),
      ),
    );
  }
}

/// Time of day, not food (rule 4): shared with the Plan tab's cards.
IconData _slotIcon(String slot) => switch (slot) {
  'breakfast' => Icons.wb_twilight,
  'mid_morning' => Icons.local_cafe_outlined,
  'lunch' => Icons.wb_sunny_outlined,
  'snack' => Icons.bakery_dining_outlined,
  'evening' => Icons.wb_incandescent_outlined,
  'dinner' => Icons.nightlight_outlined,
  _ => Icons.bedtime_outlined,
};

/// The reference mock gives each meal its own hue — amber dawn, green noon, purple snack, blue
/// night. Identity, never judgement (docs/05 §6): a slot keeps its colour whatever was eaten.
Color _slotColor(String slot) => switch (slot) {
  'breakfast' => AppColors.warning,
  'mid_morning' => AppColors.warmCoral,
  'lunch' => AppColors.success,
  'snack' => AppColors.macroCarb,
  'evening' => AppColors.warmCoral,
  'dinner' => AppColors.info,
  _ => AppColors.macroFat,
};

/// docs/09 §5 slot order — the order a day runs, not alphabetical.
const _slotOrder = ['breakfast', 'mid_morning', 'lunch', 'snack', 'evening', 'dinner', 'bedtime'];

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

/// One slot of the diary as the reference's meal card: the slot's tinted disc, its name, its
/// share of the day, the macro line — and on the right the kcal sum over a share bar (D-140).
/// The entries still follow underneath; a photo per meal waits on the server sending one.
class _SlotSummary extends StatelessWidget {
  const _SlotSummary({
    required this.slot,
    required this.label,
    required this.entries,
    this.targetKcal,
  });

  final String slot;
  final String label;
  final List<LogEntry> entries;

  /// The day's kcal target. The share line and the bar exist only when the server set one —
  /// a share of an invented target would be rule-2 territory.
  final double? targetKcal;

  static const _disc = 36.0;
  static const _bar = 72.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    double sum(double Function(LogEntry) of) => entries.fold(0, (acc, e) => acc + of(e));

    final kcal = sum((e) => e.kcal);
    final target = targetKcal;
    final share = target == null || target == 0 ? null : kcal / target;
    final color = _slotColor(slot);

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: _disc,
              width: _disc,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_slotIcon(slot), size: AppSpacing.lg, color: color),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (share != null)
                  Text(l.homeSlotShare((share * 100).round()), style: theme.textTheme.bodySmall),
                // What this meal actually delivered, in the macro colours the whole app uses.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'P ${sum((e) => e.proteinG).round()} g',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.macroProtein),
                      ),
                      TextSpan(text: ' · ', style: theme.textTheme.bodySmall),
                      TextSpan(
                        text: 'C ${sum((e) => e.carbG).round()} g',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.macroCarb),
                      ),
                      TextSpan(text: ' · ', style: theme.textTheme.bodySmall),
                      TextSpan(
                        text: 'F ${sum((e) => e.fatG).round()} g',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.macroFat),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${kcal.round()} kcal',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (share != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: _bar,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          // The BAR clamps, the number does not, and neither is ever red — the
                          // water card's own rule (docs/05 §6).
                          value: share.clamp(0.0, 1.0),
                          minHeight: AppSizes.barHeight * 0.75,
                          color: AppColors.success,
                          backgroundColor: AppColors.success.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${(share * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          ExcludeSemantics(
            child: Icon(Icons.chevron_right, size: AppSpacing.lg, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      // The chevron goes somewhere real: the card opens the log sheet, the diary's way to add to
      // this day.
      child: PressScale(
        onTap: () => LogSheet.show(context),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        child: card,
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final LogEntry entry;

  static const _photo = 52.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grams = entry.measureLabel == null
        ? '${entry.quantityG.round()} g'
        : '${entry.measureLabel} · ${entry.quantityG.round()} g';
    // D-240: a scanned plate's numbers are a model's estimate, and the row says so every time.
    final amount = entry.estimated ? '$grams · ${l.logEstimated}' : grams;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            // What was eaten, not only its name (docs/21 §6). A custom entry has no photo and gets
            // the same-sized placeholder, so the rows stay aligned (D-83).
            FoodImage(url: entry.imageUrl, attribution: entry.imageAttribution, size: _photo),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: theme.textTheme.bodyLarge),
                  Text(
                    amount,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.kcal.round()} kcal',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
