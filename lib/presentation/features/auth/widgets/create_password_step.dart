import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_fields.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// After a first Google sign-in: one password, so the account can also be signed in to by email.
class CreatePasswordStep extends StatelessWidget {
  const CreatePasswordStep({required this.controller, super.key});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPasswordField(value: c.password, isNew: true, onSubmitted: c.createPassword),
          const SizedBox(height: AppSpacing.xl),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthFailureText(failure: c.failure.value),
                AuthPrimaryButton(
                  label: l.createPasswordSave,
                  onPressed: c.canCreatePassword ? c.createPassword : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
