import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';

/// One set. Only the fields its mode uses are set: weight × reps, a hold in seconds, or minutes at
/// a speed. Effort keeps whichever scale it was rated in.
class WorkoutSet {
  const WorkoutSet({
    this.weightKg,
    this.reps,
    this.seconds,
    this.minutes,
    this.speedKmh,
    this.done = false,
    this.rir,
    this.rpe,
  });

  WorkoutSet.fromJson(Map<String, dynamic> json)
    : this(
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        reps: (json['reps'] as num?)?.toInt(),
        seconds: (json['seconds'] as num?)?.toInt(),
        minutes: (json['minutes'] as num?)?.toDouble(),
        speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
        done: json['done'] as bool? ?? false,
        rir: (json['rir'] as num?)?.toDouble(),
        rpe: (json['rpe'] as num?)?.toDouble(),
      );

  static List<WorkoutSet> listFrom(Object? json) =>
      (json as List? ?? []).map((s) => WorkoutSet.fromJson(s as Map<String, dynamic>)).toList();

  final double? weightKg;
  final int? reps;
  final int? seconds;
  final double? minutes;
  final double? speedKmh;
  final bool done;
  final double? rir;
  final double? rpe;

  Map<String, dynamic> toJson() => {
    if (weightKg != null) 'weight_kg': weightKg,
    if (reps != null) 'reps': reps,
    if (seconds != null) 'seconds': seconds,
    if (minutes != null) 'minutes': minutes,
    if (speedKmh != null) 'speed_kmh': speedKmh,
    'done': done,
    if (rir != null) 'rir': rir,
    if (rpe != null) 'rpe': rpe,
  };

  WorkoutSet copyWith({
    double? weightKg,
    int? reps,
    int? seconds,
    double? minutes,
    double? speedKmh,
    bool? done,
    double? Function()? rir,
    double? Function()? rpe,
  }) => WorkoutSet(
    weightKg: weightKg ?? this.weightKg,
    reps: reps ?? this.reps,
    seconds: seconds ?? this.seconds,
    minutes: minutes ?? this.minutes,
    speedKmh: speedKmh ?? this.speedKmh,
    done: done ?? this.done,
    rir: rir != null ? rir() : this.rir,
    rpe: rpe != null ? rpe() : this.rpe,
  );
}

/// Why a session's numbers are what they are — a code and its figures, which the app words.
class Prescription {
  const Prescription({
    required this.rule,
    required this.kind,
    required this.whyCode,
    this.whyArgs = const {},
  });

  Prescription.fromJson(Map<String, dynamic> json)
    : this(
        rule: ProgressionRule.fromWire(json['rule']?.toString()),
        kind: json['kind']?.toString() ?? 'off',
        whyCode: (json['why'] as Map<String, dynamic>?)?['code']?.toString() ?? 'off',
        whyArgs: Map<String, dynamic>.of(json['why'] as Map<String, dynamic>? ?? const {})
          ..remove('code'),
      );

  final ProgressionRule rule;

  /// 'first' | 'up' | 'hold' | 'deload' | 'off'.
  final String kind;
  final String whyCode;
  final Map<String, dynamic> whyArgs;

  bool get isDeload => kind == 'deload';

  num? arg(String key) => whyArgs[key] as num?;

  Map<String, dynamic> toJson() => {
    'rule': rule.wire,
    'kind': kind,
    'why': {'code': whyCode, ...whyArgs},
  };
}

/// One exercise in a session: the target it was asked for, and its sets as logged so far.
class SessionEntry {
  const SessionEntry({
    required this.exerciseId,
    required this.name,
    required this.mode,
    required this.bodyPart,
    required this.target,
    required this.sets,
    this.isBodyweight = false,
    this.perSide = false,
    this.superset,
    this.prescription,
    this.lastDate,
    this.lastSets = const [],
    this.bestWeightKg,
    this.topWeightKg,
    this.mediaUrl,
    this.muscles = const [],
    this.stepsEn = const [],
    this.stepsHi = const [],
  });

  SessionEntry.fromJson(Map<String, dynamic> json)
    : this(
        exerciseId: json['exercise_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        mode: ExerciseMode.fromWire(json['mode']?.toString()),
        bodyPart: json['body_part']?.toString() ?? '',
        target: RoutineExercise.fromJson(json['target'] as Map<String, dynamic>? ?? const {}),
        sets: WorkoutSet.listFrom(json['sets']),
        isBodyweight: json['is_bodyweight'] as bool? ?? false,
        perSide: json['per_side'] as bool? ?? false,
        superset: json['superset'] as String?,
        prescription: json['prescription'] is Map<String, dynamic>
            ? Prescription.fromJson(json['prescription'] as Map<String, dynamic>)
            : null,
        lastDate: (json['last'] as Map<String, dynamic>?)?['date']?.toString(),
        lastSets: WorkoutSet.listFrom((json['last'] as Map<String, dynamic>?)?['sets']),
        bestWeightKg: (json['best_weight_kg'] as num?)?.toDouble(),
        topWeightKg: (json['top_weight_kg'] as num?)?.toDouble(),
        mediaUrl: json['media_url'] as String?,
        muscles: (json['muscles'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(MuscleShare.fromJson)
            .toList(),
        stepsEn: _stepList(json['steps'], 'en'),
        stepsHi: _stepList(json['steps'], 'hi'),
      );

  static List<String> _stepList(Object? steps, String lang) =>
      ((steps as Map<String, dynamic>?)?[lang] as List? ?? [])
          .map((s) => s.toString())
          .toList();

  final String exerciseId;
  final String name;
  final ExerciseMode mode;
  final String bodyPart;
  final RoutineExercise target;
  final List<WorkoutSet> sets;
  final bool isBodyweight;
  final bool perSide;
  final String? superset;
  final Prescription? prescription;
  final String? lastDate;
  final List<WorkoutSet> lastSets;
  final double? bestWeightKg;

  /// The working weight the person confirmed after the last set.
  final double? topWeightKg;

  /// D-243: null until exercise media is licensed.
  final String? mediaUrl;

  /// Sent with the plan so the workout screen can draw and read the exercise with no signal.
  final List<MuscleShare> muscles;
  final List<String> stepsEn;
  final List<String> stepsHi;

  /// Hindi when the phone reads Hindi and the dataset has it, English otherwise.
  List<String> stepsFor(String languageCode) =>
      languageCode == 'hi' && stepsHi.isNotEmpty ? stepsHi : stepsEn;

  SessionEntry copyWith({List<WorkoutSet>? sets, double? Function()? topWeightKg}) => SessionEntry(
    exerciseId: exerciseId,
    name: name,
    mode: mode,
    bodyPart: bodyPart,
    target: target,
    sets: sets ?? this.sets,
    isBodyweight: isBodyweight,
    perSide: perSide,
    superset: superset,
    prescription: prescription,
    lastDate: lastDate,
    lastSets: lastSets,
    bestWeightKg: bestWeightKg,
    topWeightKg: topWeightKg != null ? topWeightKg() : this.topWeightKg,
    mediaUrl: mediaUrl,
    muscles: muscles,
    stepsEn: stepsEn,
    stepsHi: stepsHi,
  );

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'name': name,
    'mode': mode.wire,
    'body_part': bodyPart,
    'target': target.toJson(),
    'sets': [for (final s in sets) s.toJson()],
    'is_bodyweight': isBodyweight,
    'per_side': perSide,
    'superset': superset,
    if (prescription != null) 'prescription': prescription!.toJson(),
    if (lastDate != null)
      'last': {
        'date': lastDate,
        'sets': [for (final s in lastSets) s.toJson()],
      },
    'best_weight_kg': bestWeightKg,
    'top_weight_kg': topWeightKg,
    'media_url': mediaUrl,
    'muscles': [for (final m in muscles) m.toJson()],
    'steps': {'en': stepsEn, 'hi': stepsHi},
  };
}

/// A finished workout in a list.
class WorkoutSummary {
  const WorkoutSummary({
    required this.id,
    required this.name,
    required this.diaryDate,
    required this.startedAt,
    required this.durationSec,
    required this.setsDone,
    required this.volumeKg,
    this.routineId,
    this.energyKcal,
    this.prCount = 0,
    this.exerciseCount = 0,
  });

  WorkoutSummary.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        routineId: (json['routine_id'] as num?)?.toInt(),
        name: json['name']?.toString() ?? '',
        diaryDate: json['diary_date']?.toString() ?? '',
        startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ?? DateTime(0),
        durationSec: (json['duration_sec'] as num?)?.toInt() ?? 0,
        setsDone: (json['sets_done'] as num?)?.toInt() ?? 0,
        volumeKg: (json['volume_kg'] as num?)?.toDouble() ?? 0,
        energyKcal: (json['energy_kcal'] as num?)?.toInt(),
        prCount: (json['pr_count'] as num?)?.toInt() ?? 0,
        exerciseCount: (json['exercise_count'] as num?)?.toInt() ?? 0,
      );

  static List<WorkoutSummary> listFrom(Object? json) =>
      (json as List? ?? []).map((w) => WorkoutSummary.fromJson(w as Map<String, dynamic>)).toList();

  final String id;
  final int? routineId;
  final String name;

  /// The server's diary day (CLAUDE.md rule 8).
  final String diaryDate;
  final DateTime startedAt;
  final int durationSec;
  final int setsDone;
  final double volumeKg;

  /// D-242: an estimate above resting. Null means not estimated — never shown as 0.
  final int? energyKcal;
  final int prCount;
  final int exerciseCount;
}

class WorkoutRecord {
  const WorkoutRecord({
    required this.exerciseId,
    required this.name,
    required this.kind,
    required this.valueKg,
    this.weightKg,
    this.reps,
  });

  WorkoutRecord.fromJson(Map<String, dynamic> json)
    : this(
        exerciseId: json['exercise_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'weight',
        valueKg: (json['value_kg'] as num?)?.toDouble() ?? 0,
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        reps: (json['reps'] as num?)?.toInt(),
      );

  final String exerciseId;
  final String name;

  /// 'weight' or 'e1rm'.
  final String kind;
  final double valueKg;
  final double? weightKg;
  final int? reps;

  bool get isWeight => kind == 'weight';
}

class MuscleLevel {
  const MuscleLevel({required this.muscle, required this.sets, required this.level});

  MuscleLevel.fromJson(Map<String, dynamic> json)
    : this(
        muscle: json['muscle']?.toString() ?? '',
        sets: (json['sets'] as num?)?.toDouble() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 0,
      );

  static List<MuscleLevel> listFrom(Object? json) =>
      (json as List? ?? []).map((m) => MuscleLevel.fromJson(m as Map<String, dynamic>)).toList();

  final String muscle;

  /// Effective sets: done sets × the muscle's share of each exercise.
  final double sets;

  /// 0 (untrained) to 4, relative to the hardest-worked muscle in the same window.
  final int level;
}

/// Which body weight priced the estimate, and how the session's time was split (D-242).
class EnergyBasis {
  const EnergyBasis({
    required this.weightKg,
    required this.weightSource,
    required this.cardioMinutes,
    required this.strengthMinutes,
  });

  static EnergyBasis? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return EnergyBasis(
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      weightSource: json['weight_source']?.toString() ?? 'profile',
      cardioMinutes: (json['cardio_minutes'] as num?)?.toDouble() ?? 0,
      strengthMinutes: (json['strength_minutes'] as num?)?.toDouble() ?? 0,
    );
  }

  final double weightKg;

  /// 'weigh_in' | 'measurement' | 'profile'.
  final String weightSource;
  final double cardioMinutes;
  final double strengthMinutes;
}

/// One exercise as it was logged.
class LoggedEntry {
  const LoggedEntry({
    required this.exerciseId,
    required this.name,
    required this.mode,
    required this.sets,
    this.topWeightKg,
  });

  LoggedEntry.fromJson(Map<String, dynamic> json)
    : this(
        exerciseId: json['exercise_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        mode: ExerciseMode.fromWire(json['mode']?.toString()),
        sets: WorkoutSet.listFrom(json['sets']),
        topWeightKg: (json['top_weight_kg'] as num?)?.toDouble(),
      );

  final String exerciseId;
  final String name;
  final ExerciseMode mode;
  final List<WorkoutSet> sets;
  final double? topWeightKg;
}

/// A finished workout in full — also what a save returns, so the summary shows the server's own
/// records and estimate rather than the phone's guess at them.
class WorkoutDetail {
  const WorkoutDetail({
    required this.summary,
    required this.entries,
    this.bodyWeightKg,
    this.records = const [],
    this.energyBasis,
    this.muscles = const [],
  });

  WorkoutDetail.fromJson(Map<String, dynamic> json)
    : this(
        summary: WorkoutSummary.fromJson(json),
        bodyWeightKg: (json['body_weight_kg'] as num?)?.toDouble(),
        entries: (json['entries'] as List? ?? [])
            .map((e) => LoggedEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        records: (json['prs'] as List? ?? [])
            .map((p) => WorkoutRecord.fromJson(p as Map<String, dynamic>))
            .toList(),
        energyBasis: EnergyBasis.fromJsonOrNull(json['energy_basis']),
        muscles: MuscleLevel.listFrom(json['muscles']),
      );

  final WorkoutSummary summary;
  final double? bodyWeightKg;
  final List<LoggedEntry> entries;
  final List<WorkoutRecord> records;
  final EnergyBasis? energyBasis;
  final List<MuscleLevel> muscles;
}

/// A finished session, as sent to `POST /gym/workouts`. Its [id] is made when the workout starts,
/// so a save retried after a dropped connection is the same workout on the server.
class WorkoutDraft {
  const WorkoutDraft({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.entries,
    this.routineId,
    this.bodyWeightKg,
  });

  WorkoutDraft.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        routineId: (json['routine_id'] as num?)?.toInt(),
        name: json['name']?.toString() ?? '',
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: DateTime.parse(json['ended_at'] as String),
        bodyWeightKg: (json['body_weight_kg'] as num?)?.toDouble(),
        entries: (json['entries'] as List? ?? [])
            .map((e) => SessionEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final int? routineId;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final double? bodyWeightKg;
  final List<SessionEntry> entries;

  /// The wire body: each entry as the server expects it, nothing more.
  Map<String, dynamic> toWire() => {
    'id': id,
    'routine_id': routineId,
    'name': name,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'body_weight_kg': bodyWeightKg,
    'entries': [
      for (final e in entries)
        {
          'exercise_id': e.exerciseId,
          'mode': e.mode.wire,
          'target': e.target.toJson(),
          'sets': [for (final s in e.sets) s.toJson()],
          'top_weight_kg': e.topWeightKg,
          'superset': e.superset,
        },
    ],
  };

  /// For the offline queue — keeps names so a pending save can still be listed.
  Map<String, dynamic> toJson() => {
    ...toWire(),
    'entries': [for (final e in entries) e.toJson()],
  };
}
