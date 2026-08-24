import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// docs/14 §6: phone/OTP is the first screen. Phone is primary auth in India (docs/09 §3) — there
/// is no email or password anywhere in this flow.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<LoginController>();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final sent = c.codeSent.value;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                Text(sent ? l.otpTitle : l.loginTitle, style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  sent ? l.otpSubtitle(c.phoneE164) : l.loginSubtitle,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!sent) _PhoneField(controller: c) else _OtpField(controller: c),
                const SizedBox(height: AppSpacing.lg),
                if (c.failure.value != null)
                  // CLAUDE.md rule 7: the server's user_message, verbatim.
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      c.failure.value!.userMessage,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                FilledButton(
                  onPressed: c.busy.value
                      ? null
                      : sent
                      ? (c.canVerify ? c.verify : null)
                      : (c.canSend ? c.sendCode : null),
                  child: Text(sent ? l.otpVerify : l.loginSendCode),
                ),
                if (sent) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: c.resendIn.value == 0 ? c.sendCode : null,
                    child: Text(
                      c.resendIn.value == 0 ? l.otpResend : l.otpResendIn(c.resendIn.value),
                    ),
                  ),
                ],
                const Spacer(),
                Text(l.copyDisclaimer, style: theme.textTheme.bodySmall),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      keyboardType: TextInputType.phone,
      autofocus: true,
      maxLength: 10,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: l.loginPhoneLabel,
        prefixText: '+91 ',
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: (v) => controller.phone.value = v,
    );
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller});
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      keyboardType: TextInputType.number,
      autofocus: true,
      maxLength: LoginController.otpLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: l.otpLabel,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: (v) => controller.otp.value = v,
    );
  }
}

/// Shown while secure storage is read on boot. docs/14 §3: a state, not an inferred null.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: LoadingView(lines: 2)));
}
