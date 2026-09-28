import 'package:health_pro/domain/entities/gym/workout.dart';

/// One drawn muscle and how much of the work it does (1.0 target, 0.4 supporting).
class MuscleShare {
  const MuscleShare({required this.muscle, required this.weight});

  MuscleShare.fromJson(Map<String, dynamic> json)
    : this(
        muscle: json['muscle']?.toString() ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
      );

  final String muscle;
  final double weight;

  bool get isPrimary => weight >= 1;

  Map<String, dynamic> toJson() => {'muscle': muscle, 'weight': weight};
}

/// A library exercise, or one the person made. Names come from the dataset in English and are
/// shown as they are — they are names, not vocabulary.
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.target,
    this.secondary = const [],
    this.muscles = const [],
    this.isBodyweight = false,
    this.isCardio = false,
    this.isCustom = false,
    this.description,
    this.mediaUrl,
    this.thumbUrl,
  });

  Exercise.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        bodyPart: json['body_part']?.toString() ?? '',
        equipment: json['equipment']?.toString() ?? '',
        target: json['target']?.toString() ?? '',
        secondary: (json['secondary'] as List? ?? []).map((s) => s.toString()).toList(),
        muscles: (json['muscles'] as List? ?? [])
            .map((m) => MuscleShare.fromJson(m as Map<String, dynamic>))
            .toList(),
        isBodyweight: json['is_bodyweight'] as bool? ?? false,
        isCardio: json['is_cardio'] as bool? ?? false,
        isCustom: json['is_custom'] as bool? ?? false,
        description: json['description'] as String?,
        mediaUrl: json['media_url'] as String?,
        thumbUrl: json['thumb_url'] as String?,
      );

  final String id;
  final String name;
  final String bodyPart;
  final String equipment;

  /// The primary muscle in the dataset's words; empty for a custom exercise.
  final String target;
  final List<String> secondary;

  /// Folded onto the drawn muscles by the server.
  final List<MuscleShare> muscles;
  final bool isBodyweight;
  final bool isCardio;
  final bool isCustom;
  final String? description;

  /// D-243: null until exercise media is licensed.
  final String? mediaUrl;
  final String? thumbUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'body_part': bodyPart,
    'equipment': equipment,
    'target': target,
    'secondary': secondary,
    'muscles': [for (final m in muscles) m.toJson()],
    'is_bodyweight': isBodyweight,
    'is_cardio': isCardio,
    'is_custom': isCustom,
    'description': description,
    'media_url': mediaUrl,
    'thumb_url': thumbUrl,
  };
}

/// The best estimated one-rep max, and the set it came from.
class OneRmRecord {
  const OneRmRecord({
    required this.valueKg,
    required this.weightKg,
    required this.reps,
    required this.date,
  });

  static OneRmRecord? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return OneRmRecord(
      valueKg: (json['value_kg'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      date: json['date']?.toString() ?? '',
    );
  }

  final double valueKg;
  final double weightKg;
  final int reps;
  final String date;
}

/// `GET /gym/exercises/:id` — the exercise with its steps, what the person has done with it, and
/// the entry adding it to a workout right now would start with.
class ExerciseDetail {
  const ExerciseDetail({
    required this.exercise,
    required this.stepsEn,
    required this.stepsHi,
    required this.planEntry,
    this.bestWeightKg,
    this.bestE1rm,
    this.lastDate,
    this.lastSets = const [],
    this.routineIds = const [],
  });

  ExerciseDetail.fromJson(Map<String, dynamic> json)
    : this(
        exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
        stepsEn: _steps(json['exercise'], 'en'),
        stepsHi: _steps(json['exercise'], 'hi'),
        planEntry: SessionEntry.fromJson(json['plan_entry'] as Map<String, dynamic>),
        bestWeightKg: (json['best_weight_kg'] as num?)?.toDouble(),
        bestE1rm: OneRmRecord.fromJsonOrNull(json['best_e1rm']),
        lastDate: (json['last'] as Map<String, dynamic>?)?['date']?.toString(),
        lastSets: WorkoutSet.listFrom((json['last'] as Map<String, dynamic>?)?['sets']),
        routineIds: (json['routine_ids'] as List? ?? []).map((i) => (i as num).toInt()).toList(),
      );

  final Exercise exercise;
  final List<String> stepsEn;
  final List<String> stepsHi;
  final SessionEntry planEntry;
  final double? bestWeightKg;
  final OneRmRecord? bestE1rm;
  final String? lastDate;
  final List<WorkoutSet> lastSets;

  /// The routines it is already in.
  final List<int> routineIds;

  /// Hindi when the phone reads Hindi and the dataset has it, English otherwise.
  List<String> stepsFor(String languageCode) =>
      languageCode == 'hi' && stepsHi.isNotEmpty ? stepsHi : stepsEn;

  static List<String> _steps(Object? exercise, String lang) {
    final steps = (exercise as Map<String, dynamic>?)?['steps'] as Map<String, dynamic>?;
    return (steps?[lang] as List? ?? []).map((s) => s.toString()).toList();
  }
}
