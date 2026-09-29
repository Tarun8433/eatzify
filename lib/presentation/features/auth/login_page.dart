import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/code_step.dart';
import 'package:health_pro/presentation/features/auth/widgets/forgot_step.dart';
import 'package:health_pro/presentation/features/auth/widgets/sign_in_step.dart';
import 'package:health_pro/presentation/features/auth/widgets/sign_up_step.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The first screen: email and password, with a code emailed the first time (D-250).
///
/// Every step on one page rather than a route each: each is the same screen with the question
/// changed, and pushing routes would put a system back button beside the app's own way back.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _scroll = ScrollController();
  late final Worker _stepChanges;

  @override
  void initState() {
    super.initState();
    // Changing step swaps the page's content but not its scroll offset. The disclaimer makes this
    // page taller than a small phone, so someone who scrolled to reach a button was dropped into
    // the middle of the next step — past the fields they were just asked to fill in.
    _stepChanges = ever(Get.find<LoginController>().step, (_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _stepChanges.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<LoginController>();
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        // Only `step` is read here. Everything else reactive belongs to a step, which wraps its
        // own `Obx` — a value read in this closure but rendered by a child widget's `build` is read
        // outside the reactive scope and never rebuilds. That bug shipped once already (D-88).
        child: Obx(() {
          final step = c.step.value;
          final (title, subtitle) = switch (step) {
            AuthStep.signIn => (l.loginTitle, l.loginSubtitle),
            AuthStep.signUp => (l.signUpTitle, l.signUpSubtitle),
            AuthStep.verify => (l.otpTitle, l.otpSubtitle(c.email.value.trim())),
            AuthStep.forgot => (l.forgotTitle, l.forgotSubtitle),
            AuthStep.forgotSent => (l.forgotSentTitle, ''),
          };

          return ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            children: [
              _TopRow(
                // Not on sign-in: there is nothing behind it, and an arrow that does nothing is
                // worse than no arrow.
                onBack: step == AuthStep.signIn ? null : () => c.goTo(AuthStep.signIn),
                secureLabel: l.loginSecureBadge,
                backLabel: l.loginBack,
              ),
              const SizedBox(height: AppSpacing.xl),
              _Heading(title: title, subtitle: subtitle),
              const SizedBox(height: AppSpacing.xl),
              switch (step) {
                AuthStep.signIn => SignInStep(controller: c),
                AuthStep.signUp => SignUpStep(controller: c),
                AuthStep.verify => CodeStep(controller: c),
                AuthStep.forgot => ForgotStep(controller: c),
                AuthStep.forgotSent => ForgotSentStep(controller: c),
              },
              const SizedBox(height: AppSpacing.xxl),
              _ImportantCard(title: l.loginImportantTitle, body: l.copyDisclaimer),
              const SizedBox(height: AppSpacing.xl),
              _Footer(label: l.loginFooter),
            ],
          );
        }),
      ),
    );
  }
}

/// The back arrow and the reassurance, on one line above the headline.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.onBack, required this.secureLabel, required this.backLabel});

  final VoidCallback? onBack;
  final String secureLabel;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            // Icon-only, so it carries its own label (rule 12).
            tooltip: backLabel,
            icon: const Icon(Icons.arrow_back_rounded),
            color: theme.colorScheme.primary,
            // Pulls the glyph to the page's left edge; the icon's own padding does the rest.
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
          ),
        // Expanded rather than a Spacer, so the badge can give width back at 200 % font scale
        // instead of overflowing the row (rule 12).
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: // Not a claim about cryptography — the answer to "is it safe to type this in here",
                // asked at the moment someone is deciding whether to.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppElevation.card(theme.brightness),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: AppSpacing.xl,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          secureLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

/// Headline and one sentence, with the art beside them rather than above.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Shared with the goal step, so two screens with art beside a headline look like one
        // design rather than two attempts at it (D-111).
        final art = (constraints.maxWidth * AppSizes.heroArtFraction).clamp(
          0.0,
          AppSizes.heroArtMax,
        );

        // A Stack rather than a Row, and the two fractions add up to more than one: the outer
        // eighth of the PNG is transparent, so the boxes overlap while nothing drawn in them does.
        // That overlap is where the width for a two-line headline comes from (D-111).
        return SizedBox(
          width: constraints.maxWidth,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: ExcludeSemantics(
                  child: Image.asset(
                    AppAssets.loginHero,
                    width: art,
                    // A missing asset must not take the sign-in screen down with it. Nothing stands
                    // in: the illustration says nothing the headline has not already said.
                    errorBuilder: (context, _, _) => SizedBox(width: art),
                  ),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth * AppSizes.heroTextFraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle.isNotEmpty) const SizedBox(height: AppSpacing.md),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The clinical disclaimer, docs/05 §6. Warm rather than green: it is the one block on the page
/// that is neither a question nor an action, and it must not read as another thing to press.
class _ImportantCard extends StatelessWidget {
  const _ImportantCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
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
                  decoration: BoxDecoration(
                    color: AppColors.warmCoral.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: AppSpacing.xl,
                    color: AppColors.warmCoral,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Expanded so the heading wraps beside the 44 pt disc instead of running past the
              // card: unbounded, it overflowed by 71 pt at 200 % font scale (rule 12).
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Container(
            height: AppSpacing.xxl,
            width: AppSpacing.xxl,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.spa_outlined,
              size: AppSpacing.lg,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
        const SizedBox(width: AppSpacing.sm),
        ExcludeSemantics(
          child: Icon(
            Icons.favorite_rounded,
            size: AppSpacing.lg,
            color: theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}
