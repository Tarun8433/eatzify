import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/section_header.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/client_diary_page.dart';
import 'package:health_pro/presentation/features/coach/client_progress_section.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// One client, opened from the roster (D-195, D-199).
///
/// The server has already decided what may appear here — the intersection of what the client
/// granted and what this coach's level reaches — so the page renders what arrived and filters
/// nothing itself. Two places deciding one access rule is how they come to disagree.
class ClientDetailController extends GetxController {
  ClientDetailController({required this.coach, required this.clientUserId});

  final CoachRepository coach;
  final int clientUserId;

  final state = Rx<ViewState<CoachClientDetail>>(const Loading());

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await coach.client(clientUserId);
    result.fold((f) => state.value = Failed(f), (d) => state.value = Ready(d));
  }
}

class ClientDetailPage extends StatelessWidget {
  const ClientDetailPage({required this.clientUserId, required this.name, super.key});

  final int clientUserId;

  /// Carried from the roster so the title is right during the load. The page still reads the name
  /// back from the server — this is only what to show while waiting.
  final String name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.put(
      ClientDetailController(coach: Get.find<CoachRepository>(), clientUserId: clientUserId),
      tag: 'client-$clientUserId',
    );

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<CoachClientDetail>() => const LoadingView(),
          // Reachable when the client revokes between the roster loading and this opening. Not a
          // failure — access ended, which is the client's right and needs saying plainly.
          Empty<CoachClientDetail>() => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: EmptyView(title: l.coachAccessEnded, body: l.coachAccessEndedBody),
          ),
          Failed<CoachClientDetail>(:final failure) => _Failed(failure: failure, onRetry: c.load),
          Ready<CoachClientDetail>(:final data) => _Detail(client: data),
        },
      ),
    );
  }
}

/// A 404 here means "no grant" as much as "no such person" — the server answers both the same way
/// so an id cannot be used to learn who exists. Shown as access ending rather than as an error,
/// because for a coach that is what it is.
class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final Failure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (failure is ApiFailure && (failure as ApiFailure).status == 404) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyView(title: l.coachAccessEnded, body: l.coachAccessEndedBody),
      );
    }

    return FailedView(failure: failure, onRetry: onRetry);
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.client});

  final CoachClientDetail client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final goal = enumFromWire(Goal.values, client.goal ?? '', (e) => e.wire);
    final sex = enumFromWire(SexAtBirth.values, client.sexAtBirth ?? '', (e) => e.wire);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        // Says what the coach may see before they notice what is missing. docs/10 §3 makes the
        // grant the client's decision, so its limits are a fact about the relationship rather
        // than a fault in the screen.
        HintCard(
          icon: Icons.lock_outline,
          title: l.coachWhatYouCanSee,
          text: l.coachScopeCount(client.scopes.length),
        ),
        const SizedBox(height: AppSpacing.lg),

        AppCard(
          child: Column(
            children: _Fact.card([
              if (client.ageYears case final years?)
                _Fact(
                  label: l.fieldAge,
                  value: '$years',
                  icon: Icons.cake_outlined,
                  tint: AppColors.macroCarb,
                ),
              // A level 1 coach gets the band instead of the number (docs/10 §2).
              if (client.ageBand case final band?)
                _Fact(
                  label: l.fieldAge,
                  value: band,
                  icon: Icons.cake_outlined,
                  tint: AppColors.macroCarb,
                ),
              if (sex != null)
                _Fact(
                  label: l.accountSex,
                  value: sex.label(l),
                  icon: Icons.wc_outlined,
                  tint: AppColors.macroCarb,
                ),
              if (goal != null)
                _Fact(
                  label: l.accountGoal,
                  value: goal.label(l),
                  icon: Icons.adjust_outlined,
                  tint: AppColors.warmCoral,
                ),
              if (client.heightCm case final cm?)
                _Fact(
                  label: l.fieldHeightCm,
                  value: '$cm',
                  icon: Icons.straighten_outlined,
                  tint: AppColors.success,
                ),
              if (client.weightKg case final kg?)
                _Fact(
                  label: l.fieldWeightShort,
                  value: l.accountWeightValue(kg.toStringAsFixed(1)),
                  icon: Icons.monitor_weight_outlined,
                  tint: AppColors.macroFat,
                ),
              // Absent and empty differ: no key means the client did not grant this, an empty
              // list means they declared none. Only the second is printed as "None".
              if (client.conditions case final rows?)
                _Fact(
                  label: l.accountConditions,
                  value: rows.isEmpty ? l.accountNone : rows.join(', '),
                  icon: Icons.favorite_outline,
                  tint: AppColors.danger,
                ),
              if (client.allergies case final rows?)
                _Fact(
                  label: l.accountAllergies,
                  value: rows.isEmpty ? l.accountNone : rows.join(', '),
                  icon: Icons.coronavirus_outlined,
                  tint: AppColors.macroCarb,
                ),
              // Declared, never diagnosed — and the rest of what somebody writing a diet has to
              // know before they write it.
              if (client.medications case final medicines?)
                _Fact(
                  label: l.coachMedications,
                  value: medicines.trim().isEmpty ? l.accountNone : medicines,
                  icon: Icons.medication_outlined,
                  tint: AppColors.info,
                ),
              if (client.digestiveSymptoms case final rows?)
                _Fact(
                  label: l.coachDigestive,
                  value: rows.isEmpty ? l.accountNone : rows.join(', '),
                  icon: Icons.local_fire_department_outlined,
                  tint: AppColors.macroProtein,
                ),
              if (client.injuries case final rows?)
                _Fact(
                  label: l.coachInjuries,
                  value: rows.isEmpty ? l.accountNone : rows.join(', '),
                  icon: Icons.healing_outlined,
                  tint: AppColors.warmCoral,
                ),
            ]),
          ),
        ),

        // The answers the plan was written from. Not medical, and the first thing a nutritionist
        // needs: five meals a day on a night shift with a karela allergy is a different diet from
        // three meals in an office (D-205).
        if (client.routine case final routine?) ...[
          const SizedBox(height: AppSpacing.lg),
          _Routine(routine: routine),
        ],

        // What they actually ate, day by day (D-206). Its own screen rather than a section: a
        // diary is one day at a time, and a coach reads several of them in a row.
        if (client.scopes.contains('progress')) ...[
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: AppSizes.primaryButton,
            child: FilledButton.tonalIcon(
              onPressed: () => Get.to<void>(
                () => ClientDiaryPage(clientUserId: client.userId, name: client.name),
              ),
              icon: const Icon(Icons.restaurant_outlined),
              label: Text(l.coachDiaryOpen),
            ),
          ),
        ],

        // Everything they have actually been logging, under the facts they declared (D-203). Its
        // own read and its own audit row: the profile is what somebody typed once, and this is
        // what they do every day.
        if (client.scopes.contains('progress')) ...[
          const SizedBox(height: AppSpacing.lg),
          ClientProgressSection(clientUserId: client.userId),
        ],

        if (!client.hasAnyDetail) ...[
          const SizedBox(height: AppSpacing.lg),
          // The grant is `basic` and the level reaches nothing more. Saying so beats a page that
          // looks broken, and it names the thing that would change it.
          HintCard(icon: Icons.info_outline, title: l.coachOnlyBasics, text: l.coachOnlyBasicsBody),
        ],
      ],
    );
  }
}

/// One fact about a client. The profile screen's row, in the one place a coach reads the same
/// kind of list — a coloured glyph, the label, the answer, a divider between.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final bool last;

  /// Which row is last is a runtime fact here: a client who granted less has fewer rows, and the
  /// card must not end on a divider that separates it from nothing.
  static List<Widget> card(List<_Fact?> rows) {
    final shown = rows.whereType<_Fact>().toList();
    if (shown.isEmpty) return const [];

    return [...shown.take(shown.length - 1), shown.last._asLast()];
  }

  _Fact _asLast() => _Fact(label: label, value: value, icon: icon, tint: tint, last: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.choiceDisc,
                  width: AppSizes.choiceDisc,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(icon, size: AppSpacing.lg, color: tint),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
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

/// The answers the diet plan was written from.
///
/// Every one of these came from onboarding and none of them reached a coach until D-205. A
/// nutritionist who cannot see that somebody eats five times a day, works nights, has ₹6,000 a
/// month and will not touch karela is writing a plan by guesswork.
class _Routine extends StatelessWidget {
  const _Routine({required this.routine});

  final Map<String, dynamic> routine;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mealCount = enumFromWire(
      MealCount.values,
      '${routine['meal_count'] ?? ''}',
      (e) => e.wire,
    );
    final lifestyle = enumFromWire(
      Lifestyle.values,
      '${routine['lifestyle'] ?? ''}',
      (e) => e.wire,
    );
    final diet = enumFromWire(
      FoodPreference.values,
      '${routine['food_preference'] ?? ''}',
      (e) => e.wire,
    );
    final activity = enumFromWire(
      ActivityLevel.values,
      '${routine['activity'] ?? ''}',
      (e) => e.wire,
    );

    final times = <(String, String)>[
      (l.accountWakeTime, '${routine['wake_time'] ?? ''}'),
      (l.onboardingBreakfastTime, '${routine['breakfast_time'] ?? ''}'),
      (l.onboardingMidMorningTime, '${routine['mid_morning_time'] ?? ''}'),
      (l.onboardingLunchTime, '${routine['lunch_time'] ?? ''}'),
      (l.onboardingEveningSnackTime, '${routine['evening_snack_time'] ?? ''}'),
      (l.onboardingDinnerTime, '${routine['dinner_time'] ?? ''}'),
      (l.onboardingBedtimeSnackTime, '${routine['bedtime_snack_time'] ?? ''}'),
      (l.accountSleepTime, '${routine['sleep_time'] ?? ''}'),
    ].where((t) => t.$2.isNotEmpty && t.$2 != 'null').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l.coachRoutineTitle),
        AppCard(
          child: Column(
            children: _Fact.card([
              if (mealCount != null)
                _Fact(
                  label: l.coachRoutineMealCount,
                  value: mealCount.label(l),
                  icon: Icons.restaurant_menu_outlined,
                  tint: AppColors.macroProtein,
                ),
              if (lifestyle != null)
                _Fact(
                  label: l.coachRoutineLifestyle,
                  value: lifestyle.label(l),
                  icon: Icons.work_outline,
                  tint: AppColors.macroCarb,
                ),
              if (diet != null)
                _Fact(
                  label: l.coachRoutineDiet,
                  value: diet.label(l),
                  icon: Icons.restaurant_outlined,
                  tint: AppColors.warning,
                ),
              if (activity != null)
                _Fact(
                  label: l.coachRoutineActivity,
                  value: activity.label(l),
                  icon: Icons.directions_run_outlined,
                  tint: AppColors.success,
                ),
              if (routine['budget_monthly_inr'] case final budget? when budget is int)
                _Fact(
                  label: l.coachRoutineBudget,
                  value: Rupees.format(budget),
                  icon: Icons.account_balance_wallet_outlined,
                  tint: AppColors.success,
                ),
              // The single most actionable line on this card: what not to put in the plan.
              if ('${routine['food_dislikes'] ?? ''}' case final dislikes
                  when dislikes.isNotEmpty && dislikes != 'null')
                _Fact(
                  label: l.coachRoutineDislikes,
                  value: dislikes,
                  icon: Icons.block_outlined,
                  tint: AppColors.danger,
                ),
            ]),
          ),
        ),
        // When they actually eat. A plan that puts a meal at 8 a.m. for somebody who wakes at
        // noon is a plan nobody follows.
        if (times.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SectionHeader(title: l.coachRoutineTimes),
          AppCard(
            child: Column(
              children: _Fact.card([
                for (final (label, wire) in times)
                  _Fact(
                    label: label,
                    value: TimeOfDayText.formatWire(context, wire) ?? wire,
                    icon: Icons.schedule_outlined,
                    tint: AppColors.macroFat,
                  ),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}
