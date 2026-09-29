import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/config/site_links.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_fields.dart';
import 'package:health_pro/presentation/features/auth/widgets/google_button.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/widgets/site_link.dart';

/// Email and password (D-250), with the ways to the other steps beneath.
class SignInStep extends StatelessWidget {
  const SignInStep({required this.controller, super.key});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthEmailField(value: c.email),
          const SizedBox(height: AppSpacing.md),
          AuthPasswordField(value: c.password, isNew: false, onSubmitted: c.signIn),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => c.goTo(AuthStep.forgot), child: Text(l.loginForgot)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthFailureText(failure: c.failure.value),
                AuthPrimaryButton(label: l.loginSignIn, onPressed: c.canSignIn ? c.signIn : null),
                const SizedBox(height: AppSpacing.sm),
                AgreementLine(
                  lead: l.legalAgreeSignIn,
                  links: [
                    (label: l.legalTerms, uri: SiteLinks.terms),
                    (label: l.legalPrivacy, uri: SiteLinks.privacy),
                  ],
                ),
                if (c.googleEnabled) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AuthOrDivider(label: l.loginOr),
                  const SizedBox(height: AppSpacing.lg),
                  GoogleButton(
                    onPressed: c.busy.value ? null : () => c.signInWithGoogle(l.loginGoogleFailed),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AuthLinkRow(
                  lead: l.loginNoAccount,
                  action: l.loginCreateAccount,
                  onPressed: c.busy.value ? null : () => c.goTo(AuthStep.signUp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
