import 'package:health_pro/domain/entities/food.dart';

/// One meal slot's share of the day. docs/04 §5 — the split comes from the rule pack and is
/// applied server-side (CLAUDE.md rule 2), so nothing here multiplies a percentage.
class MealTarget {
  const MealTarget({
    required this.slot,
    required this.pct,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
  });

  MealTarget.fromJson(Map<String, dynamic> json)
    : this(
        slot: json['slot']?.toString() ?? '',
        pct: (json['pct'] as num?)?.toDouble() ?? 0,
        kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        carbG: (json['carb_g'] as num?)?.toDouble() ?? 0,
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      );

  final String slot;
  final double pct;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
}

/// `GET /plans/current`.
class Plan {
  const Plan({
    required this.id,
    required this.validFrom,
    required this.mealTargets,
    required this.rulePackVersion,
    required this.warnings,
    this.targets,
    this.fibreG,
    this.waterMl,
  });

  /// `GET /plans/current` returns null when no plan exists; the caller handles that as Empty.
  static Plan? fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>?;
    if (plan == null) return null;

    final targets = plan['targets'] as Map<String, dynamic>?;

    return Plan(
      id: plan['id']?.toString() ?? '',
      validFrom: plan['valid_from']?.toString() ?? '',
      targets: targets == null
          ? null
          : Macros(
              kcal: (targets['kcal'] as num?)?.toDouble() ?? 0,
              proteinG: (targets['proteinG'] as num?)?.toDouble() ?? 0,
              carbG: (targets['carbG'] as num?)?.toDouble() ?? 0,
              fatG: (targets['fatG'] as num?)?.toDouble() ?? 0,
            ),
      // The engine has always sent these two alongside the four macros; nothing asked for them
      // until the plan screen had somewhere to put them (D-130). Nullable, because a plan from
      // before they existed is still a plan.
      fibreG: (targets?['fibreG'] as num?)?.toDouble(),
      waterMl: (targets?['waterMl'] as num?)?.toDouble(),
      mealTargets: (plan['meal_targets'] as List? ?? [])
          .map((m) => MealTarget.fromJson(m as Map<String, dynamic>))
          .toList(),
      rulePackVersion: json['rule_pack_version']?.toString() ?? '',
      // docs/05 §7 safety-clamp copy, verbatim from the server (rule 7).
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => (w as Map<String, dynamic>)['user_message']?.toString() ?? '')
          .where((m) => m.isNotEmpty)
          .toList(),
    );
  }

  final String id;
  final String validFrom;
  final Macros? targets;
  final List<MealTarget> mealTargets;

  /// A day's fibre target. There is no consumed figure to put beside it: a food log row copies
  /// kcal and the three macros and nothing else, so counting fibre eaten needs a column and a
  /// migration, not a widget.
  final double? fibreG;

  /// A day's water target — the same number the diary carries, from the same plan.
  final double? waterMl;
  final String rulePackVersion;

  /// docs/05 §7 safety-clamp copy, verbatim from the server (rule 7).
  final List<String> warnings;
}

/// A food the user may choose for a meal (D-82).
///
/// NOT the plan's contents. The engine's candidate pool picks foods AND portions to hit a slot's
/// targets (docs/04 steps 11–14) and is not built. This is the food table filtered by what the user
/// has already told us — preference, allergies, budget, condition tags — for them to choose from.
class FoodOption {
  const FoodOption({
    required this.id,
    required this.name,
    required this.kcalPer100g,
    this.nameHi,
    this.measureLabel,
    this.measureGrams,
    this.kcalPerMeasure,
    this.imageUrl,
    this.imageAttribution,
  });

  FoodOption.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nameHi: json['name_hi']?.toString(),
        kcalPer100g: (json['kcal_per_100g'] as num?)?.toDouble() ?? 0,
        measureLabel: (json['default_measure'] as Map<String, dynamic>?)?['label']?.toString(),
        measureGrams: ((json['default_measure'] as Map<String, dynamic>?)?['grams'] as num?)
            ?.toDouble(),
        kcalPerMeasure: (json['kcal_per_measure'] as num?)?.toInt(),
        imageUrl: json['image_url']?.toString(),
        imageAttribution: json['image_attribution']?.toString(),
      );

  final String id;
  final String name;
  final String? nameHi;
  final double kcalPer100g;

  /// The household measure a person would say out loud — "1 katori". Null when the food has none,
  /// in which case the log falls back to grams.
  final String? measureLabel;
  final double? measureGrams;
  final int? kcalPerMeasure;

  /// Relative to the API root — the client joins it to its own base URL, so the same record works
  /// against a laptop, a LAN address and production without the server knowing which.
  final String? imageUrl;

  /// The credit the photograph must be shown with (D-83). CC BY and CC BY-SA require it, so this
  /// is not optional decoration: no image is rendered without a route to its attribution.
  final String? imageAttribution;

  /// The same option with [imageUrl] resolved against the API's base URL.
  FoodOption absolute(String baseUrl) {
    final path = imageUrl;
    if (path == null || path.startsWith('http')) return this;
    return FoodOption(
      id: id,
      name: name,
      nameHi: nameHi,
      kcalPer100g: kcalPer100g,
      measureLabel: measureLabel,
      measureGrams: measureGrams,
      kcalPerMeasure: kcalPerMeasure,
      imageUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path',
      imageAttribution: imageAttribution,
    );
  }
}
