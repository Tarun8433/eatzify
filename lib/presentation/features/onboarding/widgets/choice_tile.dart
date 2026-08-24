import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A single-select or multi-select option row.
///
/// 48 dp minimum target and a real `Semantics` state, so a screen reader announces selection rather
/// than leaving it to a colour difference (docs/14 §5).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.description,
    this.multiSelect = false,
  });

  final String label;
  final String? description;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      inMutuallyExclusiveGroup: !multiSelect,
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: selected ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.bodyMedium),
                        if (description != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(description!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  Icon(switch ((multiSelect, selected)) {
                    (true, true) => Icons.check_box,
                    (true, false) => Icons.check_box_outline_blank,
                    (false, true) => Icons.radio_button_checked,
                    (false, false) => Icons.radio_button_unchecked,
                  }, color: selected ? scheme.primary : scheme.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
