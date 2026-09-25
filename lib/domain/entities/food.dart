import 'package:health_pro/domain/entities/measurement.dart';

/// The server sends photo paths relative to itself (`/food-images/…`, D-83); this makes one
/// absolute. Already-absolute URLs, and a null base (a parse with nowhere to resolve against),
/// pass through unchanged.
String? resolveImageUrl(String? path, String? baseUrl) {
  if (path == null || baseUrl == null || path.startsWith('http')) return path;
  return '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path';
}

/// A searchable food plus its household measures. docs/03 §1 — nutrition is per 100 g edible
/// portion, so anything the user sees is scaled from these numbers by the server.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.kcalPer100g,
    required this.measures,
    this.nameHi,
    this.imageUrl,
    this.imageAttribution,
    this.proteinPer100g,
    this.carbPer100g,
    this.fatPer100g,
  });

  Food.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nameHi: json['nameHi']?.toString(),
        kcalPer100g: double.tryParse(json['kcal']?.toString() ?? '') ?? 0,
        measures: (json['measures'] as List? ?? [])
            .map((m) => HouseholdMeasure.fromJson(m as Map<String, dynamic>))
            .toList(),
        imageUrl: json['image_url']?.toString(),
        imageAttribution: json['image_attribution']?.toString(),
        // The server's own per-100 g figures (numeric columns arrive as strings). Displayed as
        // they are — never scaled here (rule 2); a portion's numbers come from the preview.
        proteinPer100g: double.tryParse(json['proteinG']?.toString() ?? ''),
        carbPer100g: double.tryParse(json['carbG']?.toString() ?? ''),
        fatPer100g: double.tryParse(json['fatG']?.toString() ?? ''),
      );

  final String id;
  final String name;
  final String? nameHi;
  final double kcalPer100g;
  final List<HouseholdMeasure> measures;

  /// Null when the server did not send the figure — the row then shows no macro line rather than
  /// a zero it does not know (D-43).
  final double? proteinPer100g;
  final double? carbPer100g;
  final double? fatPer100g;

  /// Relative until the data source resolves it — see [absolute] (D-83).
  final String? imageUrl;

  /// The credit the photograph must be shown with. Required by CC BY and CC BY-SA.
  final String? imageAttribution;

  /// The same food with [imageUrl] resolved against the API's base URL.
  Food absolute(String baseUrl) {
    final path = imageUrl;
    if (path == null || path.startsWith('http')) return this;
    return Food(
      id: id,
      name: name,
      nameHi: nameHi,
      kcalPer100g: kcalPer100g,
      measures: measures,
      imageUrl: resolveImageUrl(path, baseUrl),
      imageAttribution: imageAttribution,
      proteinPer100g: proteinPer100g,
      carbPer100g: carbPer100g,
      fatPer100g: fatPer100g,
    );
  }

  /// docs/03 §units: the household measure is primary. A food with none can still be logged in
  /// grams, but the measure is what the user is offered first.
  HouseholdMeasure? get defaultMeasure =>
      measures.where((m) => m.isDefault).firstOrNull ?? measures.firstOrNull;
}

class HouseholdMeasure {
  const HouseholdMeasure({required this.label, required this.grams, required this.isDefault});

  HouseholdMeasure.fromJson(Map<String, dynamic> json)
    : this(
        label: json['label']?.toString() ?? '',
        grams: double.tryParse(json['grams']?.toString() ?? '') ?? 0,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  final String label;
  final double grams;
  final bool isDefault;
}

/// `POST /logs/food/preview` (D-238): what a chosen portion carries, scaled by the server with the
/// same code that will scale the diary entry — so the add sheet shows exactly what gets logged.
class NutritionPreview {
  const NutritionPreview({
    required this.grams,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.fibreG,
    required this.sodiumMg,
    required this.addedSugarG,
    required this.saturatedFatG,
  });

  NutritionPreview.fromJson(Map<String, dynamic> json)
    : this(
        grams: _num(json['grams']),
        kcal: _num(json['kcal']),
        proteinG: _num(json['protein_g']),
        carbG: _num(json['carb_g']),
        fatG: _num(json['fat_g']),
        fibreG: _num(json['fibre_g']),
        sodiumMg: _num(json['sodium_mg']),
        addedSugarG: _num(json['added_sugar_g']),
        saturatedFatG: _num(json['saturated_fat_g']),
      );

  /// Several portions together — a scanned plate's kept items (D-240). One decimal, as the server
  /// rounds its own sum.
  factory NutritionPreview.sum(Iterable<NutritionPreview> parts) {
    double total(double Function(NutritionPreview) pick) =>
        double.parse(parts.fold<double>(0, (s, p) => s + pick(p)).toStringAsFixed(1));
    return NutritionPreview(
      grams: total((p) => p.grams),
      kcal: total((p) => p.kcal),
      proteinG: total((p) => p.proteinG),
      carbG: total((p) => p.carbG),
      fatG: total((p) => p.fatG),
      fibreG: total((p) => p.fibreG),
      sodiumMg: total((p) => p.sodiumMg),
      addedSugarG: total((p) => p.addedSugarG),
      saturatedFatG: total((p) => p.saturatedFatG),
    );
  }

  final double grams;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final double fibreG;
  final double sodiumMg;
  final double addedSugarG;
  final double saturatedFatG;

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
}

/// One diary entry.
class LogEntry {
  const LogEntry({
    required this.id,
    required this.slot,
    required this.name,
    required this.quantityG,
    required this.kcal,
    required this.locked,
    this.measureLabel,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.imageUrl,
    this.imageAttribution,
    this.estimated = false,
  });

  /// [imageBase] is the API's base URL, which the photo path is resolved against.
  LogEntry.fromJson(Map<String, dynamic> json, {String? imageBase})
    : this(
        id: json['id']?.toString() ?? '',
        slot: json['slot']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        quantityG: (json['quantity_g'] as num?)?.toDouble() ?? 0,
        measureLabel: json['measure_label']?.toString(),
        kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
        // The server has always sent these per entry; nothing parsed them until Home's meal rows
        // needed what was EATEN by slot rather than what the plan prescribes (D-140).
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        carbG: (json['carb_g'] as num?)?.toDouble() ?? 0,
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
        locked: json['locked'] as bool? ?? false,
        imageUrl: resolveImageUrl(json['image_url']?.toString(), imageBase),
        imageAttribution: json['image_attribution']?.toString(),
        estimated: json['estimated'] as bool? ?? false,
      );

  final String id;
  final String slot;
  final String name;
  final double quantityG;
  final String? measureLabel;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// docs/08: editable for 48 h, then part of the record.
  final bool locked;

  /// The food's photograph (docs/21 §6) and the credit it is shown with (D-83). Null for a custom
  /// entry, or a food without one.
  final String? imageUrl;
  final String? imageAttribution;

  /// D-240. The nutrition is a model's estimate of a photographed plate (and [imageUrl] is the
  /// user's own photo) — shown as one, never passed off as the food table's figures.
  final bool estimated;
}

class Macros {
  const Macros({
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    this.fibreG,
  });

  Macros.fromJson(Map<String, dynamic> json)
    : this(
        kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        carbG: (json['carb_g'] as num?)?.toDouble() ?? 0,
        fibreG: (json['fibre_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      );

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// Fibre, when the server sends it (D-136): the day's summed grams on totals, the plan's target
  /// on targets. Null from an older server, or on a plan from before the engine exposed it.
  final double? fibreG;
}

/// `GET /logs/day`.
class DiaryDay {
  const DiaryDay({
    required this.diaryDate,
    required this.entries,
    required this.totals,
    this.targets,
    this.steps,
    this.stepsSource = MeasurementSource.manual,
    this.stepsAdded,
    this.energyBurnedKcal,
    this.workoutKcal,
    this.waterLoggedMl,
    this.waterTargetMl,
    this.windowStart,
    this.windowEnd,
  });

  /// [imageBase] is the API's base URL, which the entries' photo paths are resolved against.
  DiaryDay.fromJson(Map<String, dynamic> json, {String? imageBase})
    : this(
        diaryDate: json['diary_date']?.toString() ?? '',
        entries: (json['entries'] as List? ?? [])
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>, imageBase: imageBase))
            .toList(),
        totals: Macros.fromJson(json['totals'] as Map<String, dynamic>? ?? const {}),
        targets: json['targets'] == null
            ? null
            : Macros.fromJson(json['targets']! as Map<String, dynamic>),
        steps: ((json['activity'] as Map<String, dynamic>?)?['steps'] as num?)?.toInt(),
        stepsSource: MeasurementSource.fromWire(
          (json['activity'] as Map<String, dynamic>?)?['steps_source']?.toString(),
        ),
        stepsAdded: ((json['activity'] as Map<String, dynamic>?)?['steps_added'] as num?)?.toInt(),
        windowStart: DateTime.tryParse(
          (json['diary_window'] as Map<String, dynamic>?)?['start']?.toString() ?? '',
        ),
        windowEnd: DateTime.tryParse(
          (json['diary_window'] as Map<String, dynamic>?)?['end']?.toString() ?? '',
        ),
        energyBurnedKcal:
            ((json['activity'] as Map<String, dynamic>?)?['energy_burned_kcal'] as num?)?.toInt(),
        workoutKcal: ((json['activity'] as Map<String, dynamic>?)?['workout_kcal'] as num?)
            ?.toInt(),
        waterLoggedMl: ((json['water'] as Map<String, dynamic>?)?['logged_ml'] as num?)?.toInt(),
        waterTargetMl: ((json['water'] as Map<String, dynamic>?)?['target_ml'] as num?)?.toInt(),
      );

  final String diaryDate;
  final List<LogEntry> entries;
  final Macros totals;

  /// What the user reported moving today (D-80). Null is NOT RECORDED, never zero: "you burned
  /// nothing" and "we are not measuring" are different sentences and only one of them is true.
  final int? steps;

  /// Where [steps] came from (D-97). Rule 10: the app must be able to say, wherever the count is
  /// shown, whether a phone reported it or a person typed it.
  final MeasurementSource stepsSource;

  /// How much of [steps] the person added (or, negative, took off) by hand (D-221). Already in
  /// [steps]; null when they changed nothing. What a device counted is `steps - stepsAdded`.
  final int? stepsAdded;

  final int? energyBurnedKcal;

  /// D-242: the server's estimate of what the day's gym workouts burned above resting. Its OWN
  /// figure — never part of [energyBurnedKcal] (a watch that tracked the session already counts
  /// it) and never taken off what is left to eat. Null when nothing was estimated.
  final int? workoutKcal;

  /// Hydration (D-86). Logged is null until the user records any; the target is the engine's and is
  /// null until a plan exists — never zero, which would read as "you should drink nothing".
  final int? waterLoggedMl;
  final int? waterTargetMl;

  /// Null when no plan exists. NOT zero — the UI must say "no plan yet" rather than show progress
  /// against a target of nothing.
  final Macros? targets;

  /// The instants this diary day spans, from the SERVER (D-98). A step sync asks the phone for the
  /// steps between them. Null on an older server, and a sync that cannot be told the window does
  /// not guess one — CLAUDE.md rule 8 keeps the 04:00 IST boundary in one place, and a client that
  /// derived it would put a 1 a.m. walk on the wrong day.
  final DateTime? windowStart;
  final DateTime? windowEnd;

  bool get isEmpty => entries.isEmpty;
}
