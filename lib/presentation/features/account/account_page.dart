import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/section_header.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/account/edit_sheets.dart';
import 'package:health_pro/presentation/features/account/profile_frame.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:health_pro/presentation/shell/walking_man.dart';
import 'package:intl/intl.dart';

/// tabYou tab. docs/14 §1. All four states per CLAUDE.md rule 6.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = Get.put(
      AccountController(
        profiles: Get.find<ProfileRepository>(),
        plans: Get.find<PlanRepository>(),
        diary: Get.isRegistered<DiaryRepository>() ? Get.find<DiaryRepository>() : null,
        measurements: Get.isRegistered<MeasurementsRepository>()
            ? Get.find<MeasurementsRepository>()
            : null,
      ),
      permanent: true,
    );

    // No sheet, no hole (D-152) — the page works exactly like Home: it paints no background of
    // its own, so the walker and his stage art show through wherever the hero leaves room, and
    // the cards pass OVER him the moment the list scrolls. The mock's "blob" was never a cut-out;
    // it is the stage art itself. The LayoutBuilder's box is the shell's body: exactly the
    // coordinate space `WalkingMan.boundsIn` answers in (D-63).
    return LayoutBuilder(
      builder: (context, body) {
        final man = WalkingMan.boundsAt(body.biggest, ClientTab.you);
        return _content(context, c, l10n, man.bottom, body.maxHeight);
      },
    );
  }

  Widget _content(
    BuildContext context,
    AccountController c,
    AppLocalizations l10n,
    double walkerBottom,
    double bodyHeight,
  ) {
    return TabScaffold(
      // The page heads itself "Profile" (the mock's word); the TAB stays "You" — docs/14 §1 owns
      // the shell's names, not the page's heading.
      title: l10n.accountTitle,
      subtitle: l10n.accountSubtitle,
      // The sign-out button lives INSIDE the list now (D-146): pinned below it, its height was
      // silently counted into `_Details`' headerHeight and the frame band came up short — the
      // stat strip printed into the walker's circle.
      child: Obx(
        () => switch (c.state.value) {
          Loading<ProfileView>() => const LoadingView(),
          Empty<ProfileView>() => EmptyView(
            title: l10n.accountEmptyTitle,
            body: l10n.accountEmptyBody,
          ),
          Failed<ProfileView>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
            retryLabel: l10n.accountRetry,
          ),
          Ready<ProfileView>(:final data) => _Details(
            profile: data,
            controller: c,
            walkerBottom: walkerBottom,
            bodyHeight: bodyHeight,
            // The sheet returns true only after the server accepted the change, so the
            // reload reflects what was actually stored, not what was typed.
            onEdited: c.load,
          ),
        },
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.profile,
    required this.controller,
    required this.onEdited,
    required this.walkerBottom,
    required this.bodyHeight,
  });

  final ProfileView profile;
  final AccountController controller;
  final Future<void> Function() onEdited;

  /// Bottom of the walker's box, in the shell BODY's coordinates. The list lives further down the
  /// page than that, so it is converted below rather than used directly.
  final double walkerBottom;
  final double bodyHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Every enum goes back through the label extensions — CLAUDE.md rule 4, never a raw wire value.
    final sex = enumFromWire(SexAtBirth.values, profile.sexAtBirth, (e) => e.wire);
    final goal = enumFromWire(Goal.values, profile.goal, (e) => e.wire);
    final activity = enumFromWire(ActivityLevel.values, profile.activity, (e) => e.wire);
    final diet = enumFromWire(FoodPreference.values, profile.foodPreference, (e) => e.wire);

    final conditions = profile.conditions
        .map((w) => enumFromWire(Condition.values, w, (e) => e.wire)?.label(l))
        .whereType<String>()
        .toList();
    final allergies = profile.allergies
        .map((w) => enumFromWire(FoodAllergy.values, w, (e) => e.wire)?.label(l))
        .whereType<String>()
        .toList();

    return LayoutBuilder(
      builder: (context, list) {
        // The list is not the page: the tab's title sits above it. Everything the hole is measured
        // in is body coordinates, so convert once, here, rather than hard-coding a header height
        // that changes with the font scale.
        final headerHeight = bodyHeight - list.maxHeight;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          children: [
            // The band the walker and his stage occupy, exactly as on Home (D-152). The heading
            // and photo sit in it, to the LEFT of him.
            SizedBox(
              height: (walkerBottom - headerHeight).clamp(AppSizes.profileFrame, bodyHeight),
              // The mock's hero is three corners, not a column (D-151): the LEFT half lays out
              // on its own — avatar row at the top, straight under the subtitle; the stat strip
              // at the foot, beside the stage's lower third — and neither waits for the walker.
              child: LayoutBuilder(
                builder: (context, band) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: AppSpacing.md,
                      width: band.maxWidth * 0.58,
                      child: ProfileFrame(
                        name: profile.name,
                        photoUrl: profile.photoUrl,
                        onPhotoChanged: onEdited,
                      ),
                    ),
                    // Age and height at a glance. "Member since" waits on the server sending
                    // the account's created_at (docs/21 §7).
                    Positioned(
                      left: 0,
                      bottom: AppSpacing.sm,
                      width: band.maxWidth * 0.55,
                      child: _StatStrip(profile: profile),
                    ),
                    // The mock's step pill, hung on the frame's lower edge — only when the
                    // phone reported a count today (D-146).
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Obx(() {
                        final steps = controller.today.value?.steps;
                        if (steps == null) return const SizedBox.shrink();
                        return _StepsChip(steps: steps);
                      }),
                    ),
                  ],
                ),
              ),
            ),
            // Today at a glance (D-144): the day's figures in miniature, with the way to Home.
            // Only when a diary answered — no card of dashes for a day that never loaded.
            Obx(() {
              final day = controller.today.value;
              if (day == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: l.homeSubtitle,
                    actionLabel: l.progressSeeAll,
                    onAction: () {
                      if (Get.isRegistered<NavController>()) {
                        Get.find<NavController>().current = ClientTab.home;
                      }
                    },
                  ),
                  _GlanceCard(day: day),
                ],
              );
            }),
            SectionHeader(title: l.accountDailyGoals),
            Obx(() => _GoalTiles(goals: controller.goals.value, today: controller.today.value)),
            // Body stats (D-144): the latest weight and the server's change sentence. BMI, body
            // fat and muscle mass wait on the server sending them — docs/21 §7.
            Obx(() {
              final history = controller.weight.value;
              final latest = history?.points.lastOrNull;
              if (history == null || latest == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: l.accountBodyStats,
                    actionLabel: l.progressSeeAll,
                    onAction: () {
                      if (Get.isRegistered<NavController>()) {
                        Get.find<NavController>().current = ClientTab.progress;
                      }
                    },
                  ),
                  _BodyStatsCard(history: history, latest: latest),
                ],
              );
            }),
            SectionHeader(
              title: l.accountYourDetails,
              actionLabel: l.accountEdit,
              onAction: () async {
                final changed = await EditSheets.details(context, profile);
                if (changed ?? false) await onEdited();
              },
            ),
            AppCard(
              child: Column(
                children: [
                  // Age and height live in the hero strip now (D-146); repeating them here would
                  // print the same fact twice on one screen.
                  _Row(
                    label: l.fieldWeightKg,
                    value: l.accountWeightValue(profile.weightKg.toStringAsFixed(1)),
                  ),
                  if (sex != null) _Row(label: l.accountSex, value: sex.label(l)),
                  if (goal != null) _Row(label: l.accountGoal, value: goal.label(l)),
                  if (activity != null) _Row(label: l.accountActivity, value: activity.label(l)),
                  if (diet != null) _Row(label: l.accountDiet, value: diet.label(l)),
                ],
              ),
            ),
            SectionHeader(
              title: l.accountHealth,
              actionLabel: l.accountEdit,
              onAction: () async {
                final changed = await EditSheets.health(context, profile);
                if (changed ?? false) await onEdited();
              },
            ),
            AppCard(
              child: Column(
                children: [
                  _Row(
                    label: l.accountConditions,
                    value: conditions.isEmpty ? l.accountNone : conditions.join(', '),
                  ),
                  _Row(
                    label: l.accountAllergies,
                    value: allergies.isEmpty ? l.accountNone : allergies.join(', '),
                  ),
                ],
              ),
            ),
            // Quick actions (D-144): the mock's pills, each going somewhere that exists. No
            // Reminders pill — there are no reminders to manage yet.
            SectionHeader(title: l.accountQuickActions),
            _quickActions(context, l),
            const SizedBox(height: AppSpacing.lg),
            const _SignOutButton(),
            // Clears the docked FAB, which otherwise sits on top of the button.
            const SizedBox(height: AppSpacing.xxl),
          ],
        );
      },
    );
  }

  Widget _quickActions(BuildContext context, AppLocalizations l) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _ActionPill(
          icon: Icons.person_outline,
          label: l.accountEditProfile,
          onTap: () async {
            final changed = await EditSheets.details(context, profile);
            if (changed ?? false) await onEdited();
          },
        ),
        _ActionPill(
          icon: Icons.restaurant_menu_outlined,
          label: l.accountMyPlan,
          onTap: () {
            if (Get.isRegistered<NavController>()) {
              Get.find<NavController>().current = ClientTab.plan;
            }
          },
        ),
        _ActionPill(
          icon: Icons.bar_chart,
          label: l.accountReports,
          onTap: () {
            if (Get.isRegistered<NavController>()) {
              Get.find<NavController>().current = ClientTab.progress;
            }
          },
        ),
      ],
    );
  }
}

/// The mock's goal rows (D-144, restyling D-61's saturated bands): a white row per target, the
/// macro's colour on its disc and its progress bar. Calories takes the brand green — it is the
/// day's total, not a macro, and giving it a fourth hue would imply a fourth ring. When today's
/// diary is present the bar shows eaten-against-goal; without it the row states the goal alone.
///
/// Null goals means no plan, which is said in words instead of shown as four zeroes (D-43).
/// There is deliberately no "Edit goals" and no "Add more goals": targets are the SERVER's
/// answer to the profile (rule 2) — the way to change them is to change the profile or the plan.
class _GoalTiles extends StatelessWidget {
  const _GoalTiles({required this.goals, this.today});

  final Macros? goals;
  final DiaryDay? today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final g = goals;
    if (g == null) {
      return Text(l.accountNoGoalsYet, style: theme.textTheme.bodyMedium);
    }

    double? ratio(double? eaten, double target) =>
        eaten == null || target <= 0 ? null : eaten / target;
    final waterTarget = today?.waterTargetMl;

    return Column(
      children: [
        _GoalRow(
          icon: Icons.local_fire_department_outlined,
          color: theme.colorScheme.primary,
          label: l.accountGoalCalories,
          value: '${g.kcal.round()}',
          progress: ratio(today?.totals.kcal, g.kcal),
        ),
        _GoalRow(
          icon: Icons.egg_alt_outlined,
          color: AppColors.macroProtein,
          label: l.homeProtein,
          value: '${g.proteinG.round()} g',
          progress: ratio(today?.totals.proteinG, g.proteinG),
        ),
        _GoalRow(
          icon: Icons.grain_outlined,
          color: AppColors.macroCarb,
          label: l.homeCarbs,
          value: '${g.carbG.round()} g',
          progress: ratio(today?.totals.carbG, g.carbG),
        ),
        _GoalRow(
          icon: Icons.water_drop_outlined,
          color: AppColors.macroFat,
          label: l.homeFat,
          value: '${g.fatG.round()} g',
          progress: ratio(today?.totals.fatG, g.fatG),
        ),
        if (waterTarget != null && waterTarget > 0)
          _GoalRow(
            icon: Icons.local_drink_outlined,
            color: AppColors.info,
            label: l.homeWater,
            value: '${(waterTarget / 1000).toStringAsFixed(1)} L',
            progress: ratio((today?.waterLoggedMl ?? 0).toDouble(), waterTarget.toDouble()),
          ),
      ],
    );
  }
}

/// One goal row: the macro's solid disc and white glyph, the label, today's bar in the same hue
/// (clamped — the number never is, docs/05 §6), the target on the right.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.progress,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  /// Today's eaten-against-goal; null draws no bar rather than a bar of nothing.
  final double? progress;

  static const _disc = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        // Vertical sm, not md (D-153): five of these stack, and the 48 pt floor above already
        // keeps a sparse row tall enough.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                height: _disc,
                width: _disc,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(icon, size: AppSpacing.lg, color: AppColors.lightSurface),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: AppSizes.barHeight * 0.75,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today in miniature (D-144): calories against the goal with the ring, the three macros and
/// water as small bars, and the phone's step count when the day carries one.
class _GlanceCard extends StatelessWidget {
  const _GlanceCard({required this.day});

  final DiaryDay day;

  static const _ring = 64.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = day.targets;
    final kcalTarget = targets?.kcal;
    final tiles = <(String, String, double?, Color)>[
      if (targets != null) ...[
        (
          l.homeProtein,
          '${day.totals.proteinG.round()} / ${targets.proteinG.round()} g',
          targets.proteinG <= 0 ? null : day.totals.proteinG / targets.proteinG,
          AppColors.macroProtein,
        ),
        (
          l.homeCarbs,
          '${day.totals.carbG.round()} / ${targets.carbG.round()} g',
          targets.carbG <= 0 ? null : day.totals.carbG / targets.carbG,
          AppColors.macroCarb,
        ),
        (
          l.homeFat,
          '${day.totals.fatG.round()} / ${targets.fatG.round()} g',
          targets.fatG <= 0 ? null : day.totals.fatG / targets.fatG,
          AppColors.macroFat,
        ),
      ],
      if (day.waterTargetMl != null && day.waterTargetMl! > 0)
        (
          l.homeWater,
          '${((day.waterLoggedMl ?? 0) / 1000).toStringAsFixed(1)} / '
              '${(day.waterTargetMl! / 1000).toStringAsFixed(1)} L',
          (day.waterLoggedMl ?? 0) / day.waterTargetMl!,
          AppColors.info,
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
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
                        Text(l.accountGoalCalories, style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        kcalTarget == null
                            ? '${day.totals.kcal.round()} kcal'
                            : '${day.totals.kcal.round()} / ${kcalTarget.round()} kcal',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ProgressRing(
                size: _ring,
                strokeWidth: 6,
                progress: kcalTarget == null || kcalTarget <= 0
                    ? null
                    : day.totals.kcal / kcalTarget,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kcalTarget == null || kcalTarget <= 0
                            ? '—'
                            : '${(day.totals.kcal / kcalTarget * 100).round()}%',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(l.progressOfGoal, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final perRow = constraints.maxWidth < AppSizes.heroBreakpoint ? 1 : 2;
                final width =
                    (constraints.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (label, value, ratio, color) in tiles)
                      SizedBox(
                        width: width,
                        child: _GlanceTile(
                          label: label,
                          value: value,
                          ratio: ratio,
                          color: color,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The mock's hero strip: a figure with its icon and caption, dividers between (D-146).
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.profile});

  final ProfileView profile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = [
      (Icons.cake_outlined, l.fieldAge, l.accountAgeValue(profile.ageYears)),
      (Icons.height, l.fieldHeightCm, l.accountHeightValue(profile.heightCm)),
    ];

    return Row(
      children: [
        for (final (i, (icon, label, value)) in items.indexed) ...[
          if (i > 0)
            Container(
              width: 1,
              height: AppSpacing.xxl,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              color: scheme.outline,
            ),
          Expanded(
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: AppSpacing.lg, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The white pill at the walker's feet: today's step count, the phone's own figure (D-146).
class _StepsChip extends StatelessWidget {
  const _StepsChip({required this.steps});

  final int steps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = NumberFormat.decimalPattern(locale).format(steps);

    return Semantics(
      label: l.accountStepsToday(formatted),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            boxShadow: AppElevation.raised(theme.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_walk, size: AppSpacing.xl, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatted,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(l.accountStepsCaption, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One small figure in the glance card: label, value, and the bar in the macro's colour. The bar
/// clamps; the number does not (docs/05 §6).
class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String value;
  final double? ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: (ratio ?? 0).clamp(0.0, 1.0),
            minHeight: AppSizes.barHeight * 0.75,
            color: color,
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

/// The latest weight and the server's change sentence — never a figure computed here (rule 2).
class _BodyStatsCard extends StatelessWidget {
  const _BodyStatsCard({required this.history, required this.latest});

  final MeasurementHistory history;
  final Measurement latest;

  static const _disc = 36.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The last 30 days first (docs/21 §3), since-start as the fallback — same preference as the
    // Progress trend card, so the two screens never caption one chart two ways.
    final recent = history.change30d;
    final change = recent ?? history.change;
    final changeText = change == null
        ? null
        : change.abs() < 0.1
        ? (recent != null ? l.progressChange30Flat : l.progressChangeFlat)
        : change < 0
        ? (recent != null
              ? l.progressChange30Down(change.abs().toStringAsFixed(1))
              : l.progressChangeDown(change.abs().toStringAsFixed(1)))
        : (recent != null
              ? l.progressChange30Up(change.abs().toStringAsFixed(1))
              : l.progressChangeUp(change.abs().toStringAsFixed(1)));

    return AppCard(
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: _disc,
              width: _disc,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(
                Icons.monitor_weight_outlined,
                size: AppSpacing.lg,
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
                  '${latest.value.toStringAsFixed(1)} ${latest.unit}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(l.progressCurrentWeight, style: theme.textTheme.bodySmall),
                if (changeText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(changeText, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One quick action: a pill that goes somewhere that exists.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSpacing.lg, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: theme.textTheme.labelLarge),
              Icon(Icons.chevron_right, size: AppSpacing.lg, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      // Wraps instead of overflowing at 200 % font scale.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Disables itself while the call is in flight so a double tap cannot fire two logouts.
class _SignOutButton extends StatefulWidget {
  const _SignOutButton();

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    // SessionController clears local state even if the server call fails, then RootGate flips back
    // to the login page — there is nothing to navigate here.
    await Get.find<SessionController>().signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // The list it sits in carries the horizontal padding now (D-146).
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(onPressed: _busy ? null : _signOut, child: Text(l10n.signOut)),
    );
  }
}
