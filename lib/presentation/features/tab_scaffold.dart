import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// Common chrome for a tab: title, optional subtitle, body. No back arrow and no menu pill —
/// docs/14 §1 deletes that pattern.
class TabScaffold extends StatelessWidget {
  const TabScaffold({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.action,
    this.titleIcon,
  });

  final String title;

  /// Decoration beside the title, excluded from semantics — the word carries the meaning.
  final IconData? titleIcon;

  final String? subtitle;

  /// One control on the heading's right — the Plan tab's Go Premium pill (D-136). One, because a
  /// heading with a toolbar in it is a toolbar.
  final Widget? action;

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(title, style: theme.textTheme.headlineMedium)),
                        if (titleIcon != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          ExcludeSemantics(
                            child: Icon(
                              titleIcon,
                              size: AppSpacing.lg,
                              // The reference's wave is the warm gold of the emoji it stands in
                              // for (ui-standards bans the emoji itself), not the brand teal.
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
