import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/edit_profile_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/choice_tile.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The two edit sheets on the You tab. They reuse `ChoiceTile` and the label extensions so an
/// edited value goes through exactly the same rendering path as the onboarding flow.
///
/// Everything onboarding asked for is editable here (D-72). Age and height were held back on the
/// grounds that they move a docs/05 §3 gate — but `PATCH /profile` re-runs every gate when an
/// anthropometric changes and returns the new health-profile version, so the consequence is applied
/// and visible rather than silent. Leaving them out meant a typo at signup was permanent, and it
/// meant `MEAL_PATTERN_CONFLICT` told users to change a field the app did not offer.
abstract final class EditSheets {
  static Future<bool?> details(BuildContext context, ProfileView profile) =>
      _show(context, profile, health: false);

  static Future<bool?> health(BuildContext context, ProfileView profile) =>
      _show(context, profile, health: true);

  static Future<bool?> _show(BuildContext context, ProfileView profile, {required bool health}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _EditSheet(profile: profile, health: health),
      );
}

class _EditSheet extends StatelessWidget {
  const _EditSheet({required this.profile, required this.health});

  final ProfileView profile;
  final bool health;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = Get.put(
      EditProfileController(profiles: Get.find<ProfileRepository>(), initial: profile),
      tag: health ? 'health' : 'details',
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Text(
              health ? l.accountEditHealth : l.accountEditDetails,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: health ? _healthFields(c, l) : _detailFields(c, l),
              ),
            ),
            Obx(
              () => Column(
                children: [
                  if (c.error.value != null) ...[
                    // Rule 7: the server's own words, unmodified.
                    Text(
                      c.error.value!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: c.saving.value
                          ? null
                          : () async {
                              final ok = await c.save(health: health);
                              if (ok && context.mounted) Navigator.of(context).pop(true);
                            },
                      child: Text(l.accountSave),
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

  List<Widget> _detailFields(EditProfileController c, AppLocalizations l) => [
    FreeTextField(
      label: l.onboardingNameLabel,
      initial: c.name.value,
      maxLength: 80,
      onChanged: (v) => c.name.value = v,
    ),
    const SizedBox(height: AppSpacing.md),
    NumberField(
      label: l.fieldAge,
      initial: '${c.ageYears.value ?? ''}',
      helperText: '18 – 99',
      onLiveChange: (v) => c.ageYears.value = int.tryParse(v),
      onCommit: (v) => c.ageYears.value = int.tryParse(v),
    ),
    const SizedBox(height: AppSpacing.md),
    NumberField(
      label: l.fieldHeightCm,
      initial: '${c.heightCm.value ?? ''}',
      helperText: '120 – 220',
      onLiveChange: (v) => c.heightCm.value = int.tryParse(v),
      onCommit: (v) => c.heightCm.value = int.tryParse(v),
    ),
    const SizedBox(height: AppSpacing.md),
    NumberField(
      label: l.fieldWeightKg,
      decimal: true,
      initial: '${c.weightKg.value ?? ''}',
      helperText: '30.0 – 250.0',
      onLiveChange: (v) => c.weightKg.value = double.tryParse(v),
      onCommit: (v) => c.weightKg.value = double.tryParse(v),
    ),
    const SizedBox(height: AppSpacing.md),
    NumberField(
      label: l.onboardingGoalWeightLabel,
      decimal: true,
      initial: '${c.goalWeightKg.value ?? ''}',
      helperText: l.onboardingGoalWeightOptional,
      onLiveChange: (v) => c.goalWeightKg.value = double.tryParse(v),
      onCommit: (v) => c.goalWeightKg.value = double.tryParse(v),
    ),
    _SectionLabel(l.accountGoal),
    Obx(
      () => Column(
        children: [
          for (final g in GoalDeclared.values)
            ChoiceTile(
              label: g.label(l),
              selected: c.goalDeclared.value == g,
              onTap: () => c.goalDeclared.value = g,
            ),
        ],
      ),
    ),
    Obx(
      () => Column(
        children: [
          for (final g in Goal.values)
            ChoiceTile(
              label: g.label(l),
              selected: c.goal.value == g,
              onTap: () => c.goal.value = g,
            ),
        ],
      ),
    ),
    _SectionLabel(l.accountActivity),
    Obx(
      () => Column(
        children: [
          for (final a in ActivityLevel.values)
            ChoiceTile(
              label: a.label(l),
              description: a.description(l),
              selected: c.activity.value == a,
              onTap: () => c.activity.value = a,
            ),
        ],
      ),
    ),
    _SectionLabel(l.accountDiet),
    Obx(
      () => Column(
        children: [
          for (final d in FoodPreference.values)
            ChoiceTile(
              label: d.label(l),
              selected: c.diet.value == d,
              onTap: () => c.diet.value = d,
            ),
        ],
      ),
    ),
    // The field MEAL_PATTERN_CONFLICT tells the user to change. Without it here, the error was a
    // dead end: correct advice pointing at a control that did not exist.
    _SectionLabel(l.accountMealCount),
    Obx(
      () => Column(
        children: [
          for (final m in MealCount.values)
            ChoiceTile(
              label: m.label(l),
              selected: c.mealCount.value == m,
              onTap: () => c.mealCount.value = m,
            ),
        ],
      ),
    ),
    _SectionLabel(l.accountLifestyle),
    Obx(
      () => Column(
        children: [
          for (final v in Lifestyle.values)
            ChoiceTile(
              label: v.label(l),
              selected: c.lifestyle.value == v,
              onTap: () => c.lifestyle.value = v,
            ),
        ],
      ),
    ),
    _SectionLabel(l.accountBudget),
    Obx(() {
      final rupees = c.budgetMonthlyInr.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.onboardingBudgetPerMonth(Rupees.format(rupees))),
          Slider(
            value: rupees.toDouble(),
            min: BudgetRange.minInr.toDouble(),
            max: BudgetRange.maxInr.toDouble(),
            divisions: (BudgetRange.maxInr - BudgetRange.minInr) ~/ BudgetRange.stepInr,
            label: Rupees.format(rupees),
            onChanged: (v) => c.budgetMonthlyInr.value = BudgetRange.clamp(v.round()),
          ),
        ],
      );
    }),
    _SectionLabel(l.onboardingDailyRoutineTitle),
    Obx(
      () => Column(
        children: [
          TimeField(
            label: l.onboardingWakeTime,
            fallback: const TimeOfDay(hour: 7, minute: 0),
            value: c.wakeTime.value,
            onChanged: (v) => c.wakeTime.value = v,
          ),
          TimeField(
            label: l.onboardingSleepTime,
            fallback: const TimeOfDay(hour: 23, minute: 0),
            value: c.sleepTime.value,
            onChanged: (v) => c.sleepTime.value = v,
          ),
        ],
      ),
    ),
    // Derived from the two times above (D-77), so it cannot be edited into disagreeing with them.
    Obx(() {
      final hours = c.sleepHours;
      if (hours == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          l.onboardingSleepDerived(
            hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1),
          ),
        ),
      );
    }),
    _SectionLabel(l.onboardingMealTimingsTitle),
    Obx(
      () => Column(
        children: [
          TimeField(
            label: l.onboardingBreakfastTime,
            fallback: const TimeOfDay(hour: 8, minute: 30),
            value: c.breakfastTime.value,
            onChanged: (v) => c.breakfastTime.value = v,
          ),
          TimeField(
            label: l.onboardingLunchTime,
            fallback: const TimeOfDay(hour: 13, minute: 30),
            value: c.lunchTime.value,
            onChanged: (v) => c.lunchTime.value = v,
          ),
          TimeField(
            label: l.onboardingEveningSnackTime,
            fallback: const TimeOfDay(hour: 17, minute: 30),
            value: c.eveningSnackTime.value,
            onChanged: (v) => c.eveningSnackTime.value = v,
          ),
          TimeField(
            label: l.onboardingDinnerTime,
            fallback: const TimeOfDay(hour: 20, minute: 30),
            value: c.dinnerTime.value,
            onChanged: (v) => c.dinnerTime.value = v,
          ),
        ],
      ),
    ),
    _SectionLabel(l.onboardingDislikesLabel),
    FreeTextField(
      label: l.onboardingDislikesLabel,
      initial: c.foodDislikes.value,
      helperText: l.onboardingDislikesHint,
      maxLines: 2,
      onChanged: (v) => c.foodDislikes.value = v,
    ),
  ];

  List<Widget> _healthFields(EditProfileController c, AppLocalizations l) => [
    _SectionLabel(l.accountConditions),
    Obx(
      () => Column(
        children: [
          for (final condition in Condition.values)
            ChoiceTile(
              label: condition.label(l),
              selected: c.conditions.contains(condition),
              onTap: () => c.toggleCondition(condition),
            ),
        ],
      ),
    ),
    _SectionLabel(l.accountAllergies),
    Obx(
      () => Column(
        children: [
          for (final allergy in FoodAllergy.values)
            ChoiceTile(
              label: allergy.label(l),
              selected: c.allergies.contains(allergy),
              onTap: () => c.toggleAllergy(allergy),
            ),
        ],
      ),
    ),
    _SectionLabel(l.onboardingMedicationsLabel),
    FreeTextField(
      label: l.onboardingMedicationsLabel,
      initial: c.medications.value,
      helperText: l.onboardingMedicationsHint,
      maxLines: 3,
      onChanged: (v) => c.medications.value = v,
    ),
    _SectionLabel(l.onboardingDigestiveTitle),
    Obx(
      () => Column(
        children: [
          for (final d in DigestiveSymptom.values)
            ChoiceTile(
              label: d.label(l),
              selected: c.digestiveSymptoms.contains(d),
              onTap: () => c.toggleDigestiveSymptom(d),
            ),
        ],
      ),
    ),
    _SectionLabel(l.onboardingInjuriesTitle),
    Obx(
      () => Column(
        children: [
          for (final i in InjuryArea.values)
            ChoiceTile(
              label: i.label(l),
              selected: c.injuries.contains(i),
              onTap: () => c.toggleInjury(i),
            ),
        ],
      ),
    ),
    // FR-1.3: offered to female users only, the same rule onboarding applies.
    if (c.asksFemaleHealth) ...[
      _SectionLabel(l.onboardingWomensHealthTitle),
      Obx(
        () => Column(
          children: [
            for (final v in MenstrualRegularity.values)
              ChoiceTile(
                label: v.label(l),
                selected: c.menstrualRegularity.value == v,
                onTap: () => c.menstrualRegularity.value = v,
              ),
            _YesNoRow(
              question: l.onboardingPregnantQuestion,
              value: c.pregnantOrBreastfeeding.value,
              onChanged: (v) => c.pregnantOrBreastfeeding.value = v,
            ),
            _YesNoRow(
              question: l.onboardingHeavyBleedingQuestion,
              value: c.heavyBleedingOrPain.value,
              onChanged: (v) => c.heavyBleedingOrPain.value = v,
            ),
            _YesNoRow(
              question: l.onboardingHormonalMedicineQuestion,
              value: c.hormonalMedication.value,
              onChanged: (v) => c.hormonalMedication.value = v,
            ),
          ],
        ),
      ),
    ],
  ];
}

/// A yes/no pair, matching the onboarding screening rows.
class _YesNoRow extends StatelessWidget {
  const _YesNoRow({required this.question, required this.value, required this.onChanged});

  final String question;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final answer in [true, false])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: answer ? AppSpacing.sm : 0),
                    child: ChoiceTile(
                      label: answer ? l.answerYes : l.answerNo,
                      selected: value == answer,
                      onTap: () => onChanged(answer),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
