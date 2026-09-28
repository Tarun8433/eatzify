import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/form_fields.dart';
import 'package:health_pro/core/widgets/step_progress.dart';
import 'package:health_pro/core/widgets/wheel_picker.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profession.dart';
import 'package:health_pro/domain/usecases/validate_onboarding.dart';
import 'package:health_pro/presentation/features/coach/partner_invite_sheet.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/choice_tile.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/goal_result.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:lottie/lottie.dart';

/// The onboarding flow. docs/14 §6, requirements docs/02 FR-1.
///
/// One screen per decision, a visible step count, and no progress bar that lies about how much is
/// left. The gate screen is reachable from the conditions step and is a dead end by design —
/// docs/05 §3: no plan is generated, and a partial plan would be worse than none.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(OnboardingController())
      // The controller holds no copy of its own (rule 5); this is the one string it needs and the
      // page is where l10n lives.
      ..missingFieldMessage = AppLocalizations.of(context).onboardingIncomplete;
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final step = c.step.value;
          if (step == OnboardingStep.gate) return _GateView(controller: c);
          if (step == OnboardingStep.done) return const _DoneView();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: c),
              Expanded(
                child: _StepScrollView(
                  step: step,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Steps slide, they do not swap (D-103). Thirteen screens replacing each
                      // other instantly gave the funnel no sense of going anywhere — the teardown
                      // calls this its biggest single opening, and it is one widget for all
                      // thirteen. Forward enters from the right, back from the left, so the motion
                      // itself says which way the flow just moved.
                      _StepTransition(
                        step: step,
                        forward: c.goingForward,
                        child: switch (step) {
                          OnboardingStep.basics => _BasicsStep(controller: c),
                          OnboardingStep.result => _ResultStep(controller: c),
                          OnboardingStep.goal => _GoalStep(controller: c),
                          OnboardingStep.activity => _ActivityStep(controller: c),
                          OnboardingStep.dailyRoutine => _DailyRoutineStep(controller: c),
                          OnboardingStep.conditions => _ConditionsStep(controller: c),
                          OnboardingStep.health => _HealthStep(controller: c),
                          OnboardingStep.womensHealth => _WomensHealthStep(controller: c),
                          OnboardingStep.screening => _ScreeningStep(controller: c),
                          OnboardingStep.diet => _DietStep(controller: c),
                          OnboardingStep.mealTimings => _MealTimingsStep(controller: c),
                          OnboardingStep.routine => _RoutineStep(controller: c),
                          OnboardingStep.summary => _SummaryStep(controller: c),
                          OnboardingStep.consent => _ConsentStep(controller: c),
                          OnboardingStep.gate || OnboardingStep.done => const SizedBox.shrink(),
                        },
                      ),
                      // docs/05 §7: the disclaimer belongs in the onboarding flow. It scrolls with
                      // the content rather than sitting in the fixed footer — at 200 % on a phone
                      // it is tall enough to squeeze the body out of the viewport entirely (D-90).
                      const SizedBox(height: AppSpacing.xl),
                      const _Disclaimer(),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
              _Footer(controller: c, l: l),
            ],
          );
        }),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (controller.stepNumber > 1)
            IconButton(
              onPressed: controller.back,
              icon: const Icon(Icons.arrow_back),
              tooltip: l.onboardingBack,
            ),
          // A dash per step, not "Step 9 of 11" — counting a twelve-step form out loud is what
          // made it feel like paperwork (D-88).
          Expanded(
            child: StepProgress(step: controller.stepNumber, total: controller.totalSteps),
          ),
          const SizedBox(width: AppSpacing.lg),
          // The way out of the wrong account. RootGate sends any session flagged
          // `onboarding_required` straight here, so this can be the FIRST screen a returning user
          // sees — a number typed one digit wrong, a shared phone, a server that has not caught up.
          // Without it the form is a trap: no back, no shell, no route to sign in as somebody else.
          // Offered on step one only, where there are no answers to lose by leaving.
          if (controller.stepNumber == 1)
            TextButton(
              onPressed: () => Get.find<SessionController>().signOut(),
              child: Text(l.signOut),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.l});
  final OnboardingController controller;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Obx(() {
        final reject = controller.reject.value;
        final submitError = controller.submitError.value;
        final isLast = controller.step.value == OnboardingStep.consent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rule 7: the server's own words. It was being STORED and never drawn, so a failed
            // submit looked like a button that did nothing at all (D-91).
            if (submitError != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  submitError,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
            if (reject != null) ...[
              // FR-1.2 requires this to read plainly and without blame. The copy lives in l10n.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  reject.label(l),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
            FilledButton(
              onPressed: controller.canAdvance && !controller.submitting.value
                  ? controller.next
                  : null,
              child: controller.submitting.value
                  // Submitting takes a network round trip. Without this the button looks inert for
                  // the whole of it, which is the same thing a broken button looks like.
                  ? const SizedBox.square(
                      dimension: AppSpacing.lg,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  // The label stays centred and the arrow sits at the trailing edge, as the
                  // reference draws it — a Row would centre the pair and leave the text off-centre.
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        // Sizes the Stack to the button rather than to the label — without it
                        // `right: 0` is the right edge of the WORD, and the arrow lands against it.
                        const SizedBox(width: double.infinity),
                        Text(isLast ? l.onboardingFinish : l.onboardingNext),
                        if (!isLast)
                          const Positioned(
                            right: 0,
                            child: ExcludeSemantics(child: Icon(Icons.arrow_forward)),
                          ),
                      ],
                    ),
            ),
          ],
        );
      }),
    );
  }
}

/// The question, centred and large (D-104).
///
/// It was left-aligned at `headlineMedium` and read as a section header on a form. The reference
/// puts the question in the middle of the screen at display weight, because that is what the
/// screen is FOR — everything under it is the answer. Centring it is what turns a form field with
/// a label into a question being asked.
class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, {this.subtitle, this.icon});
  final String title;
  final String? subtitle;

  /// A tinted disc at the leading edge, which also turns the question LEFT-aligned (D-110).
  ///
  /// The centred question is right for a screen that asks one thing. It is wrong for a screen that
  /// asks one thing and then lists sixteen answers down the left margin: the heading floats free of
  /// the column it introduces. A disc and a left edge tie them together, and the steps with art
  /// (`_StepHero`) already read that way.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aligned = icon != null;

    final words = Column(
      crossAxisAlignment: aligned ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: aligned ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: aligned ? scheme.primary : null,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            textAlign: aligned ? TextAlign.start : TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: aligned
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    height: AppSizes.ringSmall,
                    width: AppSizes.ringSmall,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: words),
              ],
            )
          : words,
    );
  }
}

/// A step header with art: the title beside a picture that runs off the corner (D-106, D-109).
///
/// Steps that carry art do not use `_StepTitle`'s centred question — a centred line under
/// something hanging off the right edge reads as misaligned, and the reference sets the two side
/// by side deliberately: the art says what the screen is about, the words start at the margin
/// where reading starts. Steps without art keep the centre, or a leading disc (`_StepTitle.icon`).
///
/// The image is DECORATION and is excluded from semantics. It says nothing the title does not.
/// A step's header with a glyph in a tinted disc instead of a photograph (D-112).
///
/// The middle setting between `_StepTitle`'s bare centred question and `_StepHero`'s full-bleed
/// cut-out. Some steps have a subject but no picture that suits them — the screening questions
/// being the clearest case: a cheerful illustration beside "have you been treated for an eating
/// disorder" is the wrong register, and a bare sentence gives the screen no head at all.
///
/// Left-aligned, unlike `_StepTitle`, for the reason `_StepHero` gives: a centred line under
/// something sitting off to one side reads as misaligned.
class _StepGlyphTitle extends StatelessWidget {
  const _StepGlyphTitle({required this.title, required this.subtitle, required this.glyph});

  final String title;
  final String subtitle;
  final IconData glyph;

  /// The disc's diameter, and it is deliberately modest: at 72 with a 16 pt gap the title column
  /// was 254 pt and "Three quick questions" broke after "quick". The glyph is decoration; the
  /// words are the screen.
  static const _disc = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.displayLarge?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    // Past this scale the words need the whole width, and the disc is decoration — the first thing
    // that can be given up for them (rule 12). Same threshold every other header here uses.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: stacked
          ? words
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    height: _disc,
                    width: _disc,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      glyph,
                      size: AppSpacing.xxl,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: words),
              ],
            ),
    );
  }
}

class _StepHero extends StatelessWidget {
  const _StepHero({required this.title, required this.subtitle, required this.art, this.glyph});

  final String title;
  final String subtitle;

  /// An `AppAssets` path. Every one of these is a cut-out with a transparent left edge — see
  /// [_artWidthFraction].
  final String art;

  /// The small mark beside the title — a sprig on the basics step, a sun on the routine one. An
  /// icon rather than an emoji (ui-standards): it takes the theme colour and scales with the text.
  final IconData? glyph;

  /// The art's share of the width, and the text's.
  ///
  /// They add up to more than one, and that is deliberate: the left fifth of the PNG is
  /// transparent — a scatter of leaves around an empty corner — so the two BOXES overlap while
  /// nothing drawn in them does. Sized so they do not overlap, the title got 48 % of a phone and
  /// "About you" wrapped onto two lines at display size.
  static const _artWidthFraction = 0.62;
  static const _textWidthFraction = 0.62;

  /// How far past the page's own padding the art runs, so it is cut by the screen edge rather
  /// than stopping short of it. That cut is what makes it read as a photograph the screen was
  /// cropped from instead of a sticker placed on it.
  static const _bleed = -(AppSpacing.xxl + AppSpacing.xl);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                style: theme.textTheme.displayLarge?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            if (glyph != null) ...[
              const SizedBox(width: AppSpacing.sm),
              ExcludeSemantics(
                child: Icon(glyph, size: AppSpacing.xl, color: theme.colorScheme.secondary),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    // Past this scale the title needs the whole width, and a picture is the first thing that can
    // be given up for it (rule 12). Same threshold the Home hero stacks at.
    if (MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: words,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        // The art is meant to leave the layout on two sides.
        clipBehavior: Clip.none,
        children: [
          Positioned(
            // Above the content it sits beside, so the picture is cut by the top of the page the
            // way the reference cuts it, rather than starting neatly under the progress bar.
            top: -AppSpacing.xl,
            right: _bleed,
            width: constraints.maxWidth * _artWidthFraction,
            // ponytail: the reference sets a tinted circle behind the routine art. A circle behind
            // a 3:2 picture needs an AspectRatio wrapper and shrinks the art to fit inside it —
            // add it if the art ever changes to something that floats on the page without one.
            child: ExcludeSemantics(
              child: Image(image: AssetImage(art), fit: BoxFit.contain),
            ),
          ),
          // Full width, so the Stack is too — sized to the text column instead, `right: _bleed`
          // was measured from the middle of the page and the art never reached the edge.
          SizedBox(
            width: constraints.maxWidth,
            child: Padding(
              // The column is narrowed by PADDING, not by a nested SizedBox: this one is handed
              // tight constraints, and a SizedBox inside tight constraints silently keeps the
              // parent's width — the title ran the full page and straight under the bowl.
              //
              // The bottom inset also keeps the first field BELOW the art rather than beside it,
              // so the first thing the user touches is not half-covered.
              padding: EdgeInsets.only(
                top: AppSpacing.xxl,
                bottom: AppSpacing.xl,
                right: constraints.maxWidth * (1 - _textWidthFraction),
              ),
              child: words,
            ),
          ),
        ],
      ),
    );
  }
}

class _BasicsStep extends StatelessWidget {
  const _BasicsStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHero(
          title: l.onboardingBasicsTitle,
          subtitle: l.onboardingBasicsSubtitle,
          art: AppAssets.basicsHero,
          glyph: Icons.eco,
        ),
        FreeTextField(
          // Prefilled from the controller (D-117): a field is only blank the first time. Coming back
          // to a step must show what was typed, not invite it to be typed again.
          initial: controller.name.value,
          label: l.onboardingNameLabel,
          helperText: l.onboardingNameHint,
          icon: Icons.person_outline,
          maxLength: 80,
          onChanged: (v) => controller.name.value = v,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProfessionQuestion(controller: controller),
        const SizedBox(height: AppSpacing.lg),
        // Paired (D-90). Two fit a phone side by side, and the weights especially belong together:
        // the gap between current and target is the thing being decided, and it is only visible
        // when both numbers are in view.
        _NumberPair(
          left: _NumberSpec(
            label: l.fieldAge,
            icon: Icons.calendar_today_outlined,
            // Horizontal: the reference draws age as a carousel, height as a wheel.
            picker: NumberPickerConfig(
              min: 18,
              max: 99,
              // 25, not the range's midpoint of 59: the wheel opens on a plausible first answer.
              opensAt: 25,
              horizontal: true,
              caption: l.pickerYearsOld,
            ),
            pickerWhy: l.onboardingAgeWhy,
            initial: () => controller.ageYears.value,
            onChanged: (t, {silent = false}) => controller.setAge(int.tryParse(t), silent: silent),
          ),
          right: _NumberSpec(
            // docs/03 §2 types height_cm as an int. At 6.25 kcal per cm in Mifflin, half a
            // centimetre moves BMR by ~3 kcal — below the noise floor of self-reported activity.
            label: l.fieldHeightCm,
            icon: Icons.straighten,
            picker: const NumberPickerConfig(min: 120, max: 220, suffix: 'cm', feetInches: true),
            pickerWhy: l.onboardingHeightWhy,
            initial: () => controller.heightCm.value,
            onChanged: (t, {silent = false}) =>
                controller.setHeight(int.tryParse(t), silent: silent),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Between height and the weights (D-76): it is the last thing the calorie equation needs,
        // and the guidance below the weights depends on it.
        Text(
          l.fieldSexAtBirth,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l.sexAtBirthWhy, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => Wrap(
            children: [
              for (final (i, sex) in SexAtBirth.values.indexed)
                StaggeredIn(
                  index: i,
                  child: ChoiceTile(
                    icon: sex.icon,
                    label: sex.label(l),
                    selected: controller.sexAtBirth.value == sex,
                    onTap: () => controller.sexAtBirth.value = sex,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NumberPair(
          left: _NumberSpec(
            label: l.fieldWeightShort,
            icon: Icons.monitor_weight_outlined,
            decimal: true,
            // Half a kilo ON THE RULER: people know their weight to that, and not to a gram. A
            // typed 70.3 is still accepted — see NumberPickerConfig.step.
            picker: NumberPickerConfig(
              min: 30,
              max: 250,
              step: 0.5,
              suffix: 'kg',
              // The reference draws weight as a horizontal ruler with a kg ⇄ lb toggle, opening
              // on a plausible reading rather than the range's 140 kg midpoint.
              ruler: true,
              kgPounds: true,
              opensAt: 70,
              flag: l.pickerSelectedWeight,
            ),
            pickerWhy: l.onboardingWeightWhy,
            pickerNote: l.onboardingWeightTrack,
            initial: () => controller.weightKg.value,
            onChanged: (t, {silent = false}) =>
                controller.setWeight(double.tryParse(t), silent: silent),
          ),
          right: _NumberSpec(
            // Optional on purpose: plenty of people start without a number in mind, and demanding
            // one invites a made-up answer that then shapes the plan.
            label: l.fieldGoalWeightShort,
            icon: Icons.track_changes,
            decimal: true,
            // The same ruler as the current weight beside it — two identical questions rendered
            // by two different controls would read as two different questions.
            picker: NumberPickerConfig(
              min: 30,
              max: 250,
              step: 0.5,
              suffix: 'kg',
              ruler: true,
              kgPounds: true,
              opensAt: 70,
              flag: l.pickerSelectedWeight,
            ),
            // The BMI-derived band as a SUGGESTION on the sheet (docs/05 §6: informs the choice,
            // never makes it). Computed by the same domain helper the form validates against, so
            // the card and the rules cannot disagree — and at open time, so it sees the height
            // entered a moment ago.
            pickerHint: () {
              final range = controller.healthyWeightRange;
              return range == null
                  ? null
                  : l.pickerHealthyHint(
                      range.low.toStringAsFixed(1),
                      range.high.toStringAsFixed(1),
                    );
            },
            initial: () => controller.goalWeightKg.value,
            onChanged: (t, {silent = false}) =>
                controller.setGoalWeight(double.tryParse(t), silent: silent),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Below the weights, because it is what the target answer depends on.
        _HealthyWeightNote(controller: controller),
      ],
    );
  }
}

/// The healthy band for this height, and the current BMI, shown once age, gender, height and
/// weight are all entered (D-76).
///
/// A range and a bare number — no band label, no colour, no "you are Obese". docs/05 §6 forbids a
/// judgemental status, and the old build put exactly that on its profile screen. The target field
/// below is never auto-filled from this: it informs the choice, it does not make it.
class _HealthyWeightNote extends StatelessWidget {
  const _HealthyWeightNote({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final range = controller.healthyWeightRange;
      final bmi = controller.currentBmi;

      if (range == null || bmi == null) {
        return HintCard(icon: Icons.lightbulb_outline, text: l.onboardingHealthyWeightHint);
      }

      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.onboardingHealthyWeightTitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.onboardingHealthyWeightRange(
                range.low.toStringAsFixed(1),
                range.high.toStringAsFixed(1),
              ),
              style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.onboardingHealthyWeightBody(bmi.toStringAsFixed(1)),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    });
  }
}

/// The gap between the two weights the user just typed, drawn (D-101).
///
/// The only screen in the funnel that gives something back rather than asking. It states the
/// difference and nothing else: no rate, no date, no "you will reach this by" — the app has not
/// been told the goal yet, the engine has not run, and CLAUDE.md rule 2 puts every target on the
/// server. A projection here would be the client inventing a clinical claim.
///
/// Shown even when the two weights are equal, because "hold your weight" is a real answer and a
/// screen that vanished on it would make the funnel's step count jump.
class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final start = controller.weightKg.value;
      final target = controller.goalWeightKg.value ?? start;
      final height = controller.heightCm.value;
      // Answered here rather than in the view, because it is a domain question: the band comes
      // from the same bound `ValidateOnboarding.goalWeightKg` rejects on, so what the card says
      // and what the form enforces cannot disagree (rule 2 — no clinical arithmetic in a widget).
      final band = height == null ? null : ValidateOnboarding.healthyWeightRangeKg(height);

      return GoalResultView(
        startKg: start,
        targetKg: target,
        inHealthyRange: (target == null || band == null)
            ? null
            : target >= band.low && target <= band.high,
        // The note names the numbers when they are known — same helper, same silence rules.
        healthyLowKg: band?.low,
        healthyHighKg: band?.high,
      );
    });
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(l.onboardingGoalTitle),
        Obx(
          () => Column(
            children: [
              // The seven the user recognises. The engine's three are derived — see GoalDeclared.
              for (final (i, g) in GoalDeclared.values.indexed)
                StaggeredIn(
                  index: i,
                  child: ChoiceTile(
                    label: g.label(l),
                    icon: g.icon,
                    selected: controller.goalDeclared.value == g,
                    onTap: () => controller.goalDeclared.value = g,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityStep extends StatelessWidget {
  const _ActivityStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(l.onboardingActivityTitle, subtitle: l.onboardingActivitySubtitle),
        Obx(
          () => Column(
            children: [
              for (final (i, a) in ActivityLevel.values.indexed)
                StaggeredIn(
                  index: i,
                  child: ChoiceTile(
                    label: a.label(l),
                    icon: a.icon,
                    description: a.description(l),
                    selected: controller.activity.value == a,
                    onTap: () => controller.activity.value = a,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConditionsStep extends StatelessWidget {
  const _ConditionsStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          l.onboardingConditionsTitle,
          subtitle: l.onboardingConditionsSubtitle,
          icon: Icons.monitor_heart_outlined,
        ),
        // Said once, before the first tap (D-110). Every other step on the funnel takes one answer
        // and moves on, so a user who has learned that pattern taps "Type 2 diabetes" and waits for
        // the screen to advance. Nothing about a list of rows says it will not.
        HintCard(icon: Icons.eco, text: l.onboardingMultiSelectHint),
        const SizedBox(height: AppSpacing.lg),
        Obx(() {
          // FR-1.3: pregnancy and lactation are offered only to women aged 18-50. Outside that
          // band they are health fields with no clinical purpose, which docs/13 forbids collecting.
          //
          // PCOS is female-only for the same reason and a wider one: Polycystic OVARY Syndrome is
          // not a condition a man can have, so offering it to one is both a health field with no
          // purpose and a question that reads as the app not having listened to the answer before.
          // Gated on sex rather than the 18–50 band — PCOS does not stop at fifty.
          final hidden = <Condition>{
            if (!controller.asksPregnancyStatus) ...{Condition.pregnancy, Condition.lactation},
            if (!controller.asksFemaleHealth) Condition.pcos,
          };
          final shown = Condition.values.where((c) => !hidden.contains(c)).toList();
          // Rows, not chips — which reverses D-88 for this step alone (D-110). D-88 was right that
          // sixteen bare full-width rows is a scroll and sixteen chips is a glance. It is wrong
          // once each row carries a glyph: a chip can hold a label and nothing else, and this is
          // the one list in the funnel where the answers are medical terms that a user scans for
          // their own rather than reads end to end. The scroll is the price of that.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in shown.indexed)
                StaggeredIn(
                  index: i,
                  child: ChoiceTile(
                    label: c.label(l),
                    icon: c.icon,
                    multiSelect: true,
                    selected: controller.conditions.contains(c),
                    onTap: () => controller.toggleCondition(c),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.lg),
        // docs/13, said where it is actually being asked for. The disclaimer card below is about
        // what the app is NOT; this is about what happens to what the user just typed, and the one
        // screen that collects diagnoses is where it earns its line.
        _PrivacyNote(text: l.copyHealthDataPrivate),
      ],
    );
  }
}

/// What happens to a health answer, said on the screen that asks for it (docs/13, D-110, D-111).
///
/// A card rather than the line it started as: it appears under two different lists of diagnoses and
/// symptoms, and the same promise should not look like a caption on one screen and a card on the
/// next. Green rather than the disclaimer's warm tone — this is a reassurance, not a warning, and
/// the two must not be confusable.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => HintCard(icon: Icons.lock_outline, text: text);
}

/// A labelled group of choices, used by the steps that ask more than one thing.
class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.values,
    required this.labelOf,
    required this.isSelected,
    required this.onTap,
    this.hint,
    this.iconOf,
    this.descriptionOf,
    this.headingIcon,
    this.columns = 1,
    this.multiSelect = false,
  });

  final String label;
  final String? hint;
  final List<T> values;
  final String Function(T) labelOf;

  /// A glyph per option (D-110, D-111). Null for the whole group, or null for one value, both mean
  /// no disc — see `ConditionIcon` for why `none` never gets one.
  final IconData? Function(T)? iconOf;

  /// A line under the label (D-112). For a list where the label alone does not answer "is that
  /// me?" — five diets, three of which are words not every user knows.
  final String Function(T)? descriptionOf;

  /// A disc beside the group's own heading, matching `_StepTitle.icon`. For a second question on a
  /// screen that already has one: without it the two headings are the same weight and the page
  /// reads as one long list with a gap in it.
  final IconData? headingIcon;

  /// Lay the options out two-up (D-112). For short labels with no description, where one column of
  /// eleven allergies is a scroll and two is a glance. A label too long for its cell WRAPS — none
  /// of these are ellipsised — and at a large text scale the group falls back to one column.
  final int columns;

  final bool Function(T) isSelected;
  final void Function(T) onTap;
  final bool multiSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // A multi-select group says so unless the caller has something more specific to say (D-111).
    // Defaulted here rather than passed at eight call sites: a list that takes several answers and
    // does not say so is the same misunderstanding on every one of them.
    final sub = hint ?? (multiSelect ? l.onboardingSelectAllHint : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupHeading(label: label, hint: sub, icon: headingIcon),
        const SizedBox(height: AppSpacing.md),
        _options(context),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _options(BuildContext context) {
    // Options land one after another rather than all at once (D-103). This helper backs most
    // of the funnel, so one wrapper here staggers the majority of the thirteen steps.
    final tiles = [
      for (final (i, v) in values.indexed)
        StaggeredIn(
          index: i,
          child: ChoiceTile(
            label: labelOf(v),
            description: descriptionOf?.call(v),
            icon: iconOf?.call(v),
            compact: columns > 1,
            multiSelect: multiSelect,
            selected: isSelected(v),
            onTap: () => onTap(v),
          ),
        ),
    ];

    if (columns == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tiles);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // One column once the text is large: a two-word label in half a phone at 200 % is three
        // wrapped lines in a cell built for one (rule 12).
        if (MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tiles);
        }
        // Rows of `columns`, not a Wrap. A Wrap lets each cell keep its own height, so one label
        // that wraps onto two lines leaves its neighbour floating with a gap beneath it —
        // `IntrinsicHeight` makes the pair agree, and `Expanded` splits the width without any
        // arithmetic that a text scale could invalidate.
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: AppSpacing.sm),
                      // The last row can be short. An empty Expanded holds the column open so a
                      // lone final option does not stretch across the whole width.
                      Expanded(
                        child: i + j < tiles.length ? tiles[i + j] : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The heading over a group of answers: an optional disc, the question, and a line under it.
///
/// Shared by `_ChoiceGroup` and the budget block (D-113), because a screen where the second
/// question is styled differently from the first reads as two screens stitched together.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label, this.hint, this.icon});

  final String label;
  final String? hint;

  /// A disc beside the heading, matching `_StepTitle.icon`. For a second question on a screen that
  /// already has one: without it the two headings are the same weight and the page reads as one
  /// long list with a gap in it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(hint!, style: theme.textTheme.bodySmall),
        ],
      ],
    );

    if (icon == null) return words;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            height: AppSizes.ringSmall,
            width: AppSizes.ringSmall,
            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: words),
      ],
    );
  }
}

class _YesNo extends StatelessWidget {
  const _YesNo({required this.question, required this.value, required this.onChanged, this.number});

  final String question;
  final bool? value;
  final ValueChanged<bool> onChanged;

  /// Its position in the set, 1-based, where the screen asks a numbered few. Decoration for a
  /// screen reader — which is already told "2 of 3" by the list — but it is what tells a sighted
  /// user at a glance that this is a short set and not a page of them.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number != null) ...[
                  ExcludeSemantics(
                    child: Container(
                      height: AppSizes.ringSmall,
                      width: AppSizes.ringSmall,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$number',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Text(question, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
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
      ),
    );
  }
}

/// Wake, bedtime and hours slept. Sleep is the only one that gates the step — see canAdvance.
class _DailyRoutineStep extends StatelessWidget {
  const _DailyRoutineStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHero(
          title: l.onboardingDailyRoutineTitle,
          subtitle: l.onboardingDailyRoutineSubtitle,
          art: AppAssets.themed(AppAssets.routineHero, Theme.of(context).brightness),
          glyph: Icons.wb_sunny_outlined,
        ),
        Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rows rather than fields (D-109). Two times are the whole screen here, and a time
              // already chosen is an answer to read back, not text waiting to be entered.
              TimeField(
                label: l.onboardingWakeTime,
                icon: Icons.wb_sunny_outlined,
                fallback: const TimeOfDay(hour: 7, minute: 0),
                value: controller.wakeTime.value,
                onChanged: (v) => controller.wakeTime.value = v,
              ),
              TimeField(
                label: l.onboardingSleepTime,
                icon: Icons.nightlight_outlined,
                fallback: const TimeOfDay(hour: 23, minute: 0),
                value: controller.sleepTime.value,
                onChanged: (v) => controller.sleepTime.value = v,
              ),
            ],
          ),
        ),
        // Derived, not asked (D-77). Two questions for one fact invites two answers that disagree.
        Obx(() {
          final hours = controller.sleepHours;
          if (hours == null) return const SizedBox.shrink();
          return _SleepSummary(hours: _formatHours(hours));
        }),
      ],
    );
  }

  /// Whole hours read as whole hours: "8", not "8.0". A half shows as "7.5".
  static String _formatHours(double hours) =>
      hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1);
}

/// What the two times add up to, given back before the user has to ask (D-109).
///
/// The screen's only reward for answering: the arithmetic nobody wants to do at 11 pm. It states
/// the number and, under a rule, the range most adults sit in — INFORMATION, not a target. No
/// judgement on the figure above it, whatever it is (docs/05 §6): there is no colour, no "too
/// little", and the plan is not withheld from anyone who sleeps six hours.
class _SleepSummary extends StatelessWidget {
  const _SleepSummary({required this.hours});

  final String hours;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: scheme.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The one filled disc on the screen. It is the answer, not another question.
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: Icon(Icons.bedtime_outlined, size: AppSpacing.xl, color: scheme.onPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.onboardingSleepAbout,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l.onboardingSleepInBed(hours),
                      style: theme.textTheme.headlineMedium?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.secondaryContainer, height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.eco, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l.onboardingSleepAdvice,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Medicines, digestive symptoms and injuries. Everything here is optional — "none of the above" is
/// the common answer and must not cost three taps to give.
class _HealthStep extends StatelessWidget {
  const _HealthStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          l.onboardingHealthTitle,
          subtitle: l.onboardingHealthSubtitle,
          icon: Icons.assignment_outlined,
        ),
        // Marked, not just implied (D-111). The subtitle says the whole step is skippable, but a
        // text box on a health screen reads as something being demanded — and a user who has
        // nothing to type sits looking for what they are supposed to put in it.
        const _OptionalBadge(),
        const SizedBox(height: AppSpacing.sm),
        FreeTextField(
          initial: controller.medications.value,
          label: l.onboardingMedicationsLabel,
          helperText: l.onboardingMedicationsHint,
          icon: Icons.medication_outlined,
          maxLines: 3,
          onChanged: (v) => controller.medications.value = v,
        ),
        const SizedBox(height: AppSpacing.xl),
        Obx(() {
          // Read inside the builder, not in a closure handed to a child — the child's build is not
          // what GetX is observing.
          final symptoms = controller.digestiveSymptoms.toSet();
          final chosenInjuries = controller.injuries.toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChoiceGroup<DigestiveSymptom>(
                label: l.onboardingDigestiveTitle,
                values: DigestiveSymptom.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                isSelected: symptoms.contains,
                onTap: controller.toggleDigestiveSymptom,
                multiSelect: true,
              ),
              _ChoiceGroup<InjuryArea>(
                label: l.onboardingInjuriesTitle,
                values: InjuryArea.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                isSelected: chosenInjuries.contains,
                onTap: controller.toggleInjury,
                multiSelect: true,
              ),
            ],
          );
        }),
        _PrivacyNote(text: l.copyHealthDataPrivate),
      ],
    );
  }
}

/// The small pill that says a field can be left empty.
///
/// A word, not a "(optional)" suffix on the label: the label is what the field is FOR, and hanging
/// a qualifier off it makes the question longer to read for everyone in order to reassure the
/// people who are going to skip it.
class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        AppLocalizations.of(context).onboardingOptional,
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

/// FR-1.3 / docs/13. Reached only when `sex_at_birth == female`; the step is not in this user's
/// flow otherwise, so there is nothing to skip past.
class _WomensHealthStep extends StatelessWidget {
  const _WomensHealthStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(l.onboardingWomensHealthTitle, subtitle: l.onboardingWomensHealthSubtitle),
        Obx(() {
          final regularity = controller.menstrualRegularity.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChoiceGroup<MenstrualRegularity>(
                label: l.onboardingPeriodsQuestion,
                values: MenstrualRegularity.values,
                labelOf: (v) => v.label(l),
                isSelected: (v) => regularity == v,
                onTap: (v) => controller.menstrualRegularity.value = v,
              ),
              // docs/05 §3: pregnancy and lactation are hard gates. Asking here as well as in the
              // condition list is deliberate — someone who did not think of pregnancy as a
              // "medical condition" still gets the question.
              _YesNo(
                question: l.onboardingPregnantQuestion,
                value: controller.pregnantOrBreastfeeding.value,
                onChanged: (v) => controller.pregnantOrBreastfeeding.value = v,
              ),
              _YesNo(
                question: l.onboardingHeavyBleedingQuestion,
                value: controller.heavyBleedingOrPain.value,
                onChanged: (v) => controller.heavyBleedingOrPain.value = v,
              ),
              _YesNo(
                question: l.onboardingHormonalMedicineQuestion,
                value: controller.hormonalMedication.value,
                onChanged: (v) => controller.hormonalMedication.value = v,
              ),
            ],
          );
        }),
      ],
    );
  }
}

/// When the user actually eats. docs/04 §12 shifts meal windows for night-shift workers off a
/// declared time — this is where that time comes from.
class _MealTimingsStep extends StatelessWidget {
  const _MealTimingsStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The routine step's header, on the routine step's other half (D-113). There is no art for
        // this one, so the glyph disc stands in — the same middle setting the screening step uses.
        _StepGlyphTitle(
          title: l.onboardingMealTimingsTitle,
          subtitle: l.onboardingMealTimingsSubtitle,
          glyph: Icons.restaurant_outlined,
        ),
        Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rows, not fields — the same treatment wake and bedtime get one step earlier. A
              // meal time is an answer to read back, not text waiting to be entered, and four
              // "Not set" placeholders in a column read as an empty form rather than as four
              // questions. The disc per slot is what lets the eye find dinner without reading
              // three labels first.
              TimeField(
                label: l.onboardingBreakfastTime,
                icon: Icons.free_breakfast_outlined,
                fallback: const TimeOfDay(hour: 8, minute: 30),
                value: controller.breakfastTime.value,
                onChanged: (v) => controller.breakfastTime.value = v,
              ),
              // docs/04 §7's five-to-six pattern puts mid-morning between breakfast and lunch,
              // so the row sits where the meal does.
              if (controller.asksExtraSlots)
                TimeField(
                  label: l.onboardingMidMorningTime,
                  icon: Icons.bakery_dining_outlined,
                  fallback: const TimeOfDay(hour: 11, minute: 0),
                  value: controller.midMorningTime.value,
                  onChanged: (v) => controller.midMorningTime.value = v,
                ),
              TimeField(
                label: l.onboardingLunchTime,
                icon: Icons.lunch_dining_outlined,
                fallback: const TimeOfDay(hour: 13, minute: 30),
                value: controller.lunchTime.value,
                onChanged: (v) => controller.lunchTime.value = v,
              ),

              // docs/04 §7: a three-meal pattern has no snack slot. Asking when someone eats a
              // snack they just said they do not eat is a question with no right answer.
              if (controller.asksSnackTime)
                TimeField(
                  label: l.onboardingEveningSnackTime,
                  icon: Icons.cookie_outlined,
                  fallback: const TimeOfDay(hour: 17, minute: 30),
                  value: controller.eveningSnackTime.value,
                  onChanged: (v) => controller.eveningSnackTime.value = v,
                ),
              TimeField(
                label: l.onboardingDinnerTime,
                icon: Icons.dinner_dining_outlined,
                fallback: const TimeOfDay(hour: 20, minute: 30),
                value: controller.dinnerTime.value,
                onChanged: (v) => controller.dinnerTime.value = v,
              ),
              // docs/04 §7 marks the bedtime occasion OPTIONAL, so it is offered and never
              // required to move on.
              if (controller.asksExtraSlots)
                TimeField(
                  label: l.onboardingBedtimeSnackTime,
                  icon: Icons.nightlight_outlined,
                  fallback: const TimeOfDay(hour: 22, minute: 0),
                  value: controller.bedtimeSnackTime.value,
                  onChanged: (v) => controller.bedtimeSnackTime.value = v,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The monthly food budget, in rupees (D-78).
///
/// The engine's tier is derived from the amount and is not shown: a label like "Premium" invites
/// the reading that a bigger budget buys a better plan, and it does not — it changes which foods
/// the plan reaches for, never how much the person is fed.
class _BudgetSlider extends StatelessWidget {
  const _BudgetSlider({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final rupees = controller.budgetMonthlyInr.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeading(
            label: l.onboardingBudgetLabel,
            hint: l.onboardingBudgetHint,
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          // In a card, like every other answer on the funnel (D-113). It was a heading, a
          // paragraph, a number and a bare slider stacked loose on the page — the only question in
          // the funnel whose answer had no surface under it, and it read as an afterthought
          // appended to the screen rather than the third thing being asked.
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.onboardingBudgetPerMonth(Rupees.format(rupees)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                Slider(
                  value: rupees.toDouble(),
                  min: BudgetRange.minInr.toDouble(),
                  max: BudgetRange.maxInr.toDouble(),
                  divisions: (BudgetRange.maxInr - BudgetRange.minInr) ~/ BudgetRange.stepInr,
                  label: Rupees.format(rupees),
                  onChanged: (v) =>
                      controller.budgetMonthlyInr.value = BudgetRange.clamp(v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Rupees.format(BudgetRange.minInr), style: theme.textTheme.bodySmall),
                    Text(Rupees.format(BudgetRange.maxInr), style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      );
    });
  }
}

/// docs/05 §4 — the three screening questions. These catch what the condition list cannot: a
/// clinician-prescribed diet, insulin or kidney medication, and an eating-disorder history.
class _ScreeningStep extends StatelessWidget {
  const _ScreeningStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A glyph rather than a photograph: this is the one step that asks about a diagnosis, and
        // a cheerful cut-out beside "have you been treated for an eating disorder" is the wrong
        // register. The disc still says the screen has a subject (D-112).
        _StepGlyphTitle(
          title: l.screeningTitle,
          subtitle: l.screeningSubtitle,
          glyph: Icons.assignment_turned_in_outlined,
        ),
        Obx(() {
          final q1 = controller.screenedSpecialDiet.value;
          final q2 = controller.screenedInsulinOrKidney.value;
          final q3 = controller.screenedEatingDisorder.value;
          return Column(
            children: [
              _YesNo(
                number: 1,
                question: l.screeningQ1,
                value: q1,
                onChanged: (v) => controller.screenedSpecialDiet.value = v,
              ),
              _YesNo(
                number: 2,
                question: l.screeningQ2,
                value: q2,
                onChanged: (v) => controller.screenedInsulinOrKidney.value = v,
              ),
              _YesNo(
                number: 3,
                question: l.screeningQ3,
                value: q3,
                onChanged: (v) => controller.screenedEatingDisorder.value = v,
              ),
              // The same note the conditions and health steps carry. This screen asks the
              // most sensitive of the three questions, and it was the one that did not say
              // what happens to the answer.
              _PrivacyNote(text: l.copyHealthDataPrivate),
            ],
          );
        }),
      ],
    );
  }
}

class _DietStep extends StatelessWidget {
  const _DietStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          l.onboardingDietTitle,
          subtitle: l.onboardingDietSubtitle,
          icon: Icons.restaurant_outlined,
        ),
        Obx(() {
          // Read here, inside the builder. A closure passed to a child widget is evaluated in that
          // child's build, which GetX is not observing — the same mistake as the first Obx bug.
          final preference = controller.foodPreference.value;
          final chosenAllergies = controller.allergies.toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChoiceGroup<FoodPreference>(
                // Its own question (D-112). This group was headed with the STEP's subtitle, so
                // "We only plan food you actually eat." was printed twice, once as the promise and
                // once as the question — and neither of them asked anything.
                label: l.onboardingDietQuestion,
                hint: l.onboardingDietQuestionHint,
                values: FoodPreference.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                descriptionOf: (v) => v.description(l),
                isSelected: (v) => preference == v,
                onTap: (v) => controller.foodPreference.value = v,
              ),
              // FR-1.6: FOOD allergies only. The old build collected "Dust, pollution" here, which
              // is clinically useless in a diet app and a health-data liability for no benefit.
              _ChoiceGroup<FoodAllergy>(
                label: l.onboardingAllergiesLabel,
                hint: l.onboardingSelectAllOptional,
                headingIcon: Icons.warning_amber_outlined,
                values: FoodAllergy.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                // Eleven of them, two words each and no description: one column is a scroll on its
                // own, two is a glance.
                columns: 2,
                multiSelect: true,
                isSelected: chosenAllergies.contains,
                onTap: controller.toggleAllergy,
              ),
              HintCard(icon: Icons.verified_user_outlined, text: l.onboardingAllergiesWhy),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        }),
        // Kept apart from allergies on purpose: an allergy is a hard exclusion the plan must never
        // violate, a dislike is a preference it should respect where it can. Merging them either
        // treats a dislike as dangerous or an allergy as negotiable.
        const _OptionalBadge(),
        const SizedBox(height: AppSpacing.sm),
        FreeTextField(
          initial: controller.foodDislikes.value,
          label: l.onboardingDislikesLabel,
          helperText: l.onboardingDislikesHint,
          icon: Icons.no_meals_outlined,
          maxLines: 2,
          onChanged: (v) => controller.foodDislikes.value = v,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l.onboardingDislikesNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _RoutineStep extends StatelessWidget {
  const _RoutineStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          l.onboardingRoutineTitle,
          subtitle: l.onboardingRoutineSubtitle,
          icon: Icons.schedule_outlined,
        ),
        Obx(() {
          final meals = controller.mealCount.value;
          final life = controller.lifestyle.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChoiceGroup<MealCount>(
                label: l.onboardingMealCountLabel,
                // Said out loud, because the question invites one (D-113). Nothing on the screen
                // told the user that five small plates and three large ones get the same day's
                // food, so the count read as a discipline being chosen rather than a shape.
                hint: l.onboardingMealCountHint,
                headingIcon: Icons.restaurant_menu_outlined,
                values: MealCount.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                descriptionOf: (v) => v.description(l),
                isSelected: (v) => meals == v,
                onTap: (v) => controller.mealCount.value = v,
              ),
              _ChoiceGroup<Lifestyle>(
                label: l.onboardingLifestyleLabel,
                hint: l.onboardingLifestyleHint,
                headingIcon: Icons.wb_twilight_outlined,
                values: Lifestyle.values,
                labelOf: (v) => v.label(l),
                iconOf: (v) => v.icon,
                descriptionOf: (v) => v.description(l),
                isSelected: (v) => life == v,
                onTap: (v) => controller.lifestyle.value = v,
              ),
              // A slider in rupees rather than three tiers (D-78): "medium" means nothing without
              // knowing what it is medium of, and everyone knows their own grocery bill.
              _BudgetSlider(controller: controller),
            ],
          );
        }),
      ],
    );
  }
}

/// The bookend to the result step (D-114).
///
/// The same curve, now with the shape of the plan around it: how many meals, what kind of day,
/// when those meals land, and what the food budget is. Every line is the user's own answer read
/// back — no target, no projection, no price. The engine has still not run, and rule 2 keeps its
/// arithmetic on the server.
///
/// It asks nothing, which is the point: twelve screens of being asked things, and one that shows
/// what all of it added up to before the consent checkbox.
class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaggeredIn(
          index: 0,
          child: _StepGlyphTitle(
            title: l.onboardingSummaryTitle,
            subtitle: l.onboardingSummarySubtitle,
            glyph: Icons.fact_check_outlined,
          ),
        ),
        Obx(() {
          final start = controller.weightKg.value;
          final target = controller.goalWeightKg.value ?? start;
          final height = controller.heightCm.value;
          final band = height == null ? null : ValidateOnboarding.healthyWeightRangeKg(height);

          return StaggeredIn(
            index: 1,
            child: GoalResultView(
              startKg: start,
              targetKg: target,
              inHealthyRange: (target == null || band == null)
                  ? null
                  : target >= band.low && target <= band.high,
              healthyLowKg: band?.low,
              healthyHighKg: band?.high,
              // The headline and the encouragement belong to the result step, which is where they
              // land for the first time. Repeated here they would read as the app padding out a
              // recap; the curve is the part worth seeing twice.
              chromeOnly: true,
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xl),
        StaggeredIn(
          index: 2,
          // The reference gives the section its own disc and a line of why (D-106's field-disc
          // language, at section scale).
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: AppSpacing.xl,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.onboardingSummaryShape,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      l.onboardingSummaryShapeSub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(() {
          final meals = controller.mealCount.value;
          final life = controller.lifestyle.value;
          final times = [
            controller.breakfastTime.value,
            controller.lunchTime.value,
            controller.eveningSnackTime.value,
            controller.dinnerTime.value,
          ].map((t) => TimeOfDayText.formatWire(context, t)).nonNulls.toList();

          // Each row opens the step that set it and returns here on the next advance
          // (`editFrom`) — the chevron the rows now earn is the reference's "you can still
          // change this", made true.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meals != null)
                ValueRow(
                  icon: meals.icon,
                  label: l.onboardingSummaryMeals,
                  value: meals.label(l),
                  onTap: () => controller.editFrom(OnboardingStep.routine),
                ),
              if (life != null)
                ValueRow(
                  icon: life.icon,
                  label: l.onboardingLifestyleLabel,
                  value: life.label(l),
                  onTap: () => controller.editFrom(OnboardingStep.routine),
                ),
              if (times.isNotEmpty)
                ValueRow(
                  icon: Icons.schedule_outlined,
                  label: l.onboardingSummaryTimes,
                  // Joined rather than four rows: by this screen the times are one fact about the
                  // shape of a day, not four separate answers to check. Dense: four times at
                  // titleLarge wrap into a two-line billboard on a phone.
                  value: times.join('  ·  '),
                  dense: true,
                  onTap: () => controller.editFrom(OnboardingStep.mealTimings),
                ),
              // The one figure on the screen that is money, and the reason the step exists as far
              // as the user is concerned: they moved a slider two screens ago and never saw the
              // number again. Indian digit grouping, per ui-standards.
              ValueRow(
                icon: Icons.account_balance_wallet_outlined,
                label: l.onboardingBudgetLabel,
                value: l.onboardingBudgetPerMonth(Rupees.format(controller.budgetMonthlyInr.value)),
                onTap: () => controller.editFrom(OnboardingStep.routine),
              ),
            ],
          ).paddingOnly(bottom: AppSpacing.md);
        }),
      ],
    );
  }
}

/// FR-1.7 / docs/13 §3: itemised, opt-in, and never pre-ticked (D-115).
///
/// The last screen before the data leaves the phone, and it used to be a title, a paragraph and a
/// `CheckboxListTile` — the plainest screen in the flow at the moment the user is being asked for
/// the most. The redesign is all weight and no new promise: the art, a consent card the checkbox
/// cannot be missed in, and three things the app already does, said out loud.
class _ConsentStep extends StatelessWidget {
  const _ConsentStep({required this.controller});

  final OnboardingController controller;

  /// The art's share of the width. Wider than the side-by-side heroes because it is centred above
  /// the words rather than beside them — this screen's headline is a question, not a statement,
  /// and the reference sets it under the picture.
  static const _artFraction = 0.78;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On the page's own cream, with no disc and no card behind it. The PNG's ground is
        // transparent and it has to stay that way: a tinted disc here would put a second colour
        // behind the illustration and break the one background the whole flow shares.
        //
        // Dropped entirely past the stacking scale — at 200 % the words need every pixel, and a
        // picture is the first thing that can go (rule 12).
        // The screen arrives in order — picture, question, the thing to tick, the reassurances —
        // rather than all at once. `StaggeredIn` is the same 40 ms ladder the goal options use, so
        // the last screen of the flow moves the way the rest of it does. It returns the child
        // untouched under "reduce motion" (rule 12); nothing here depends on having been seen to
        // move.
        if (MediaQuery.textScalerOf(context).scale(1) < AppSizes.heroStackTextScale)
          StaggeredIn(
            index: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ExcludeSemantics(
                  child: Image.asset(
                    AppAssets.themed(AppAssets.consentHero, Theme.of(context).brightness),
                    width: constraints.maxWidth * _artFraction,
                    // A missing asset must not take the consent screen down with it, and nothing
                    // stands in: the picture says nothing the question does not.
                    errorBuilder: (context, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        StaggeredIn(
          index: 1,
          child: _StepTitle(l.onboardingConsentTitle, subtitle: l.onboardingConsentBody),
        ),
        StaggeredIn(index: 2, child: _ConsentCard(controller: controller)),
        const SizedBox(height: AppSpacing.xl),
        const StaggeredIn(index: 3, child: _ConsentAssurances()),
      ],
    );
  }
}

/// The one thing on the screen that has to be pressed, and it must not read as a form row.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Obx(() {
      final granted = controller.consentGranted.value;

      return Semantics(
        checked: granted,
        // The whole card is the target, so a screen reader is offered one control rather than a
        // checkbox and a separate block of text next to it.
        child: MergeSemantics(
          child: InkWell(
            onTap: () => controller.consentGranted.value = !granted,
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.enter,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: granted ? scheme.secondaryContainer.withValues(alpha: 0.4) : scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.cardLarge),
                border: Border.all(
                  color: granted ? scheme.primary : scheme.outline,
                  width: granted ? 2 : 1,
                ),
                boxShadow: granted ? const [] : AppElevation.card(theme.brightness),
              ),
              child: Row(
                children: [
                  // A real Checkbox, not a tick we drew: consent is the one control in the app
                  // where the platform's own affordance — and its own semantics — is worth more
                  // than a house style.
                  ExcludeSemantics(
                    child: Checkbox(
                      value: granted,
                      onChanged: (v) => controller.consentGranted.value = v ?? false,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card / 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.consentHealthDataLead,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l.consentHealthDataDetail,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ExcludeSemantics(
                    child: Container(
                      height: AppSizes.ringSmall,
                      width: AppSizes.ringSmall,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_done_outlined,
                        size: AppSpacing.xl,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Three things the app already does, said where the decision is being made.
///
/// Not new promises: encryption at rest is what `SecureStore` is for, withdrawal is in the copy
/// above, and deletion is the account screen's existing option. Saying them here is the difference
/// between a policy someone could look up and an answer to the question they are asking right now.
class _ConsentAssurances extends StatelessWidget {
  const _ConsentAssurances();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = [
      (icon: Icons.verified_user_outlined, label: l.consentAssuranceSecure),
      (icon: Icons.tune_rounded, label: l.consentAssuranceControl),
      (icon: Icons.delete_outline_rounded, label: l.consentAssuranceDelete),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0)
              VerticalDivider(width: 1, thickness: 1, color: scheme.outline.withValues(alpha: 0.6)),
            Expanded(
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      height: AppSizes.ringSmall,
                      width: AppSizes.ringSmall,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.icon,
                        size: AppSpacing.xl,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(item.label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// End of onboarding.
///
/// docs/09 POST /plans/generate does not exist yet, so this says so instead of spinning. When E3
/// lands, this screen calls it and shows the plan-ready state (docs/14 §6).
/// The "preparing your plan" screen (D-75).
///
/// It is not a splash: `POST /plans/generate` is running behind it, and the controller moves on to
/// the shell when that finishes — or after [OnboardingController.preparingMinimum], whichever is
/// longer. Nothing here is tappable, because there is nothing to decide.
class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: AppSizes.heroArt * 0.7,
            // Reduced motion is a request, not a preference: the same picture, held still. The
            // animation says "we are working", and a static frame says it too.
            child: AppMotion.enabled(context)
                ? Lottie.asset(AppAssets.preparingPlan, repeat: true)
                : Lottie.asset(AppAssets.preparingPlan, animate: false),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l.onboardingPreparingTitle,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.onboardingPreparingBody,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GateView extends StatelessWidget {
  const _GateView({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final outcome = controller.outcome.value ?? GateOutcome.blocked;
      final body = switch (outcome) {
        GateOutcome.blocked => l.copyBlockingGate,
        GateOutcome.clinicianRequired => l.copyClinicianGate,
        GateOutcome.eatingDisorderSupport => l.copyEdSupport,
      };

      // Scrollable since the disclaimer grew into its four-point card: the gate's message plus
      // the card is legitimately taller than a short phone, and a gate that clips its safety
      // text is worse than one that scrolls (rule 12).
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.gateTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xxl),
            if (outcome == GateOutcome.eatingDisorderSupport)
              // docs/05 §7 flags that the India-appropriate helpline must be verified with a
              // clinician before shipping, so this deliberately does not link anywhere yet.
              FilledButton(onPressed: null, child: Text(l.copyEdSupportFindHelp)),
            // Sign out, NOT "back". docs/05 §3 makes this a dead end, so the only action offered is
            // one that leaves the app — never one that returns to the form, where the answer that
            // caused the gate could simply be changed.
            OutlinedButton(
              // Resolved on tap, not during build — a gate screen must render even where the
              // session is not in the container.
              onPressed: () => Get.find<SessionController>().signOut(),
              child: Text(l.signOut),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Disclaimer(),
          ],
        ),
      );
    });
  }
}

/// docs/05 §7: the disclaimer appears on every plan screen, every export, and the onboarding footer.
/// docs/05 §7's note, on every step of the funnel.
///
/// A card, not a grey paragraph (D-109) — and no longer one paragraph either: the reference
/// breaks the same sentences into four titled points, each with its own glyph, under a headline
/// that says why the note is here at all. A wall of safety text is a wall nobody reads; four
/// scannable lines are the version that gets read. Warm rather than green so it does not read as
/// another of the app's own hints. The words carry the same meaning as the old paragraph — split,
/// not rewritten.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  /// The pointing figure's width — under half the card, so the points keep the reading column.
  static const _artWidth = 156.0;

  /// How much of the card's right edge the points leave clear for him. Less than [_artWidth]:
  /// his left fringe is leaves and air, and the words are allowed to run under those.
  static const _artTextInset = 104.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // HintCard.important's warm palette, kept exactly — the card grew, its tone did not.
        color: AppColors.warmCoral.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: AppColors.warmCoral.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: AppSpacing.xl,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Expanded so the title wraps at 200 % font scale instead of running off the card.
              Expanded(
                child: Text(
                  l.copyImportant,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: l.disclaimerHeadlinePre),
                // The one warm word in a green headline — the reference's emphasis, done with
                // colour the palette already carries.
                TextSpan(
                  text: l.disclaimerHeadlineWord,
                  style: const TextStyle(color: AppColors.warning),
                ),
                TextSpan(text: l.disclaimerHeadlinePost),
              ],
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // A Stack, not a Row: the figure is pinned to the card's bottom-right corner BEHIND
          // the points, so the text keeps one consistent measure instead of being squeezed by
          // however tall the picture happens to be. The inset keeps the words off his dense
          // middle; his leafy left fringe may run under them, which is what "behind" is for.
          // Gone at large font scale (the pair-stacking threshold, D-90): at 200 % the words
          // need the whole card, and rule 12 says the layout gives way, not the text.
          Builder(
            builder: (context) {
              final showArt =
                  MediaQuery.textScalerOf(context).scale(1) < AppSizes.heroStackTextScale;

              return Stack(
                children: [
                  if (showArt)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: _artWidth,
                      child: ExcludeSemantics(child: Image.asset(AppAssets.disclaimerHero)),
                    ),
                  Padding(
                    padding: EdgeInsets.only(right: showArt ? _artTextInset : 0),
                    child: Column(
                      children: [
                        _DisclaimerPoint(
                          icon: Icons.verified_user,
                          tint: scheme.primary,
                          title: l.disclaimerPoint1Title,
                          body: l.disclaimerPoint1Body,
                        ),
                        _DisclaimerPoint(
                          icon: Icons.favorite,
                          tint: AppColors.danger,
                          title: l.disclaimerPoint2Title,
                          body: l.disclaimerPoint2Body,
                        ),
                        _DisclaimerPoint(
                          icon: Icons.medical_services_outlined,
                          tint: AppColors.info,
                          title: l.disclaimerPoint3Title,
                          body: l.disclaimerPoint3Body,
                        ),
                        _DisclaimerPoint(
                          icon: Icons.medication_outlined,
                          tint: AppColors.warning,
                          title: l.disclaimerPoint4Title,
                          body: l.disclaimerPoint4Body,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    height: AppSpacing.xxl,
                    width: AppSpacing.xxl,
                    decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                    child: Icon(Icons.eco, size: AppSpacing.lg, color: scheme.primary),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.disclaimerFooterTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        l.disclaimerFooterBody,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ExcludeSemantics(
                  child: Container(
                    height: AppSpacing.xxl,
                    width: AppSpacing.xxl,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    child: Icon(Icons.favorite, size: AppSpacing.lg, color: scheme.onPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the disclaimer's four points: a tinted disc, a bold claim, one sentence under it.
class _DisclaimerPoint extends StatelessWidget {
  const _DisclaimerPoint({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              height: AppSizes.ringSmall,
              width: AppSizes.ringSmall,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: AppSpacing.xl, color: tint),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One wheel's worth of configuration, so a pair can be described in one place (D-90).
class _NumberSpec {
  const _NumberSpec({
    required this.label,
    required this.picker,
    required this.initial,
    required this.onChanged,
    this.decimal = false,
    this.icon,
    this.pickerWhy,
    this.pickerNote,
    this.pickerHint,
  });

  final String label;
  final NumberPickerConfig picker;
  final bool decimal;

  /// Passed straight to `NumberField.icon` — the tinted disc at the leading edge.
  final IconData? icon;

  /// Passed straight to `NumberField.pickerWhy` — the why-card on the picker sheet.
  final String? pickerWhy;

  /// Passed straight to `NumberField.pickerNote` — the second card under the why-card.
  final String? pickerNote;

  /// Passed straight to `NumberField.pickerHint` — evaluated when the sheet opens, so it can
  /// read answers given after this spec was built.
  final String? Function()? pickerHint;

  /// Read ONCE, to prefill the field. `NumberField` owns its text after that — pushing a value
  /// back in on every rebuild would fight the user mid-keystroke.
  final num? Function() initial;

  /// `silent` while typing, loud on blur — the controller already distinguishes the two, so "72"
  /// is not rejected at "7".
  final void Function(String text, {bool silent}) onChanged;
}

/// Two number fields side by side, stacked when there is not room (D-90, D-95).
///
/// At 200 % font scale a label and its value need the full width, and CLAUDE.md rule 12 says the
/// layout gives way, not the text.
class _NumberPair extends StatelessWidget {
  const _NumberPair({required this.left, required this.right});

  final _NumberSpec left;
  final _NumberSpec right;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured against what two columns actually need, not against the hero's breakpoint: at
        // `heroBreakpoint * 2` the threshold was 600, and a phone's content column is about 330 —
        // so the pair stacked on every device while passing a test on an 800 pt test surface.
        final stacked =
            constraints.maxWidth < AppSizes.wheelColumnMin * 2 + AppSpacing.md ||
            textScale >= AppSizes.heroStackTextScale;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NumberColumn(spec: left),
              const SizedBox(height: AppSpacing.lg),
              _NumberColumn(spec: right),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _NumberColumn(spec: left)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _NumberColumn(spec: right)),
          ],
        );
      },
    );
  }
}

class _NumberColumn extends StatelessWidget {
  const _NumberColumn({required this.spec});

  final _NumberSpec spec;

  @override
  Widget build(BuildContext context) {
    final value = spec.initial();

    return NumberField(
      label: spec.label,
      decimal: spec.decimal,
      icon: spec.icon,
      picker: spec.picker,
      pickerWhy: spec.pickerWhy,
      pickerNote: spec.pickerNote,
      pickerHint: spec.pickerHint,
      initial: value == null ? '' : WheelPicker.formatValue(value),
      onLiveChange: (t) => spec.onChanged(t, silent: true),
      onCommit: spec.onChanged,
    );
  }
}

/// The step's scroll view, rewound to the top whenever the step changes.
///
/// One scroll view serves all thirteen steps, so without this the offset survives the change and
/// the next question opens wherever the last one was left — mid-page, or on the disclaimer.
/// Widget-layer on purpose: the controller cannot hold a ScrollController (no Flutter imports),
/// and every one of the seven step mutations funnels through this one `didUpdateWidget`.
class _StepScrollView extends StatefulWidget {
  const _StepScrollView({required this.step, required this.child});

  final OnboardingStep step;
  final Widget child;

  @override
  State<_StepScrollView> createState() => _StepScrollViewState();
}

class _StepScrollViewState extends State<_StepScrollView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_StepScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jump, not animate: the slide transition is already the motion, and a second animation
    // racing it up the page would read as a glitch.
    if (oldWidget.step != widget.step && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: widget.child,
  );
}

/// Slides one question out and the next one in (D-103).
///
/// `AnimatedSwitcher` keyed on the step, so it fires on a step change and on nothing else — a
/// rebuild from a typed character or a selected chip must not replay the transition.
///
/// The outgoing screen does NOT slide out. Both moving at once needs them laid on top of each
/// other, and these screens are different heights inside a scroll view, so the shorter one
/// stretches to the taller and the whole page jumps. Fading out in place and sliding in is the
/// same read at a fraction of the risk.
class _StepTransition extends StatelessWidget {
  const _StepTransition({required this.step, required this.forward, required this.child});

  final OnboardingStep step;
  final bool forward;
  final Widget child;

  /// How far in from the edge, as a fraction of width. Small: a full-width slide on a form reads
  /// as a page turn and makes the answer feel further away than it is.
  static const _travel = 0.06;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;

    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: AppMotion.enter,
      // Out faster than in, so the next question is never waiting on the last one.
      switchOutCurve: const Interval(0.6, 1, curve: Curves.easeIn),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: Offset(forward ? _travel : -_travel, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(step), child: child),
    );
  }
}

/// "What do you do?", asked once, on the about-you step.
///
/// A self-declaration and nothing more. It decides whether the partner offer is shown and is never
/// sent to the server — docs/13 §4 says collect less, and a field that only picks the next screen
/// has no reason to sit in a health profile. Saying "doctor" here grants nothing: docs/12 §6 makes
/// a verified partner someone whose documents a human has read.
class _ProfessionQuestion extends StatelessWidget {
  const _ProfessionQuestion({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final options = <(Profession, String)>[
      (Profession.none, l.onboardingProfessionNone),
      (Profession.trainer, l.onboardingProfessionTrainer),
      (Profession.nutritionist, l.onboardingProfessionNutritionist),
      (Profession.doctor, l.onboardingProfessionDoctor),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.onboardingProfessionLabel,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(
          () => Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (value, label) in options)
                ChoiceChip(
                  label: Text(label),
                  selected: controller.profession.value == value,
                  onSelected: (_) {
                    controller.profession.value = value;
                    // Immediately, while the answer is still the thing on screen. Held back to a
                    // later step it reads as an unrelated advert; here it reads as a reply.
                    if (value.mayCoach) PartnerInviteSheet.show(context);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
