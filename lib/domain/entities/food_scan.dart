import 'package:health_pro/domain/entities/food.dart';

/// `GET /foods/scan/status` (D-238): whether this person may scan a meal now. The SERVER decides
/// every field (rule 3) — the app only renders it.
class ScanStatus {
  const ScanStatus({
    required this.allowed,
    required this.remainingToday,
    required this.requiresAd,
    this.reason,
    this.userMessage,
  });

  ScanStatus.fromJson(Map<String, dynamic> json)
    : this(
        allowed: json['allowed'] as bool? ?? false,
        reason: json['reason'] as String?,
        remainingToday: (json['remaining_today'] as num?)?.toInt() ?? 0,
        requiresAd: json['requires_ad'] as bool? ?? false,
        userMessage: json['user_message'] as String?,
      );

  final bool allowed;

  /// `disabled` | `trial_over` | `limit_reached`, or null when allowed.
  final String? reason;
  final int remainingToday;

  /// A rewarded ad comes before the scan.
  final bool requiresAd;

  /// The server's words for a denial (rule 7); null when allowed.
  final String? userMessage;

  /// Not a daily cap but the plan itself — the upgrade sheet is the answer (rule 3).
  bool get needsUpgrade => reason == 'disabled' || reason == 'trial_over';
}

/// One thing on the photographed plate, with the model's nutrition for its weight (D-240).
class ScanItem {
  const ScanItem({required this.name, required this.nutrition});

  ScanItem.fromJson(Map<String, dynamic> json)
    : this(name: json['name']?.toString() ?? '', nutrition: NutritionPreview.fromJson(json));

  final String name;
  final NutritionPreview nutrition;
}

/// `POST /foods/scan` (D-240): a model's ESTIMATE of the plate, item by item. Nothing is logged
/// until the user confirms; the server then sums the items they kept from its own stored copy.
class ScanEstimate {
  const ScanEstimate({
    required this.scanId,
    required this.dishName,
    required this.confidence,
    required this.items,
  });

  ScanEstimate.fromJson(Map<String, dynamic> json)
    : this(
        scanId: (json['scan_id'] as num?)?.toInt(),
        dishName: json['dish_name']?.toString() ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        items: [
          for (final item in (json['items'] as List<dynamic>?) ?? const [])
            ScanItem.fromJson(item as Map<String, dynamic>),
        ],
      );

  /// Null when the photo was not food — nothing was stored.
  final int? scanId;
  final String dishName;
  final double confidence;
  final List<ScanItem> items;

  bool get recognised => scanId != null && items.isNotEmpty;

  /// What the kept items add up to, for the confirm sheet — the same sum the server makes from
  /// its stored copy when the user says yes (`sumItems`), so the sheet shows what gets logged.
  NutritionPreview totalOf(Set<int> kept) => NutritionPreview.sum([
    for (final (i, item) in items.indexed)
      if (kept.contains(i)) item.nutrition,
  ]);
}
