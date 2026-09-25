import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/app_notification.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';
import 'package:health_pro/presentation/features/account/notifications_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Notifications" (docs/14 §6): what the server has told this person — renewal notices today,
/// anything an admin sends later.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  /// Opens the screen with a controller that lives as long as it does.
  static Future<void>? open() => Get.to<void>(
    () => const NotificationsPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(
        () => NotificationsController(notifications: Get.find<NotificationsRepository>()),
      );
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<NotificationsController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationsTitle),
        actions: [
          Obx(
            () => c.unread.value == 0
                ? const SizedBox.shrink()
                : TextButton(onPressed: c.markAllRead, child: Text(l.notificationsMarkAllRead)),
          ),
        ],
      ),
      body: Obx(
        () => switch (c.state.value) {
          Loading<List<AppNotification>>() => const LoadingView(),
          Failed<List<AppNotification>>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
          ),
          Empty<List<AppNotification>>() => EmptyView(
            title: l.notificationsEmpty,
            body: l.notificationsEmptyBody,
          ),
          Ready<List<AppNotification>>(:final data) => RefreshIndicator(
            onRefresh: () => c.load(quiet: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              itemCount: data.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, index) =>
                  _NotificationCard(notification: data[index], onTap: () => c.open(data[index])),
            ),
          ),
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = notification.createdAt;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A dot, not a colour on the text: unread has to survive being read by someone who does
          // not see the colour difference.
          if (notification.isUnread) ...[
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Icon(Icons.circle, size: AppSpacing.sm, color: AppColors.info),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: notification.isUnread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The server's own words (rule 7).
                Text(notification.body, style: theme.textTheme.bodyMedium),
                if (when != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    DateFormat.yMMMd(locale).add_jm().format(when),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
