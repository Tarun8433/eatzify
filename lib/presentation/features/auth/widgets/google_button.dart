import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The second way in. White and outlined rather than filled: there is one primary action on this
/// screen and it is "Send code" — two buttons of equal weight is a screen that cannot say what it
/// wants you to do.
///
/// Only drawn when `LoginController.googleEnabled` — see the data source for why.
class GoogleButton extends StatelessWidget {
  const GoogleButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSizes.primaryButton),
        backgroundColor: theme.colorScheme.surface,
        side: BorderSide(color: theme.colorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The label already says "Continue with Google", so the mark is not read out twice.
          ExcludeSemantics(
            child: Image.asset(
              AppAssets.googleIcon,
              width: AppSpacing.xl,
              height: AppSpacing.xl,
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              l.loginGoogle,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
