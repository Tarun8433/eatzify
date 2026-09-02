import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A titled section with an optional trailing action. Used by every tab so the rhythm of the app
/// is one decision, not five.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // sm/xs, down from xl/md in two steps (D-153, D-155): a header row is ALWAYS the touch
    // target's 48 pt tall — with an action that comes from the TextButton, without one the
    // ConstrainedBox holds the same floor (D-156). Before that, actionless headers collapsed to
    // bare text height and the page's seams read congested in some places and airy in others,
    // depending on nothing but whether a button happened to be there. The section rhythm IS this
    // one floor plus the sliver of padding.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}
