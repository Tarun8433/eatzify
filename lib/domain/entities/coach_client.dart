/// One person this coach is actually working with — `GET /coach/clients` (D-195).
///
/// Different from `SentInvite` in the one way that matters: an invite is a question and this is an
/// answered one. A row exists here only because the client said yes, and [scopes] is what they
/// agreed to rather than what the coach asked for.
class CoachClient {
  const CoachClient({
    required this.userId,
    required this.name,
    required this.scopes,
    this.accessEndsAt,
    this.tier,
    this.ageYears,
    this.ageBand,
    this.goal,
    this.adherencePct,
    this.streakDays,
    this.daysSinceLastLog,
    this.weightKg,
    this.weightChange30d,
    this.status,
  });

  CoachClient.fromJson(Map<String, dynamic> json)
    : this(
        userId: (json['client_user_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        scopes: (json['scopes'] as List?)?.map((s) => s.toString()).toList() ?? const [],
        accessEndsAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
        tier: json['tier']?.toString(),
        ageYears: (json['age_years'] as num?)?.toInt(),
        ageBand: json['age_band']?.toString(),
        goal: json['goal']?.toString(),
        adherencePct: (json['adherence_pct'] as num?)?.toInt(),
        streakDays: (json['streak_days'] as num?)?.toInt(),
        daysSinceLastLog: (json['days_since_last_log'] as num?)?.toInt(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        weightChange30d: (json['weight_change_30d'] as num?)?.toDouble(),
        status: json['status']?.toString(),
      );

  final int userId;

  /// Already masked by the server where the coach's level requires it (docs/10 §2). The app never
  /// masks anything itself — it would have to know the level to do so, and then two places would
  /// decide one rule.
  final String name;

  /// What this client allowed, intersected with what the coach's level reaches. Shown to the coach
  /// so the limits of the relationship are visible rather than felt as missing screens.
  final List<String> scopes;

  /// docs/10 §3: a grant expires. Null only if the server ever stops sending it.
  final DateTime? accessEndsAt;

  /// FREE / BASIC / PRO, already resolved for expiry by the server. Shown through l10n (rule 4).
  final String? tier;

  /// The number for a verified coach, the band for one who is not — docs/10 §2. Exactly one
  /// arrives, and both being null means the grant did not carry an age at all.
  final int? ageYears;
  final String? ageBand;

  final String? goal;

  /// Days logged over the window, as a percentage. **Null is not zero**: somebody who has never
  /// logged has no figure, and printing 0 % would be a verdict rather than a measurement
  /// (docs/02 FR-4.2 — "a count not a shame badge").
  final int? adherencePct;

  /// Consecutive days logged. A logging streak, never a weight one — docs/05 §6.
  final int? streakDays;

  /// Whole days since the last log. Null when they have never logged, which the screen shows
  /// differently from "logged a long time ago".
  final int? daysSinceLastLog;

  final double? weightKg;

  /// The 30-day trend change, the same figure the client sees on their own Progress tab. Shown
  /// without a colour: docs/05 §6 — a gain is stated in the same voice as a loss.
  final double? weightChange30d;

  /// `active` · `at_risk` · `no_recent_logs`. Server-decided (rule 2), rendered through l10n.
  final String? status;

  /// Whether anything beyond a name came back. False means the grant is `basic` and the coach's
  /// level reaches nothing more — worth saying out loud rather than drawing an empty row.
  bool get hasMetrics => adherencePct != null || weightKg != null || streakDays != null;
}

/// One client opened — `GET /coach/clients/:id` (D-195).
///
/// **Every field is nullable, and null means "not allowed", not "not answered".** The server omits
/// what the grant does not cover, so a missing weight is a boundary and not a gap in the client's
/// profile. The screen says so rather than printing a dash.
class CoachClientDetail {
  const CoachClientDetail({
    required this.userId,
    required this.name,
    required this.scopes,
    this.ageYears,
    this.ageBand,
    this.goal,
    this.sexAtBirth,
    this.heightCm,
    this.weightKg,
    this.conditions,
    this.allergies,
    this.medications,
    this.digestiveSymptoms,
    this.injuries,
    this.routine,
  });

  CoachClientDetail.fromJson(Map<String, dynamic> json)
    : this(
        userId: (json['client_user_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        scopes: (json['scopes'] as List?)?.map((s) => s.toString()).toList() ?? const [],
        ageYears: (json['age_years'] as num?)?.toInt(),
        ageBand: json['age_band']?.toString(),
        goal: json['goal']?.toString(),
        sexAtBirth: json['sex_at_birth']?.toString(),
        heightCm: (json['height_cm'] as num?)?.toInt(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        // A LIST that is absent differs from one that is empty: absent is "you may not see this",
        // empty is "they declared none". Both are real answers and they are not the same.
        conditions: (json['conditions'] as List?)?.map((c) => c.toString()).toList(),
        allergies: (json['allergies'] as List?)?.map((a) => a.toString()).toList(),
        medications: json['medications']?.toString(),
        digestiveSymptoms: (json['digestive_symptoms'] as List?)?.map((d) => d.toString()).toList(),
        injuries: (json['injuries'] as List?)?.map((i) => i.toString()).toList(),
        routine: json['routine'] as Map<String, dynamic>?,
      );

  final int userId;
  final String name;
  final List<String> scopes;

  /// The exact age for a verified coach, the band for one who is not (docs/10 §2). Exactly one of
  /// the two arrives.
  final int? ageYears;
  final String? ageBand;

  final String? goal;
  final String? sexAtBirth;
  final int? heightCm;
  final double? weightKg;
  final List<String>? conditions;
  final List<String>? allergies;
  final String? medications;
  final List<String>? digestiveSymptoms;
  final List<String>? injuries;

  /// Every answer the PLAN was built from — meal count, meal times, lifestyle, budget, dislikes.
  /// Not medical, and exactly what somebody writing a diet needs before they write it (D-205).
  final Map<String, dynamic>? routine;

  /// Whether anything beyond the name came back. False means the grant is `basic` and the coach's
  /// level reaches nothing more — worth saying out loud rather than showing a near-empty page.
  bool get hasAnyDetail =>
      goal != null ||
      weightKg != null ||
      heightCm != null ||
      conditions != null ||
      allergies != null ||
      routine != null;

  /// docs/13: a client's declared conditions never reach a log line.
  @override
  String toString() => 'CoachClientDetail($userId, redacted)';
}

/// `GET /coach/clients/:id/progress` — what this client has actually been logging.
///
/// docs/10 §3's `progress` scope in full: "weight series, adherence %, steps, streaks". A coach
/// whose client granted it was seeing five profile fields and none of this.
class ClientProgress {
  const ClientProgress({
    required this.series,
    required this.daysLogged,
    required this.windowDays,
    required this.streakDays,
    this.avgKcal,
    this.avgProteinG,
    this.targetKcal,
    this.targetProteinG,
    this.weightChangeTotal,
    this.weightChange30d,
    this.adherencePct,
    this.lastLoggedDate,
  });

  ClientProgress.fromJson(Map<String, dynamic> json)
    : this(
        series: {
          for (final MapEntry(key: kind, value: points)
              in ((json['series'] as Map?) ?? const {}).entries)
            kind.toString(): ((points as List?) ?? const [])
                .map((p) => SeriesPoint.fromJson(p as Map<String, dynamic>))
                .toList(),
        },
        daysLogged: (json['days_logged'] as num?)?.toInt() ?? 0,
        windowDays: (json['window_days'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
        avgKcal: (json['avg_kcal'] as num?)?.toInt(),
        avgProteinG: (json['avg_protein_g'] as num?)?.toInt(),
        targetKcal: (json['target_kcal'] as num?)?.toInt(),
        targetProteinG: (json['target_protein_g'] as num?)?.toInt(),
        weightChangeTotal: (json['weight_change_total'] as num?)?.toDouble(),
        weightChange30d: (json['weight_change_30d'] as num?)?.toDouble(),
        adherencePct: (json['adherence_pct'] as num?)?.toInt(),
        lastLoggedDate: json['last_logged_date']?.toString(),
      );

  /// Keyed by measurement kind — `weight`, `steps`, `water_ml` and the rest. A kind the client
  /// never recorded is ABSENT rather than an empty list: an empty chart draws a flat line, which
  /// is a claim about somebody who simply never logged it.
  final Map<String, List<SeriesPoint>> series;

  final int daysLogged;
  final int windowDays;
  final int streakDays;

  /// What they ate against what the plan asked for, averaged over the days they logged.
  ///
  /// **This is the pair a nutritionist reads.** [adherencePct] is logging FREQUENCY — somebody can
  /// log a pizza every day and score 100 % on it. These say whether the food matched the plan.
  ///
  /// Null when there is no plan or nothing logged. Never zero, which would claim they ate nothing.
  final int? avgKcal;
  final int? avgProteinG;
  final int? targetKcal;
  final int? targetProteinG;

  /// The moving-average trend, the same figure the client sees on their own Progress tab. Null
  /// when there are too few readings to say anything — never zero, which would claim no change.
  final double? weightChangeTotal;
  final double? weightChange30d;

  /// Null is not zero. Somebody who has never logged has no adherence figure.
  final int? adherencePct;
  final String? lastLoggedDate;

  bool get isEmpty => series.isEmpty && adherencePct == null && avgKcal == null;

  /// docs/13: a client's readings never reach a log line.
  @override
  String toString() => 'ClientProgress(redacted)';
}

/// One dated reading.
class SeriesPoint {
  const SeriesPoint({required this.date, required this.value});

  SeriesPoint.fromJson(Map<String, dynamic> json)
    : this(date: json['date']?.toString() ?? '', value: (json['value'] as num?)?.toDouble() ?? 0);

  final String date;
  final double value;
}
