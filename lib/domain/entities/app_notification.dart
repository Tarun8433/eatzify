/// One message the server left for this person (docs/14 §6): a renewal notice, a service message,
/// or something an admin sent.
///
/// Named `AppNotification` rather than `Notification` because Flutter already has one, and a widget
/// tree that quietly resolved the wrong `Notification` is a bug nobody reads twice.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.contentClass,
    required this.title,
    required this.body,
    this.data = const {},
    this.readAt,
    this.createdAt,
  });

  AppNotification.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        contentClass: json['content_class']?.toString() ?? 'service',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
        readAt: DateTime.tryParse(json['read_at']?.toString() ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      );

  final String id;

  /// What produced it — `renewal_t7`, `trial_ending`. Never rendered raw (rule 4); the title and
  /// body are the server's own words, which is what the screen shows.
  final String kind;

  /// docs/13 §5: `clinical`, `service` or `commercial`.
  final String contentClass;

  final String title;
  final String body;

  /// Whatever the message needs to be acted on — a tier, an amount, a screen to open.
  final Map<String, dynamic> data;

  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;
}

/// A page of messages and how many are unread, which is what the badge counts.
typedef NotificationFeed = ({List<AppNotification> items, int unreadCount});
