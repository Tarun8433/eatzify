// GetX exports its own `Condition`; ours is the docs/03 §2 health condition.
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/usecases/validate_onboarding.dart';

/// Steps of the onboarding flow. docs/14 §6.
///
/// `gate` is not reached by advancing — it is jumped to when docs/05 §3 says no plan may be made.
enum OnboardingStep { basics, goal, activity, conditions, diet, routine, consent, gate, done }

/// Holds the draft and walks the steps. docs/14 §3: one controller per screen, reactive `.obs`
/// fields, no god-object state class.
///
/// CLAUDE.md rule 2: nothing here computes a target, a macro or an entitlement. It collects input,
/// applies the docs/02 FR-1 input rules, and decides which screen comes next. The server decides
/// everything else.
class OnboardingController extends GetxController {
  final step = OnboardingStep.basics.obs;

  // Basics
  final ageYears = RxnInt();
  final heightCm = RxnInt();
  final weightKg = RxnDouble();
  final sexAtBirth = Rxn<SexAtBirth>();

  final goal = Rxn<Goal>();
  final activity = Rxn<ActivityLevel>();
  final conditions = <Condition>{}.obs;

  // docs/03 §2 — the rest of the contract.
  final foodPreference = Rxn<FoodPreference>();
  final allergies = <FoodAllergy>{}.obs;
  final mealCount = Rxn<MealCount>();
  final lifestyle = Rxn<Lifestyle>();
  final budgetTier = Rxn<BudgetTier>();

  final consentGranted = false.obs;

  /// Set when a field is rejected. The UI maps it to l10n — no copy in the controller.
  final reject = Rxn<OnboardingReject>();

  /// Fields the user must confirm because they are unusual but legal (FR-1.4).
  final needsConfirm = <String>{}.obs;

  /// docs/05 §3 gates that fired. Non-empty means no plan is generated, at all.
  final gates = <Condition>{}.obs;

  static const _orderedSteps = [
    OnboardingStep.basics,
    OnboardingStep.goal,
    OnboardingStep.activity,
    OnboardingStep.conditions,
    OnboardingStep.diet,
    OnboardingStep.routine,
    OnboardingStep.consent,
  ];

  int get stepNumber => _orderedSteps.indexOf(step.value) + 1;
  int get totalSteps => _orderedSteps.length;

  /// FR-1.3 — asked of women 18–50 only.
  bool get asksPregnancyStatus {
    final sex = sexAtBirth.value;
    final age = ageYears.value;
    if (sex == null || age == null) return false;
    return ValidateOnboarding.shouldAskPregnancyStatus(sex: sex, ageYears: age);
  }

  bool get canAdvance => switch (step.value) {
    OnboardingStep.basics =>
      ageYears.value != null &&
          heightCm.value != null &&
          weightKg.value != null &&
          sexAtBirth.value != null,
    OnboardingStep.goal => goal.value != null,
    OnboardingStep.activity => activity.value != null,
    OnboardingStep.conditions => conditions.isNotEmpty,
    // Allergies are legitimately empty for most people, so they do not gate the step.
    OnboardingStep.diet => foodPreference.value != null,
    OnboardingStep.routine =>
      mealCount.value != null && lifestyle.value != null && budgetTier.value != null,
    OnboardingStep.consent => consentGranted.value,
    OnboardingStep.gate || OnboardingStep.done => false,
  };

  /// [silent] is used while the user is still typing: the value is recorded if it is valid, but no
  /// rejection is shown yet. The field commits non-silently on blur or submit.
  ///
  /// Recording live matters — if the value were only stored on blur, the last field the user
  /// touches would never commit and Continue would stay disabled with the form visibly complete.
  void setAge(int? years, {bool silent = false}) {
    reject.value = null;
    if (years == null) {
      ageYears.value = null;
      return;
    }
    final check = ValidateOnboarding.age(years);
    if (check.reject != null) {
      if (!silent) reject.value = check.reject;
      ageYears.value = null;
      return;
    }
    ageYears.value = years;
  }

  void setHeight(int? cm, {bool silent = false}) => _setMeasure(
    cm,
    'height',
    ValidateOnboarding.heightCm,
    (v) => heightCm.value = v,
    silent: silent,
  );

  void setWeight(double? kg, {bool silent = false}) => _setMeasure(
    kg,
    'weight',
    ValidateOnboarding.weightKg,
    (v) => weightKg.value = v,
    silent: silent,
  );

  void _setMeasure<T extends num>(
    T? value,
    String field,
    FieldCheck Function(T) check,
    void Function(T?) assign, {
    bool silent = false,
  }) {
    reject.value = null;
    needsConfirm.remove(field);
    if (value == null) {
      assign(null);
      return;
    }
    final result = check(value);
    if (result.reject != null) {
      if (!silent) reject.value = result.reject;
      assign(null);
      return;
    }
    // FR-1.4's confirm-on-outlier is only raised once the user has finished with the field.
    if (result.confirmNeeded && !silent) needsConfirm.add(field);
    assign(value);
  }

  /// docs/03 §2 exclusivity is applied here rather than reported, so the UI cannot get it wrong.
  void toggleCondition(Condition c) {
    reject.value = null;
    conditions.assignAll(ValidateOnboarding.toggleCondition(conditions.toSet(), c));
  }

  void toggleAllergy(FoodAllergy a) {
    final next = allergies.toSet();
    allergies.assignAll(next.contains(a) ? (next..remove(a)) : (next..add(a)));
  }

  void next() {
    reject.value = null;
    if (!canAdvance) return;

    // docs/05 §3: evaluate gates the moment conditions are known. A blocking gate means the flow
    // ends here — we do not collect consent for data we will not use, and no plan is generated.
    if (step.value == OnboardingStep.conditions) {
      final fired = ValidateOnboarding.blockingGates(conditions.toSet());
      if (fired.isNotEmpty) {
        gates.assignAll(fired);
        step.value = OnboardingStep.gate;
        return;
      }
    }

    final i = _orderedSteps.indexOf(step.value);
    if (i >= 0 && i < _orderedSteps.length - 1) {
      step.value = _orderedSteps[i + 1];
      return;
    }
    // Last step. Plan generation is a server call (docs/09 POST /plans/generate) that does not
    // exist yet, so we finish honestly rather than leaving the button inert.
    if (step.value == OnboardingStep.consent) step.value = OnboardingStep.done;
  }

  void back() {
    reject.value = null;
    if (step.value == OnboardingStep.gate) {
      step.value = OnboardingStep.conditions;
      gates.clear();
      return;
    }
    if (step.value == OnboardingStep.done) {
      step.value = OnboardingStep.consent;
      return;
    }
    final i = _orderedSteps.indexOf(step.value);
    if (i > 0) step.value = _orderedSteps[i - 1];
  }
}
