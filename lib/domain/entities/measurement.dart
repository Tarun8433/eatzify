/// docs/09 §4 / docs/08 §1.
class Measurement {
  const Measurement({
    required this.id,
    required this.kind,
    required this.value,
    required this.unit,
    required this.diaryDate,
    required this.isSuspect,
    this.source = MeasurementSource.manual,
  });

  Measurement.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        diaryDate: json['diary_date']?.toString() ?? '',
        isSuspect: json['is_suspect'] as bool? ?? false,
        source: MeasurementSource.fromWire(json['source']?.toString()),
      );

  final String id;
  final String kind;
  final double value;
  final String unit;

  /// The server's diary day. CLAUDE.md rule 8 — never computed on the client.
  final String diaryDate;

  /// docs/08: an implausible jump. Stored, shown, but excluded from the trend.
  final bool isSuspect;

  /// Where the number came from (D-97). CLAUDE.md rule 10 requires this to be visible wherever the
  /// number is — a figure a phone reported and one a person typed are different claims.
  final MeasurementSource source;
}

/// A reading to send (D-216). `at` is when it was taken; the SERVER turns that into a diary day.
/// `replaceManual` is a person asking for this device figure over one they typed (D-218).
typedef NewMeasurement = ({
  String kind,
  double value,
  String unit,
  MeasurementSource source,
  DateTime at,
  bool replaceManual,
});

/// The sources the server recognises. A closed set, so an unknown string from a newer server
/// degrades to [manual] rather than crashing a screen — and `manual` is the safe wrong answer,
/// because it is the one that says "a person stands behind this" the least loudly.
enum MeasurementSource {
  manual('manual'),
  appleHealth('apple_health'),
  healthConnect('health_connect');

  const MeasurementSource(this.wire);

  final String wire;

  static MeasurementSource fromWire(String? wire) =>
      MeasurementSource.values.firstWhere((s) => s.wire == wire, orElse: () => manual);

  /// True for anything a device reported. The UI cares about the distinction far more often than
  /// it cares which platform did the reporting.
  bool get isAutomatic => this != manual;
}

/// A kind's history plus the server-computed change.
class MeasurementHistory {
  const MeasurementHistory({required this.kind, required this.points, this.change, this.change30d});

  MeasurementHistory.fromJson(Map<String, dynamic> json)
    : this(
        kind: json['kind']?.toString() ?? '',
        points: (json['points'] as List? ?? [])
            .map((p) => Measurement.fromJson(p as Map<String, dynamic>))
            .toList(),
        change: (json['change'] as num?)?.toDouble(),
        change30d: (json['change_30d'] as num?)?.toDouble(),
      );

  final String kind;
  final List<Measurement> points;

  /// From the server's moving average, never min/max (docs/16). Null means no trend yet — which is
  /// NOT the same as zero, and the UI must not render it as one.
  final double? change;

  /// The same discipline over only the last 30 diary days (docs/21 §3) — what the weight card's
  /// sentence prefers, so a month-old loss cannot contradict a visible recent rise. Null falls
  /// back to [change]'s since-start sentence.
  final double? change30d;

  bool get isEmpty => points.isEmpty;
}
