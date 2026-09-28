/// One week's review of one client (docs/02 FR-5.2, docs/09 §6).
///
/// The server decides when it falls due and who appears — the app renders the queue it is handed
/// and never works out whose turn it is.
class CheckIn {
  const CheckIn({
    required this.id,
    required this.clientUserId,
    required this.name,
    required this.dueOn,
    required this.status,
    this.completedAt,
    this.notes,
    this.actions = const [],
    this.daysSinceLastLog,
    this.adherencePct,
  });

  CheckIn.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        clientUserId: (json['client_user_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        dueOn: json['due_on']?.toString() ?? '',
        status: json['status']?.toString() ?? 'due',
        completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? '')?.toLocal(),
        notes: json['notes']?.toString(),
        actions: [...(json['actions'] as List? ?? const []).map((a) => a.toString())],
        daysSinceLastLog: (json['days_since_last_log'] as num?)?.toInt(),
        adherencePct: (json['adherence_pct'] as num?)?.toInt(),
      );

  final String id;
  final int clientUserId;

  /// Already masked to what this coach's level may see (docs/10).
  final String name;

  /// The diary date the week's review belongs to — the server's Monday, never computed here.
  final String dueOn;

  /// `due` · `completed` · `missed`. Shown through l10n, never raw (rule 4).
  final String status;

  final DateTime? completedAt;
  final String? notes;
  final List<String> actions;

  /// Null means the client has never logged, which is not the same as logging today.
  final int? daysSinceLastLog;
  final int? adherencePct;

  bool get isDue => status == 'due';
  bool get isMissed => status == 'missed';
  bool get isOpen => isDue || isMissed;
}

/// docs/02 FR-5.3's signals about one client. `kinds` is never empty — a client with nothing to
/// report is simply absent from the list.
class CoachAlert {
  const CoachAlert({
    required this.clientUserId,
    required this.name,
    required this.kinds,
    this.daysSinceLastLog,
    this.weightChange30d,
    this.planEndsInDays,
  });

  CoachAlert.fromJson(Map<String, dynamic> json)
    : this(
        clientUserId: (json['client_user_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        kinds: [...(json['kinds'] as List? ?? const []).map((k) => k.toString())],
        daysSinceLastLog: (json['days_since_last_log'] as num?)?.toInt(),
        weightChange30d: (json['weight_change_30d'] as num?)?.toDouble(),
        planEndsInDays: (json['plan_ends_in_days'] as num?)?.toInt(),
      );

  final int clientUserId;
  final String name;

  /// `no_logs` · `off_trend` · `plan_expiring` · `checkin_missed`.
  final List<String> kinds;

  final int? daysSinceLastLog;
  final double? weightChange30d;
  final int? planEndsInDays;
}
