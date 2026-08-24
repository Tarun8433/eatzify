import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/choice_tile.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The onboarding flow. docs/14 §6, requirements docs/02 FR-1.
///
/// One screen per decision, a visible step count, and no progress bar that lies about how much is
/// left. The gate screen is reachable from the conditions step and is a dead end by design —
/// docs/05 §3: no plan is generated, and a partial plan would be worse than none.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(OnboardingController());
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final step = c.step.value;
          if (step == OnboardingStep.gate) return _GateView(controller: c);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: c),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: switch (step) {
                    OnboardingStep.basics => _BasicsStep(controller: c),
                    OnboardingStep.goal => _GoalStep(controller: c),
                    OnboardingStep.activity => _ActivityStep(controller: c),
                    OnboardingStep.conditions => _ConditionsStep(controller: c),
                    OnboardingStep.consent => _ConsentStep(controller: c),
                    OnboardingStep.gate => const SizedBox.shrink(),
                  },
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
    final theme = Theme.of(context);
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
          Text(
            l.stepOfSteps(controller.stepNumber, controller.totalSteps),
            style: theme.textTheme.bodySmall,
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
        final isLast = controller.step.value == OnboardingStep.consent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              onPressed: controller.canAdvance ? controller.next : null,
              child: Text(isLast ? l.onboardingFinish : l.onboardingNext),
            ),
          ],
        );
      }),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
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
        _StepTitle(l.onboardingBasicsTitle, subtitle: l.onboardingBasicsSubtitle),
        _NumberField(
          label: l.fieldAge,
          helperText: '18 – 99',
          onCommit: (v) => controller.setAge(int.tryParse(v)),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NumberField(
          // docs/03 §2 types height_cm as an int. At 6.25 kcal per cm in Mifflin, half a
          // centimetre moves BMR by ~3 kcal — below the noise floor of self-reported activity.
          label: l.fieldHeightCm,
          helperText: '120 – 220',
          onCommit: (v) => controller.setHeight(int.tryParse(v)),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NumberField(
          label: l.fieldWeightKg,
          decimal: true,
          helperText: '30.0 – 250.0',
          onCommit: (v) => controller.setWeight(double.tryParse(v)),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l.fieldSexAtBirth, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        // docs/03 §2: the BMR equation needs biological sex. Saying so avoids the reading that
        // this is a question about gender identity, which it is not.
        Text(l.sexAtBirthWhy, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => Column(
            children: [
              for (final s in SexAtBirth.values)
                ChoiceTile(
                  label: s.label(l),
                  selected: controller.sexAtBirth.value == s,
                  onTap: () => controller.sexAtBirth.value = s,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A numeric field that validates when the user is FINISHED, not on every keystroke.
///
/// Validating per character means typing "72" is judged at "7" and the user is told their weight is
/// out of range while they are still typing it. Ranges are checked on blur or submit; the value is
/// cleared as they type so a stale reject never lingers.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.onCommit,
    this.decimal = false,
    this.helperText,
  });

  final String label;
  final bool decimal;
  final String? helperText;
  final ValueChanged<String> onCommit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(widget.decimal ? '[0-9.]' : '[0-9]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        // docs/03 §2 ranges, shown up front rather than only as a rejection after the fact.
        helperText: widget.helperText,
      ),
      onSubmitted: widget.onCommit,
      onEditingComplete: () => widget.onCommit(_controller.text),
    );
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
              for (final g in Goal.values)
                ChoiceTile(
                  label: g.label(l),
                  selected: controller.goal.value == g,
                  onTap: () => controller.goal.value = g,
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
              for (final a in ActivityLevel.values)
                ChoiceTile(
                  label: a.label(l),
                  description: a.description(l),
                  selected: controller.activity.value == a,
                  onTap: () => controller.activity.value = a,
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
        _StepTitle(l.onboardingConditionsTitle, subtitle: l.onboardingConditionsSubtitle),
        Obx(() {
          // FR-1.3: pregnancy and lactation are offered only to women aged 18-50. Outside that
          // band they are health fields with no clinical purpose, which docs/13 forbids collecting.
          final hidden = controller.asksPregnancyStatus
              ? const <Condition>{}
              : const {Condition.pregnancy, Condition.lactation};
          return Column(
            children: [
              for (final c in Condition.values)
                if (!hidden.contains(c))
                  ChoiceTile(
                    label: c.label(l),
                    multiSelect: true,
                    selected: controller.conditions.contains(c),
                    onTap: () => controller.toggleCondition(c),
                  ),
            ],
          );
        }),
      ],
    );
  }
}

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(l.onboardingConsentTitle),
        Text(l.onboardingConsentBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        // FR-1.7 / docs/13 §3: itemised, opt-in, and never pre-ticked.
        Obx(
          () => CheckboxListTile(
            value: controller.consentGranted.value,
            onChanged: (v) => controller.consentGranted.value = v ?? false,
            title: Text(l.consentHealthData, style: theme.textTheme.bodyMedium),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}

/// docs/05 §3 referral screen. A dead end on purpose: no plan, no "continue anyway", no paywall.
/// docs/05 §6 — a safety message is never behind a subscription.
class _GateView extends StatelessWidget {
  const _GateView({required this.controller});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.gateTitle, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          Text(l.gateBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(onPressed: controller.back, child: Text(l.gateAction)),
        ],
      ),
    );
  }
}
