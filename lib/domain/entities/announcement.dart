/// News or an important update from the team, as `GET /announcements` returns it (admin panel
/// plan, Phase C). The server decides which are live for this person; the app only shows them.
enum AnnouncementPriority { normal, important, critical }

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
    this.imageUrl,
  });

  Announcement.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        imageUrl: json['image_url']?.toString(),
        priority: switch (json['priority']) {
          'critical' => AnnouncementPriority.critical,
          'important' => AnnouncementPriority.important,
          _ => AnnouncementPriority.normal,
        },
      );

  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final AnnouncementPriority priority;
}
