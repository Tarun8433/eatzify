import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_fields.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The email a reset link goes to. The link opens the website's reset page, not the app.
class ForgotStep extends StatelessWidget {
  const ForgotStep({required this.controller, super.key});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthEmailField(value: c.email),
        const SizedBox(height: AppSpacing.xl),
        Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthFailureText(failure: c.failure.value),
              AuthPrimaryButton(
                label: l.forgotSend,
                onPressed: c.canSendReset ? c.sendReset : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The same words whether or not the address has an account — the server answers identically, and
/// so must the screen.
class ForgotSentStep extends StatelessWidget {
  const ForgotSentStep({required this.controller, super.key});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HintCard(
          icon: Icons.mark_email_read_outlined,
          text: l.forgotSentBody(controller.email.value.trim()),
        ),
        const SizedBox(height: AppSpacing.xl),
        AuthPrimaryButton(
          label: l.forgotBackToSignIn,
          onPressed: () => controller.goTo(AuthStep.signIn),
        ),
      ],
    );
  }
}
