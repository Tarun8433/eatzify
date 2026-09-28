import 'package:flutter/material.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/skeleton.dart';

/// Loading skeleton. docs/14 §6 asks for a skeleton, not a spinner — a spinner on a slow Indian
/// 3G connection reads as "broken", a skeleton reads as "coming".
///
/// The generic shape, for a screen with no skeleton of its own. A screen whose real layout is
/// distinctive deserves one that mirrors it — see `HomeSkeleton` (D-162) — because bars that turn
/// into a hero and a tile grid are a jump, not a fill-in.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(lines, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SkeletonBox(height: i == 0 ? 96 : 56),
            );
          }),
        ),
      ),
    );
  }
}

/// Empty state. docs/14 §6: "empty with a single clear action" — exactly one, never a dead end.
class EmptyView extends StatelessWidget {
  const EmptyView({required this.title, super.key, this.body, this.actionLabel, this.onAction});

  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(body!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Failure state with a retry. Shows `failure.userMessage` verbatim — CLAUDE.md rule 7.
class FailedView extends StatelessWidget {
  const FailedView({required this.failure, super.key, this.onRetry, this.retryLabel});

  final Failure failure;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The server owns this string. Do not prepend, append, or rephrase it.
            Text(
              failure.userMessage,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null && retryLabel != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
