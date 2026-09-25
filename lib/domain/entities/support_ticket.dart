/// A support conversation and the messages in it (docs/14 §6's "help/tickets").
///
/// `status` stays the server's own string. The screen maps it through l10n (rule 4) rather than
/// storing a translated word, because the state is the server's to decide and ours to render.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    this.requestId,
    this.lastMessageAt,
    this.createdAt,
  });

  SupportTicket.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        status: json['status']?.toString() ?? 'new',
        requestId: json['request_id']?.toString(),
        lastMessageAt: DateTime.tryParse(json['last_message_at']?.toString() ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      );

  final String id;
  final String subject;

  /// `new`, `open`, `waiting_user`, `resolved` or `closed` (docs/03 §5).
  final String status;

  /// docs/09 §1: the `X-Request-Id` of the response that went wrong, when the person had one.
  final String? requestId;

  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  /// Whether the compose box is shown. A resolved conversation still takes a reply for seven days
  /// (docs/03 §5) — the server decides the exact day and says so if the window has passed; the app
  /// only hides the box where writing could never work.
  bool get isWritable => status != 'closed';

  /// Whether support still owes an answer. What sorts the list for the reader's own sense of it.
  bool get isWaitingOnSupport => status == 'new' || status == 'open';
}

/// One message inside a conversation.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.body,
    required this.fromSupport,
    this.createdAt,
  });

  SupportMessage.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        fromSupport: json['from_support'] == true,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      );

  final String id;
  final String body;
  final bool fromSupport;
  final DateTime? createdAt;
}

/// A conversation with its messages, oldest first.
typedef SupportThread = ({SupportTicket ticket, List<SupportMessage> messages});
