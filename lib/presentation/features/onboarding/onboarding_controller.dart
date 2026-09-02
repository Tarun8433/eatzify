import 'dart:async';

import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/usecases/validate_onboarding.dart';

// GetX exports its own `Condition`; ours is the docs/03 §2 health condition.

/// Steps of the onboarding flow. docs/14 §6.
///
/// `gate` is not reached by advancing — it is jumped to when docs/05 §3 says no plan may be made.
enum OnboardingStep {
  basics,

  /// Not a question (D-101). It shows the user the gap between the two weights they just typed,
  /// drawn rather than printed. The funnel is twelve screens of being asked things; this is the
  /// one that gives something back, and it costs no extra input.
  result,

  goal,
  activity,

  /// Wake, sleep and hours slept. Separate from [routine], which is the meal-shape step.
  dailyRoutine,
  conditions,

  /// Medicines, digestive symptoms and injuries — declared, never diagnosed by the app.
  health,

  /// FR-1.3: shown only when `sex_at_birth == female`. Skipped entirely otherwise.
  womensHealth,
  screening,
  diet,

  /// Meal timings, so the plan lands when the user actually eats.
  mealTimings,
  routine,

  /// Not a question (D-114). The bookend to [result]: the same curve, now with the shape of the
  /// plan the user has chosen around it — meals a day, typical day, meal times, and the budget
  /// they set. Everything on it is their own answers read back, never a projection.
  summary,

  consent,
  gate,
  done,
}

/// Why the flow stopped. docs/05 §3 and §4 route to three DIFFERENT screens, and conflating them
/// would put eating-disorder support behind a coach-unlock, or tell a pregnant user a coach can
/// unlock a plan for her. They are not interchangeable.
enum GateOutcome {
  /// No plan, ever, from the app. Referral to a clinician.
  blocked,

  /// A coach with a recorded clinician attestation can unlock it.
  clinicianRequired,

  /// Eating-disorder disclosure. Support screen, no targets, and no re-ask for 90 days.
  eatingDisorderSupport,
}

/// Holds the draft and walks the steps. docs/14 §3: one controller per screen, reactive `.obs`
/// fields, no god-object state class.
///
/// CLAUDE.md rule 2: nothing here computes a target, a macro or an entitlement. It collects input,
/// applies the docs/02 FR-1 input rules, and decides which screen comes next. The server decides
/// everything else.
class OnboardingController extends GetxController {
  /// Resolved lazily rather than in the constructor so a widget test that never submits does not
  /// have to register a repository at all.
  OnboardingController({
    ProfileRepository? profiles,
    PlanRepository? plans,
    SessionController? session,
  }) : _injectedProfiles = profiles,
       _injectedPlans = plans,
       _injectedSession = session;

  final ProfileRepository? _injectedProfiles;
  final PlanRepository? _injectedPlans;
  final SessionController? _injectedSession;

  ProfileRepository get _profiles => _injectedProfiles ?? Get.find<ProfileRepository>();
  PlanRepository get _plans => _injectedPlans ?? Get.find<PlanRepository>();
  SessionController get _session => _injectedSession ?? Get.find<SessionController>();

  /// How long the "preparing" screen stays up at minimum.
  ///
  /// It is a floor, not a delay: the first plan is really being generated behind it. Without a
  /// floor a fast server makes the animation flash for 200 ms, which reads as a glitch rather than
  /// as work being done.
  static const preparingMinimum = Duration(seconds: 3);

  final step = OnboardingStep.basics.obs;

  /// True while `POST /profile/onboarding` is in flight — the submit button must not double-fire.
  final submitting = false.obs;

  /// The server's `user_message`, verbatim. CLAUDE.md rule 7: we never write our own copy here.
  final submitError = RxnString();

  /// True while the first plan is being generated behind the preparing screen.
  final preparing = false.obs;

  /// The server's message if that generation failed. Carried to Home rather than shown here — the
  /// user has finished onboarding either way and should not be held on a dead end.
  final planError = RxnString();

  // Basics
  final name = ''.obs;
  final ageYears = RxnInt();
  final heightCm = RxnInt();
  final weightKg = RxnDouble();
  final sexAtBirth = Rxn<SexAtBirth>();

  final goalWeightKg = RxnDouble();

  /// What the user picked. [goal] is derived from it — the engine never sees the seven-way choice.
  final goalDeclared = Rxn<GoalDeclared>();
  Goal? get goal => goalDeclared.value?.engineGoal;

  final activity = Rxn<ActivityLevel>();
  final conditions = <Condition>{}.obs;

  // Daily routine. "HH:MM" strings — a time of day, not an instant.
  final wakeTime = RxnString();
  final sleepTime = RxnString();

  /// Derived from the two clock times, never typed (D-77). Null until both are set.
  ///
  /// Strictly this is time in BED, not time asleep — someone down at 23:00 and up at 06:30 has not
  /// necessarily slept seven and a half hours. Asking for both a bedtime and a duration was asking
  /// the same question twice and inviting two answers that disagree.
  double? get sleepHours =>
      TimeOfDayText.hoursSlept(bedtime: sleepTime.value, wakeTime: wakeTime.value);

  // Health declarations.
  final medications = ''.obs;
  final digestiveSymptoms = <DigestiveSymptom>{}.obs;
  final injuries = <InjuryArea>{}.obs;

  // FR-1.3 female-only block.
  final menstrualRegularity = Rxn<MenstrualRegularity>();
  final pregnantOrBreastfeeding = Rxn<bool>();
  final heavyBleedingOrPain = Rxn<bool>();
  final hormonalMedication = Rxn<bool>();

  // Meal timings.
  final breakfastTime = RxnString();
  final lunchTime = RxnString();
  final eveningSnackTime = RxnString();
  final dinnerTime = RxnString();

  final foodDislikes = ''.obs;

  // docs/03 §2 — the rest of the contract.
  final foodPreference = Rxn<FoodPreference>();
  final allergies = <FoodAllergy>{}.obs;
  final mealCount = Rxn<MealCount>();
  final lifestyle = Rxn<Lifestyle>();

  /// Rupees a month, from the slider (D-78). The tier below is derived from it.
  final budgetMonthlyInr = BudgetRange.defaultInr.obs;

  BudgetTier get budgetTier => BudgetTier.forMonthlyInr(budgetMonthlyInr.value);

  final consentGranted = false.obs;

  // docs/05 §4 screening. Asked once, plainly, with no score shown to the user.
  final screenedSpecialDiet = Rxn<bool>(); // Q1 -> clinician gate
  final screenedInsulinOrKidney = Rxn<bool>(); // Q2 -> hard block
  final screenedEatingDisorder = Rxn<bool>(); // Q3 -> support routing

  /// Which end state fired, if any.
  final outcome = Rxn<GateOutcome>();

  /// Set when a field is rejected. The UI maps it to l10n — no copy in the controller.
  final reject = Rxn<OnboardingReject>();

  /// Fields the user must confirm because they are unusual but legal (FR-1.4).
  final needsConfirm = <String>{}.obs;

  /// docs/05 §3 gates that fired. Non-empty means no plan is generated, at all.
  final gates = <Condition>{}.obs;

  static const _allSteps = [
    OnboardingStep.basics,
    OnboardingStep.result,
    OnboardingStep.goal,
    OnboardingStep.activity,
    OnboardingStep.dailyRoutine,
    OnboardingStep.conditions,
    OnboardingStep.health,
    OnboardingStep.womensHealth,
    OnboardingStep.screening,
    OnboardingStep.diet,
    OnboardingStep.mealTimings,
    OnboardingStep.routine,
    OnboardingStep.summary,
    OnboardingStep.consent,
  ];

  /// Which way the last step change went, so the page can slide the right way (D-103). Forward is
  /// the default: the flow only ever opens going forwards.
  bool goingForward = true;

  /// The steps THIS user walks. `womensHealth` is dropped for anyone the FR-1.3 rule does not cover,
  /// so the progress counter reads "6 of 11" rather than skipping a number and looking broken.
  List<OnboardingStep> get _orderedSteps =>
      _allSteps.where((s) => s != OnboardingStep.womensHealth || asksFemaleHealth).toList();

  int get stepNumber => _orderedSteps.indexOf(step.value) + 1;
  int get totalSteps => _orderedSteps.length;

  /// FR-1.3 / docs/13: menstrual health is asked of female users only. For anyone else these are
  /// health fields with no clinical purpose, which we must not collect at all.
  bool get asksFemaleHealth => sexAtBirth.value == SexAtBirth.female;

  /// The healthy band for the height entered, once there is one (D-76). Null until then.
  ({double low, double high})? get healthyWeightRange {
    final height = heightCm.value;
    return height == null ? null : ValidateOnboarding.healthyWeightRangeKg(height);
  }

  /// Their BMI now, or null until age, sex, height and weight are all in.
  ///
  /// Sex and age are not in the formula — they are in the gate because the guidance is only shown
  /// once the whole set is entered, which is what the user asked for and what stops a number
  /// appearing beside a half-filled form.
  double? get currentBmi {
    final height = heightCm.value;
    final weight = weightKg.value;
    if (height == null || weight == null) return null;
    if (ageYears.value == null || sexAtBirth.value == null) return null;
    return ValidateOnboarding.bmiFor(weightKg: weight, heightCm: height);
  }

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
    // Nothing to answer — it exists to be read (D-101).
    OnboardingStep.result => true,
    OnboardingStep.goal => goalDeclared.value != null,
    OnboardingStep.activity => activity.value != null,
    // Both clock times, because the duration is derived from them (D-77).
    OnboardingStep.dailyRoutine => wakeTime.value != null && sleepTime.value != null,
    OnboardingStep.conditions => conditions.isNotEmpty,
    // Every field here is legitimately empty — "no medicines, no symptoms, no injuries" is the
    // common answer and must not require ticking three boxes to say nothing.
    OnboardingStep.health => true,
    OnboardingStep.womensHealth =>
      menstrualRegularity.value != null &&
          pregnantOrBreastfeeding.value != null &&
          heavyBleedingOrPain.value != null &&
          hormonalMedication.value != null,
    OnboardingStep.screening =>
      screenedSpecialDiet.value != null &&
          screenedInsulinOrKidney.value != null &&
          screenedEatingDisorder.value != null,
    // Allergies are legitimately empty for most people, so they do not gate the step.
    OnboardingStep.diet => foodPreference.value != null,
    // Timings drive when a plan's meals land, so all four are asked for.
    OnboardingStep.mealTimings =>
      breakfastTime.value != null &&
          lunchTime.value != null &&
          eveningSnackTime.value != null &&
          dinnerTime.value != null,
    OnboardingStep.routine => mealCount.value != null && lifestyle.value != null,
    // Nothing to answer — it exists to be read, like [result].
    OnboardingStep.summary => true,
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

  /// FR-1.4. Needs the height, so it re-checks whenever either moves — a goal weight that was legal
  /// at 175 cm is not necessarily legal after the height is corrected to 155.
  void setGoalWeight(double? kg, {bool silent = false}) {
    reject.value = null;
    needsConfirm.remove('goal_weight');
    if (kg == null) {
      goalWeightKg.value = null;
      return;
    }
    final height = heightCm.value;
    if (height == null) {
      goalWeightKg.value = kg;
      return;
    }
    final result = ValidateOnboarding.goalWeightKg(kg, heightCm: height);
    if (result.reject != null) {
      if (!silent) reject.value = result.reject;
      goalWeightKg.value = null;
      return;
    }
    if (result.confirmNeeded && !silent) needsConfirm.add('goal_weight');
    goalWeightKg.value = kg;
  }

  /// `none` is exclusive in every one of these sets, for the same reason it is in conditions:
  /// "no symptoms, and also bloating" is not an answer anyone means.
  void toggleDigestiveSymptom(DigestiveSymptom symptom) => digestiveSymptoms.assignAll(
    _toggleExclusive(digestiveSymptoms.toSet(), symptom, DigestiveSymptom.none),
  );

  void toggleInjury(InjuryArea injury) =>
      injuries.assignAll(_toggleExclusive(injuries.toSet(), injury, InjuryArea.none));

  static Set<T> _toggleExclusive<T>(Set<T> current, T value, T noneValue) {
    if (current.contains(value)) return {...current}..remove(value);
    if (value == noneValue) return {noneValue};
    return {...current, value}..remove(noneValue);
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

  Future<void> next() async {
    reject.value = null;
    if (!canAdvance) return;

    // docs/05 §3: evaluate gates the moment conditions are known. A blocking gate means the flow
    // ends here — we do not collect consent for data we will not use, and no plan is generated.
    if (step.value == OnboardingStep.conditions) {
      final fired = ValidateOnboarding.blockingGates(conditions.toSet());
      if (fired.isNotEmpty) {
        gates.assignAll(fired);
        outcome.value = GateOutcome.blocked;
        goingForward = true;
        step.value = OnboardingStep.gate;
        return;
      }
    }

    // docs/05 §4 — evaluated in severity order. An eating-disorder disclosure outranks everything
    // else: it must never be answered with a coach-unlock or a referral for a different reason.
    if (step.value == OnboardingStep.screening) {
      final routed = switch ((
        screenedEatingDisorder.value,
        screenedInsulinOrKidney.value,
        screenedSpecialDiet.value,
      )) {
        (true, _, _) => GateOutcome.eatingDisorderSupport,
        (_, true, _) => GateOutcome.blocked,
        (_, _, true) => GateOutcome.clinicianRequired,
        _ => null,
      };
      if (routed != null) {
        outcome.value = routed;
        goingForward = true;
        step.value = OnboardingStep.gate;
        return;
      }
    }

    final i = _orderedSteps.indexOf(step.value);
    if (i >= 0 && i < _orderedSteps.length - 1) {
      goingForward = true;
      step.value = _orderedSteps[i + 1];
      return;
    }
    // Last step: persist. Until this call succeeds nothing the user typed exists anywhere, so the
    // flow must not advance on an optimistic guess.
    if (step.value == OnboardingStep.consent) await submit();
  }

  /// `POST /profile/onboarding` (docs/09 §4).
  ///
  /// The server re-runs every docs/05 §3 gate and its answer wins — if it returns a gate the client
  /// did not catch, we route to the gate screen rather than continuing to a plan.
  Future<void> submit() async {
    if (submitting.value) return;

    final body = buildSubmission();
    if (body == null) {
      // `next()` gates every required field long before this, so a null here is a bug in the flow
      // rather than a user error — but a silent `return` makes it a button that does nothing, which
      // is the worst way to report anything (D-91).
      submitError.value = missingFieldMessage;
      return;
    }

    submitting.value = true;
    submitError.value = null;

    final result = await _profiles.submitOnboarding(body);

    submitting.value = false;
    result.fold((failure) => submitError.value = failure.userMessage, (ok) {
      if (ok.isGated) {
        outcome.value = _outcomeFor(ok.gates);
        goingForward = true;
        step.value = OnboardingStep.gate;
        return;
      }
      step.value = OnboardingStep.done;
      unawaited(prepare());
    });
  }

  /// The "preparing your plan" step (D-75).
  ///
  /// It generates the first plan for real rather than counting to three. Nothing else in the app
  /// called `POST /plans/generate`, so every new user landed on an empty Home with a "Create my
  /// plan" button — the wait was going to happen anyway, and this is the honest place for it.
  ///
  /// A failure does NOT trap them here. Home renders the server's message and offers the button, so
  /// the worst case is the screen they used to get every time.
  Future<void> prepare() async {
    if (preparing.value) return;
    preparing.value = true;

    final startedAt = DateTime.now();
    final result = await _plans.generate();
    result.fold((failure) => planError.value = failure.userMessage, (_) {});

    final remaining = preparingMinimum - DateTime.now().difference(startedAt);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    preparing.value = false;
    // Flips RootGate to the shell. The server is the authority on `onboarding_required`; this is
    // the optimistic local half.
    await _session.markOnboardingComplete();
  }

  /// docs/05 §4 severity order, same as the client-side routing: an eating-disorder disclosure
  /// outranks everything, and anything merely clinician-gated is not a hard block.
  static GateOutcome _outcomeFor(List<String> gates) {
    if (gates.contains('eating_disorder')) return GateOutcome.eatingDisorderSupport;

    const clinicianOnly = {'special_diet', 'age_70_plus', 'bmi_40_plus'};
    if (gates.every(clinicianOnly.contains)) return GateOutcome.clinicianRequired;

    return GateOutcome.blocked;
  }

  /// Set by the UI, so the controller stays free of copy (CLAUDE.md rule 5). Shown when
  /// [buildSubmission] returns null.
  String missingFieldMessage = '';

  /// Null when a required field is still unset — `next()` gates every one of these long before the
  /// consent step, so a null here means a bug, not a user error.
  OnboardingSubmission? buildSubmission() {
    final age = ageYears.value;
    final height = heightCm.value;
    final weight = weightKg.value;
    final sex = sexAtBirth.value;
    final declared = goalDeclared.value;
    final g = declared?.engineGoal;
    final act = activity.value;
    final food = foodPreference.value;
    final meals = mealCount.value;
    final life = lifestyle.value;

    if (age == null ||
        height == null ||
        weight == null ||
        sex == null ||
        g == null ||
        act == null ||
        food == null ||
        meals == null ||
        life == null) {
      return null;
    }

    return OnboardingSubmission(
      ageYears: age,
      heightCm: height,
      weightKg: weight,
      goalWeightKg: goalWeightKg.value,
      sexAtBirth: sex,
      goal: g,
      goalDeclared: declared,
      activity: act,
      foodPreference: food,
      mealCount: meals,
      lifestyle: life,
      budgetTier: budgetTier,
      budgetMonthlyInr: budgetMonthlyInr.value,
      conditions: conditions.toSet(),
      allergies: allergies.toSet(),
      consentGranted: consentGranted.value,
      screenedSpecialDiet: screenedSpecialDiet.value,
      screenedInsulinOrKidney: screenedInsulinOrKidney.value,
      screenedEatingDisorder: screenedEatingDisorder.value,
      name: name.value.trim(),
      wakeTime: wakeTime.value,
      sleepTime: sleepTime.value,
      sleepHours: sleepHours,
      breakfastTime: breakfastTime.value,
      lunchTime: lunchTime.value,
      eveningSnackTime: eveningSnackTime.value,
      dinnerTime: dinnerTime.value,
      foodDislikes: foodDislikes.value.trim(),
      medications: medications.value.trim(),
      digestiveSymptoms: digestiveSymptoms.toSet(),
      injuries: injuries.toSet(),
      // FR-1.3: never sent for a user we did not ask. The server drops them too, but the app must
      // not put a health field it has no reason to hold on the wire in the first place.
      menstrualRegularity: asksFemaleHealth ? menstrualRegularity.value : null,
      pregnantOrBreastfeeding: asksFemaleHealth ? pregnantOrBreastfeeding.value : null,
      heavyBleedingOrPain: asksFemaleHealth ? heavyBleedingOrPain.value : null,
      hormonalMedication: asksFemaleHealth ? hormonalMedication.value : null,
    );
  }

  void back() {
    reject.value = null;
    goingForward = false;
    // docs/05 §3: ALL THREE gate outcomes are dead ends. Returning to the form here would let a
    // user flip the answer that triggered the gate and walk straight past it — the exact bypass the
    // gates exist to prevent. Previously only the eating-disorder branch was terminal, so a
    // blocking condition and a clinician gate were both escapable via this path and the back arrow.
    if (step.value == OnboardingStep.gate) return;
    if (step.value == OnboardingStep.done) {
      step.value = OnboardingStep.consent;
      return;
    }
    final i = _orderedSteps.indexOf(step.value);
    if (i > 0) step.value = _orderedSteps[i - 1];
  }
}
