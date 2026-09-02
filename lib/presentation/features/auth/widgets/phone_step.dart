import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/features/auth/widgets/google_button.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Step one: the number. docs/09 §3 — phone is primary auth in India, and there is no email or
/// password anywhere in this flow.
class PhoneStep extends StatefulWidget {
  const PhoneStep({required this.controller, super.key});

  final LoginController controller;

  @override
  State<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<PhoneStep> {
  /// Owned here so the field can be CLEARED, not just the controller's copy of it.
  late final _text = TextEditingController(text: widget.controller.phone.value);
  late final Worker _numberChanges;

  @override
  void initState() {
    super.initState();
    // Follows the controller rather than being cleared at the one call site that needed it. The
    // number is emptied by `setCountry`, and it will be emptied by whatever clears it next; a
    // field that only agrees with the controller on the paths someone remembered is how a stale
    // value ends up on screen. The guard is what keeps normal typing — where the controller is
    // downstream of this very field — from resetting the cursor on every keystroke.
    _numberChanges = ever(widget.controller.phone, (value) {
      if (value != _text.text) _text.text = value;
    });
  }

  @override
  void dispose() {
    _numberChanges.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The app's ordinary field, from `inputDecorationTheme` — the same filled, tile-radius card
        // as every field in onboarding. The picker rides in as the prefix, which is what the
        // decoration is for; a field dressed differently from the rest of the app is a field the
        // user has to learn.
        IntlPhoneField(
          controller: _text,
          initialCountryCode: 'IN',
          // Every country. India is the default because it is the market (docs/01), not a fence:
          // someone signing in from a number that is not Indian was previously unable to say so.
          //
          // The backend only sends OTPs where its provider has coverage, and it answers with a
          // `user_message` when it cannot. That refusal belongs to the server (rule 7) — guessing
          // it here would mean maintaining a second copy of the provider's country list in the app.
          languageCode: Localizations.localeOf(context).languageCode,
          // `disableLengthCheck` stays at its default false, so the package caps input at the
          // selected country's own maximum: nine digits where nine is the length, ten where it is
          // ten. The validator it also enables never runs — there is no Form around this field and
          // `autovalidateMode` is off — so nothing turns red while the fourth digit is still being
          // typed. The button is what says whether the number is usable.
          autovalidateMode: AutovalidateMode.disabled,
          dropdownIconPosition: IconPosition.trailing,
          flagsButtonPadding: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: InputDecoration(
            labelText: l.loginPhoneLabel,
            hintText: l.loginPhoneHint,
            // `maxLength` draws a "4/10" counter otherwise. The field already refuses the
            // eleventh digit; counting up to it is noise while someone types their own number.
            counterText: '',
          ),
          onCountryChanged: (country) {
            c.setCountry(
              dial: '+${country.fullCountryCode}',
              minLength: country.minLength,
              maxLength: country.maxLength,
            );
          },
          onChanged: (phone) => c.phone.value = phone.number,
        ),
        const SizedBox(height: AppSpacing.md),
        // Not a legal notice — the answer to the question someone hesitates over before typing ten
        // digits into an app they installed twenty seconds ago.
        HintCard(icon: Icons.lock_outline_rounded, text: l.loginPrivacyNote),
        const SizedBox(height: AppSpacing.xl),
        Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthFailureText(failure: c.failure.value),
              AuthPrimaryButton(label: l.loginSendCode, onPressed: c.canSend ? c.sendCode : null),
              if (c.googleEnabled) ...[
                const SizedBox(height: AppSpacing.lg),
                _OrDivider(label: l.loginOr),
                const SizedBox(height: AppSpacing.lg),
                GoogleButton(
                  onPressed: c.busy.value ? null : () => c.signInWithGoogle(l.loginGoogleFailed),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A hairline either side of the word. The alternative — a bare "or" on its own line — reads as a
/// stray caption rather than as the fork between two ways in.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = Expanded(child: Divider(color: theme.colorScheme.outline));

    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        line,
      ],
    );
  }
}
