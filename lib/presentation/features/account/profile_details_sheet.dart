import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/section_header.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/account/edit_sheets.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

/// Everything the You tab knows about the person below their daily goals: body stats, the sign-in
/// number, details, health, their day and their routine (D-237). One tap from the "Explore your
/// profile" row, so the page itself stays a glance plus a list of places to go.
abstract final class ProfileDetailsSheet {
  static Future<void> show(BuildContext context, AccountController controller) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ProfileDetailsBody(controller: controller),
      );
}

/// Reads the controller rather than a profile handed in at open time: an edit made from inside the
/// sheet reloads the profile, and the sheet must show what the server stored, not what it opened on.
class _ProfileDetailsBody extends StatelessWidget {
  const _ProfileDetailsBody({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Obx(
        () => switch (controller.state.value) {
          Loading<ProfileView>() => const LoadingView(),
          Empty<ProfileView>() => EmptyView(title: l.accountEmptyTitle, body: l.accountEmptyBody),
          Failed<ProfileView>(:final failure) => FailedView(
            failure: failure,
            onRetry: controller.load,
            retryLabel: l.accountRetry,
          ),
          Ready<ProfileView>(:final data) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Text(l.accountExplore, style: theme.textTheme.titleLarge),
              _ProfileSections(
                profile: data,
                controller: controller,
                // Quiet: a loud reload flips the state to Loading and blanks the sheet the user is
                // still looking at.
                onEdited: () => controller.load(quiet: true),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _ProfileSections extends StatelessWidget {
  const _ProfileSections({required this.profile, required this.controller, required this.onEdited});

  final ProfileView profile;
  final AccountController controller;
  final Future<void> Function() onEdited;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Every enum goes back through the label extensions — CLAUDE.md rule 4, never a raw wire value.
    final sex = enumFromWire(SexAtBirth.values, profile.sexAtBirth, (e) => e.wire);
    final goal = enumFromWire(Goal.values, profile.goal, (e) => e.wire);
    final activity = enumFromWire(ActivityLevel.values, profile.activity, (e) => e.wire);
    final diet = enumFromWire(FoodPreference.values, profile.foodPreference, (e) => e.wire);
    final mealCount = enumFromWire(MealCount.values, profile.mealCount, (e) => e.wire);
    final lifestyle = enumFromWire(Lifestyle.values, profile.lifestyle, (e) => e.wire);

    final conditions = profile.conditions
        .map((w) => enumFromWire(Condition.values, w, (e) => e.wire)?.label(l))
        .whereType<String>()
        .toList();
    final allergies = profile.allergies
        .map((w) => enumFromWire(FoodAllergy.values, w, (e) => e.wire)?.label(l))
        .whereType<String>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  // Down first: a tab switch under an open sheet lands out of sight.
                  Navigator.of(context).pop();
                  if (Get.isRegistered<NavController>()) {
                    Get.find<NavController>().current = ClientTab.progress;
                  }
                },
              ),
              _BodyStatsCard(history: history, latest: latest),
            ],
          );
        }),
        // The number the account signs in with. Its own section, with no Edit beside it,
        // because changing it means proving the new number with an OTP — and a row sitting
        // under a heading marked editable promises something no screen here can do.
        //
        // Absent entirely for an email or social signup rather than reading "Not set": there
        // is no number to set, and offering one would invent a step.
        if (profile.phone case final phone? when phone.isNotEmpty) ...[
          SectionHeader(title: l.accountAccountSection),
          AppCard(
            child: Column(
              children: _Row.card([
                _Row(
                  label: l.accountPhone,
                  value: phone,
                  icon: Icons.phone_outlined,
                  tint: AppColors.success,
                ),
              ]),
            ),
          ),
        ],
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
            // Age and height live in the hero strip now (D-146); repeating them here would
            // print the same fact twice on one screen.
            children: _Row.card([
              _Row(
                label: l.fieldWeightKg,
                value: l.accountWeightValue(profile.weightKg.toStringAsFixed(1)),
                icon: Icons.monitor_weight_outlined,
                tint: AppColors.macroFat,
              ),
              if (sex != null)
                _Row(
                  label: l.accountSex,
                  value: sex.label(l),
                  icon: Icons.wc_outlined,
                  tint: AppColors.macroCarb,
                ),
              if (goal != null)
                _Row(
                  label: l.accountGoal,
                  value: goal.label(l),
                  icon: Icons.adjust_outlined,
                  tint: AppColors.warmCoral,
                ),
              if (activity != null)
                _Row(
                  label: l.accountActivity,
                  value: activity.label(l),
                  icon: Icons.directions_run_outlined,
                  tint: AppColors.success,
                ),
              if (diet != null)
                _Row(
                  label: l.accountDiet,
                  value: diet.label(l),
                  icon: Icons.restaurant_outlined,
                  tint: AppColors.warning,
                ),
              if (profile.goalWeightKg case final target?)
                _Row(
                  label: l.accountGoalWeight,
                  value: l.accountWeightValue(target.toStringAsFixed(1)),
                  icon: Icons.flag_outlined,
                  tint: AppColors.accent,
                ),
            ]),
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
                icon: Icons.favorite_outline,
                tint: AppColors.danger,
              ),
              _Row(
                label: l.accountAllergies,
                value: allergies.isEmpty ? l.accountNone : allergies.join(', '),
                icon: Icons.coronavirus_outlined,
                tint: AppColors.macroCarb,
              ),
              // Declared, never diagnosed. These were collected at onboarding and had no home
              // on this screen, so the user could not check what the plan was built from.
              _Row(
                label: l.accountMedications,
                value: profile.medications?.trim().isNotEmpty ?? false
                    ? profile.medications!
                    : l.accountNone,
                icon: Icons.medication_outlined,
                tint: AppColors.info,
              ),
              _Row(
                label: l.accountDigestive,
                value: profile.digestiveSymptoms.isEmpty
                    ? l.accountNone
                    : profile.digestiveSymptoms.join(', '),
                icon: Icons.local_fire_department_outlined,
                tint: AppColors.macroProtein,
              ),
              _Row(
                label: l.accountInjuries,
                value: profile.injuries.isEmpty ? l.accountNone : profile.injuries.join(', '),
                icon: Icons.healing_outlined,
                tint: AppColors.warmCoral,
                last: true,
              ),
            ],
          ),
        ),

        // The shape of the day the plan is built around. Every one of these was asked during
        // onboarding and none of it was readable afterwards.
        SectionHeader(title: l.accountYourDay),
        AppCard(
          child: Column(
            // Absent for the three and four-meal patterns, which have no such occasion
            // (docs/04 §7) — so the row is absent too rather than reading "Not set".
            children: _TimeRow.list(context, [
              _TimeRow(
                label: l.accountWakeTime,
                time: profile.wakeTime,
                icon: Icons.wb_sunny_outlined,
                tint: AppColors.warning,
              ),
              _TimeRow(
                label: l.accountSleepTime,
                time: profile.sleepTime,
                icon: Icons.bedtime_outlined,
                tint: AppColors.macroCarb,
              ),
              _TimeRow(
                label: l.onboardingBreakfastTime,
                time: profile.breakfastTime,
                icon: Icons.free_breakfast_outlined,
                tint: AppColors.warmCoral,
              ),
              _TimeRow(
                label: l.onboardingMidMorningTime,
                time: profile.midMorningTime,
                icon: Icons.local_cafe_outlined,
                tint: AppColors.macroFat,
              ),
              _TimeRow(
                label: l.onboardingLunchTime,
                time: profile.lunchTime,
                icon: Icons.lunch_dining_outlined,
                tint: AppColors.success,
              ),
              _TimeRow(
                label: l.onboardingEveningSnackTime,
                time: profile.eveningSnackTime,
                icon: Icons.cookie_outlined,
                tint: AppColors.accent,
              ),
              _TimeRow(
                label: l.onboardingDinnerTime,
                time: profile.dinnerTime,
                icon: Icons.dinner_dining_outlined,
                tint: AppColors.macroProtein,
              ),
              _TimeRow(
                label: l.onboardingBedtimeSnackTime,
                time: profile.bedtimeSnackTime,
                icon: Icons.nightlight_outlined,
                tint: AppColors.info,
              ),
            ]),
          ),
        ),

        SectionHeader(title: l.accountYourRoutine),
        AppCard(
          child: Column(
            children: _Row.card([
              if (mealCount != null)
                _Row(
                  label: l.accountMealCount,
                  value: mealCount.label(l),
                  icon: Icons.restaurant_menu_outlined,
                  tint: AppColors.macroProtein,
                ),
              if (lifestyle != null)
                _Row(
                  label: l.accountLifestyle,
                  value: lifestyle.label(l),
                  icon: Icons.work_outline,
                  tint: AppColors.macroCarb,
                ),
              if (profile.budgetMonthlyInr case final budget?)
                _Row(
                  label: l.accountBudget,
                  value: Rupees.format(budget),
                  icon: Icons.account_balance_wallet_outlined,
                  tint: AppColors.success,
                ),
              _Row(
                label: l.accountDislikes,
                value: profile.foodDislikes?.trim().isNotEmpty ?? false
                    ? profile.foodDislikes!
                    : l.accountNone,
                icon: Icons.block_outlined,
                tint: AppColors.danger,
              ),
            ]),
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

/// A clock value, or nothing at all.
///
/// Absent rather than "Not set": a meal slot the user's pattern does not have (docs/04 §7) was
/// never asked for, and printing it as missing would invite them to fill in a meal they do not eat.
class _TimeRow {
  const _TimeRow({required this.label, required this.time, required this.icon, required this.tint});

  final String label;
  final String? time;
  final IconData icon;
  final Color tint;

  /// Renders the ones that have a time, and only the LAST of those drops its divider — which is
  /// why this is a list builder rather than a widget: whether a row is last depends on which of
  /// its neighbours the user's meal pattern left out.
  static List<Widget> list(BuildContext context, List<_TimeRow> rows) {
    final shown = <_Row>[];

    for (final row in rows) {
      final value = row.time;
      if (value == null || value.isEmpty) continue;

      final text = TimeOfDayText.formatWire(context, value);
      if (text == null) continue;

      shown.add(_Row(label: row.label, value: text, icon: row.icon, tint: row.tint));
    }

    return _Row.card(shown);
  }
}

/// One fact about the user: a tinted glyph, the label, the answer.
///
/// The glyph is what makes a column of twenty facts scannable — the eye finds "Diet" by its colour
/// long before it reads the word. Each row names its own, because a single shared icon would make
/// the list look like one repeated row (D-190).
///
/// The colour comes from the palette (rule 5), and it is IDENTITY rather than judgement: weight is
/// blue whether it is going up or down, exactly as docs/05 §6 requires of the macro colours.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.icon, this.tint, this.last = false});

  final String label;
  final String value;
  final IconData? icon;
  final Color? tint;

  /// The last row in a card draws no divider — otherwise the card ends on a line that separates
  /// it from nothing.
  final bool last;

  /// The rows that survived the user's answers, with the final divider dropped.
  ///
  /// [last] cannot be set at the call site on a card whose rows are conditional: skip the goal
  /// weight and "Diet" becomes the bottom row, ending the card on a line that separates it from
  /// nothing.
  static List<Widget> card(List<_Row?> rows) {
    final shown = rows.whereType<_Row>().toList();
    if (shown.isEmpty) return const [];

    return [...shown.take(shown.length - 1), shown.last._asLast()];
  }

  _Row _asLast() => _Row(label: label, value: value, icon: icon, tint: tint, last: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = tint ?? theme.colorScheme.primary;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          // Wraps instead of overflowing at 200 % font scale.
          child: Row(
            children: [
              if (icon != null) ...[
                // Decoration: the LABEL beside it carries the meaning, so a screen reader is not
                // made to announce a colour.
                ExcludeSemantics(
                  child: Container(
                    height: AppSizes.choiceDisc,
                    width: AppSizes.choiceDisc,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Icon(icon, size: AppSpacing.lg, color: colour),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (!last) Divider(color: theme.colorScheme.outline),
      ],
    );
  }
}
