import 'package:flutter/material.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// The one thing the screen is asking you to press.
///
/// Both sign-in steps have exactly one, and they must not drift: the label is centred and the arrow
/// is pinned to the right edge, so the arrow reads as a direction rather than as part of the word.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton(
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// The failure line above the button.
///
/// CLAUDE.md rule 7: this renders the server's `user_message` verbatim and never a message of our
/// own. It is `Semantics(liveRegion:)` because the text appears without the focus moving — a screen
/// reader user pressing "Send code" would otherwise get silence.
class AuthFailureText extends StatelessWidget {
  const AuthFailureText({required this.failure, super.key});

  final Failure? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (failure == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: AppSpacing.xl, color: theme.colorScheme.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                failure!.userMessage,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
