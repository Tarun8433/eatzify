/// One message between a coach and their client (docs/02 FR-5.5).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUserId,
    required this.body,
    required this.mine,
    this.readAt,
    this.createdAt,
  });

  /// [me] is the reader's own user id, for the live socket payload — it says who WROTE a message
  /// rather than whose it is, because the same message is mine to one side and not the other.
  factory ChatMessage.fromJson(Map<String, dynamic> json, {int? me}) {
    final sender = (json['sender_user_id'] as num?)?.toInt() ?? 0;
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderUserId: sender,
      body: json['body']?.toString() ?? '',
      mine: json['mine'] as bool? ?? (me != null && sender == me),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? '')?.toLocal(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  final String id;
  final int senderUserId;
  final String body;

  /// Whether the reader wrote it. The SERVER decides this on the REST path so two clients can
  /// never disagree about which side of the bubble a message belongs on.
  final bool mine;

  final DateTime? readAt;
  final DateTime? createdAt;
}

/// One conversation, from the caller's point of view.
class ChatThread {
  const ChatThread({
    required this.otherUserId,
    required this.name,
    required this.iAmCoach,
    this.lastMessage,
    this.lastAt,
    this.unread = 0,
  });

  ChatThread.fromJson(Map<String, dynamic> json)
    : this(
        otherUserId: (json['other_user_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        iAmCoach: json['i_am_coach'] as bool? ?? false,
        lastMessage: json['last_message']?.toString(),
        lastAt: DateTime.tryParse(json['last_at']?.toString() ?? '')?.toLocal(),
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );

  final int otherUserId;

  /// Already masked to what this side may see (docs/10).
  final String name;

  final bool iAmCoach;
  final String? lastMessage;
  final DateTime? lastAt;
  final int unread;
}
