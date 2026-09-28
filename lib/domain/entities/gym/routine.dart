import 'package:health_pro/domain/entities/gym/gym_enums.dart';

/// One exercise as a routine prescribes it. Immutable; the editor builds a new one per change.
/// Only the fields its [mode] uses mean anything.
class RoutineExercise {
  const RoutineExercise({
    required this.exerciseId,
    required this.mode,
    required this.sets,
    this.reps,
    this.weightKg,
    this.seconds,
    this.minutes,
    this.speedKmh,
    this.bodyweight,
    this.perSide,
    this.progression,
    this.increment,
    this.repsMin,
    this.repsMax,
    this.superset,
  });

  RoutineExercise.fromJson(Map<String, dynamic> json)
    : this(
        exerciseId: json['exercise_id']?.toString() ?? '',
        mode: ExerciseMode.fromWire(json['mode']?.toString()),
        sets: (json['sets'] as num?)?.toInt() ?? 1,
        reps: (json['reps'] as num?)?.toInt(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        seconds: (json['seconds'] as num?)?.toInt(),
        minutes: (json['minutes'] as num?)?.toDouble(),
        speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
        bodyweight: json['bodyweight'] as bool?,
        perSide: json['per_side'] as bool?,
        progression: ProgressionRule.fromWireOrNull(json['progression'] as String?),
        increment: (json['increment'] as num?)?.toDouble(),
        repsMin: (json['reps_min'] as num?)?.toInt(),
        repsMax: (json['reps_max'] as num?)?.toInt(),
        superset: json['superset'] as String?,
      );

  final String exerciseId;
  final ExerciseMode mode;
  final int sets;
  final int? reps;

  /// Added weight when done at bodyweight.
  final double? weightKg;
  final int? seconds;
  final double? minutes;
  final double? speedKmh;

  /// Overrides the library's own flag; null follows it.
  final bool? bodyweight;
  final bool? perSide;

  /// Overrides the routine's rule; null follows it.
  final ProgressionRule? progression;
  final double? increment;
  final int? repsMin;
  final int? repsMax;

  /// Adjacent exercises sharing this id are one superset.
  final String? superset;

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'mode': mode.wire,
    'sets': sets,
    if (reps != null) 'reps': reps,
    if (weightKg != null) 'weight_kg': weightKg,
    if (seconds != null) 'seconds': seconds,
    if (minutes != null) 'minutes': minutes,
    if (speedKmh != null) 'speed_kmh': speedKmh,
    if (bodyweight != null) 'bodyweight': bodyweight,
    if (perSide != null) 'per_side': perSide,
    if (progression != null) 'progression': progression!.wire,
    if (increment != null) 'increment': increment,
    if (repsMin != null) 'reps_min': repsMin,
    if (repsMax != null) 'reps_max': repsMax,
    if (superset != null) 'superset': superset,
  };

  /// A nullable field is cleared by passing a function returning null — `copyWith(superset: () =>
  /// null)` — because a plain null would mean "unchanged".
  RoutineExercise copyWith({
    ExerciseMode? mode,
    int? sets,
    int? Function()? reps,
    double? Function()? weightKg,
    int? Function()? seconds,
    double? Function()? minutes,
    double? Function()? speedKmh,
    bool? Function()? bodyweight,
    bool? Function()? perSide,
    ProgressionRule? Function()? progression,
    double? Function()? increment,
    int? Function()? repsMin,
    int? Function()? repsMax,
    String? Function()? superset,
  }) => RoutineExercise(
    exerciseId: exerciseId,
    mode: mode ?? this.mode,
    sets: sets ?? this.sets,
    reps: reps != null ? reps() : this.reps,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    seconds: seconds != null ? seconds() : this.seconds,
    minutes: minutes != null ? minutes() : this.minutes,
    speedKmh: speedKmh != null ? speedKmh() : this.speedKmh,
    bodyweight: bodyweight != null ? bodyweight() : this.bodyweight,
    perSide: perSide != null ? perSide() : this.perSide,
    progression: progression != null ? progression() : this.progression,
    increment: increment != null ? increment() : this.increment,
    repsMin: repsMin != null ? repsMin() : this.repsMin,
    repsMax: repsMax != null ? repsMax() : this.repsMax,
    superset: superset != null ? superset() : this.superset,
  );
}

/// A routine's exercise with what the list needs to draw it.
class RoutineItem {
  const RoutineItem({
    required this.config,
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.isBodyweight,
    required this.isCardio,
  });

  RoutineItem.fromJson(Map<String, dynamic> json)
    : this(
        config: RoutineExercise.fromJson(json),
        name: json['name']?.toString() ?? '',
        bodyPart: json['body_part']?.toString() ?? '',
        equipment: json['equipment']?.toString() ?? '',
        isBodyweight: json['is_bodyweight'] as bool? ?? false,
        isCardio: json['is_cardio'] as bool? ?? false,
      );

  final RoutineExercise config;
  final String name;
  final String bodyPart;
  final String equipment;

  /// After the config's own override.
  final bool isBodyweight;
  final bool isCardio;

  RoutineItem withConfig(RoutineExercise next) => RoutineItem(
    config: next,
    name: name,
    bodyPart: bodyPart,
    equipment: equipment,
    isBodyweight: next.bodyweight ?? isBodyweight,
    isCardio: isCardio,
  );

  Map<String, dynamic> toJson() => {
    ...config.toJson(),
    'name': name,
    'body_part': bodyPart,
    'equipment': equipment,
    'is_bodyweight': isBodyweight,
    'is_cardio': isCardio,
  };
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.icon,
    required this.progression,
    required this.items,
  });

  Routine.fromJson(Map<String, dynamic> json)
    : this(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        icon: RoutineIcon.fromWire(json['icon']?.toString()),
        progression: ProgressionRule.fromWire(json['progression']?.toString()),
        items: (json['exercises'] as List? ?? [])
            .map((e) => RoutineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final String name;
  final RoutineIcon icon;
  final ProgressionRule progression;
  final List<RoutineItem> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon.wire,
    'progression': progression.wire,
    'exercises': [for (final i in items) i.toJson()],
  };
}

/// What the editor sends. `id` null creates a routine.
class RoutineDraft {
  const RoutineDraft({
    required this.name,
    required this.icon,
    required this.progression,
    required this.exercises,
    this.id,
  });

  final int? id;
  final String name;
  final RoutineIcon icon;
  final ProgressionRule progression;
  final List<RoutineExercise> exercises;

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon.wire,
    'progression': progression.wire,
    'exercises': [for (final e in exercises) e.toJson()],
  };
}
