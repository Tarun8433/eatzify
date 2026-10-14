import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';
import 'package:health_pro/presentation/features/account/notifications_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Good Morning!" and its siblings, by the phone's own hour. A greeting, not a diary date, so the
/// phone's clock is the right one to ask (rule 8 is about where a diary day begins).
String homeGreeting(AppLocalizations l, DateTime now) => switch (now.hour) {
  < _afternoon => l.homeGreetingMorning,
  < _evening => l.homeGreetingAfternoon,
  _ => l.homeGreetingEvening,
};

const _afternoon = 12;
const _evening = 17;

/// The bell beside Go Premium: opens Notifications, and carries a dot only when the server says
/// something is unread — never a dot drawn to get a tap.
class HomeNotificationBell extends StatefulWidget {
  const HomeNotificationBell({super.key});

  @override
  State<HomeNotificationBell> createState() => _HomeNotificationBellState();
}

class _HomeNotificationBellState extends State<HomeNotificationBell> {
  var _unread = 0;

  static const _dot = 10.0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Quiet on failure: a bell without a dot is the honest answer when the count is unknown.
  Future<void> _refresh() async {
    if (!Get.isRegistered<NotificationsRepository>()) return;
    final feed = await Get.find<NotificationsRepository>().list();
    if (!mounted) return;
    feed.fold((_) {}, (f) => setState(() => _unread = f.unreadCount));
  }

  Future<void> _open() async {
    await NotificationsPage.open();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: CircleAvatar(
        child: IconButton(
          tooltip: l.notificationsTitle,
          onPressed: _open,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_none_rounded, color: scheme.surface),
              if (_unread > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: _dot,
                    height: _dot,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: AppSpacing.xs / 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
