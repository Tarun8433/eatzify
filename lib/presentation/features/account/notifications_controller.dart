import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/app_notification.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';

/// The messages screen (docs/14 §6). Four states, and no state inferred from a null: an empty list
/// is Empty, a transport failure is Failed, and neither is a spinner that never stops.
class NotificationsController extends GetxController {
  NotificationsController({required this.notifications});

  final NotificationsRepository notifications;

  final state = Rx<ViewState<List<AppNotification>>>(const Loading());

  /// What the You tab's row counts. Kept apart from [state] so it survives a failed reload.
  final unread = 0.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// [quiet] keeps what is on screen — pull-to-refresh holds the list it is attached to.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await notifications.list();
    state.value = result.fold(Failed.new, (feed) {
      unread.value = feed.unreadCount;
      return feed.items.isEmpty ? const Empty() : Ready(feed.items);
    });
  }

  /// Reading one marks it read. The row changes at once rather than after a round trip: the
  /// server's answer cannot make the message unread again, and a list that waits feels broken.
  Future<void> open(AppNotification notification) async {
    if (notification.isUnread) _markLocally(notification.id);
    await notifications.markRead(notification.id);
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current is Ready<List<AppNotification>>) {
      state.value = Ready([for (final n in current.data) _read(n)]);
    }
    unread.value = 0;
    await notifications.markAllRead();
  }

  void _markLocally(String id) {
    final current = state.value;
    if (current is! Ready<List<AppNotification>>) return;

    state.value = Ready([
      for (final n in current.data)
        if (n.id == id) _read(n) else n,
    ]);
    if (unread.value > 0) unread.value--;
  }

  static AppNotification _read(AppNotification n) => n.isUnread
      ? AppNotification(
          id: n.id,
          kind: n.kind,
          contentClass: n.contentClass,
          title: n.title,
          body: n.body,
          data: n.data,
          readAt: DateTime.now(),
          createdAt: n.createdAt,
        )
      : n;
}
