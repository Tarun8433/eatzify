import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// Common chrome for a tab: title, optional subtitle, body. No back arrow and no menu pill —
/// docs/14 §1 deletes that pattern.
class TabScaffold extends StatelessWidget {
  const TabScaffold({required this.title, required this.child, super.key, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
