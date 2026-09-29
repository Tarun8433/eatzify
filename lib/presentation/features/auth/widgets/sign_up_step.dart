import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/config/site_links.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_fields.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/widgets/site_link.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Email, password and phone number (D-250). The number is collected — receipts and Cashfree need
/// one — but it is never a way in, so it is not verified.
class SignUpStep extends StatelessWidget {
  const SignUpStep({required this.controller, super.key});

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
          AuthPasswordField(value: c.password, isNew: true, textInputAction: TextInputAction.next),
          const SizedBox(height: AppSpacing.md),
          IntlPhoneField(
            initialCountryCode: 'IN',
            languageCode: Localizations.localeOf(context).languageCode,
            // The package caps input at the selected country's maximum; its validator never runs
            // (no Form, autovalidate off), so nothing turns red mid-typing. The button says whether
            // the number is usable.
            autovalidateMode: AutovalidateMode.disabled,
            dropdownIconPosition: IconPosition.trailing,
            flagsButtonPadding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
            decoration: InputDecoration(
              labelText: l.loginPhoneLabel,
              hintText: l.loginPhoneHint,
              counterText: '',
            ),
            onCountryChanged: (country) => c.setCountry(
              dial: '+${country.fullCountryCode}',
              minLength: country.minLength,
              maxLength: country.maxLength,
            ),
            onChanged: (phone) => c.phone.value = phone.number,
          ),
          const SizedBox(height: AppSpacing.md),
          HintCard(icon: Icons.lock_outline_rounded, text: l.loginPrivacyNote),
          const SizedBox(height: AppSpacing.xl),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthFailureText(failure: c.failure.value),
                AuthPrimaryButton(
                  label: l.loginCreateAccount,
                  onPressed: c.canSignUp ? c.signUp : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AgreementLine(
                  lead: l.legalAgreeSignIn,
                  links: [
                    (label: l.legalTerms, uri: SiteLinks.terms),
                    (label: l.legalPrivacy, uri: SiteLinks.privacy),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AuthLinkRow(
                  lead: l.signUpHaveAccount,
                  action: l.loginSignIn,
                  onPressed: c.busy.value ? null : () => c.goTo(AuthStep.signIn),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
