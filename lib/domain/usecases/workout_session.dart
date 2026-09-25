import 'dart:math';

import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';

/// What checking a set off means for the screen: rest now, and what just finished.
typedef CheckOutcome = ({bool rest, bool entryFinished, bool groupFinished, bool allFinished});

/// The workout in progress (ADR-013). Immutable — every change returns a new session, which the
/// controller persists on the phone straight away, so a killed app resumes where it was.
///
/// This is the one piece of training state the phone owns: the server prefilled and progressed the
/// numbers, and it computes volume, records and energy on save. What lives here is only what the
/// person has done so far and where they are in the list.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.entries,
    this.routineId,
    this.bodyWeightKg,
    this.cursor = 0,
    this.asked = const {},
  });

  /// A new session from the server's plan for a routine (or an empty one, for freestyle).
  factory WorkoutSession.start({
    required String name,
    required List<SessionEntry> plan,
    required DateTime now,
    int? routineId,
    double? bodyWeightKg,
    String? id,
  }) => WorkoutSession(
    id: id ?? newId(),
    name: name,
    routineId: routineId,
    startedAt: now,
    bodyWeightKg: bodyWeightKg,
    entries: plan,
  );

  WorkoutSession.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id'] as String,
        name: json['name'] as String,
        routineId: (json['routine_id'] as num?)?.toInt(),
        startedAt: DateTime.parse(json['started_at'] as String),
        bodyWeightKg: (json['body_weight_kg'] as num?)?.toDouble(),
        entries: (json['entries'] as List)
            .map((e) => SessionEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        cursor: (json['cursor'] as num?)?.toInt() ?? 0,
        asked: (json['asked'] as List? ?? []).map((i) => (i as num).toInt()).toSet(),
      );

  /// Made when the workout starts, so a retried save is the same workout on the server.
  final String id;
  final String name;
  final int? routineId;
  final DateTime startedAt;
  final double? bodyWeightKg;
  final List<SessionEntry> entries;

  /// Which group is on screen.
  final int cursor;

  /// Entries whose working weight has already been asked about — asked once, not after every set.
  final Set<int> asked;

  /// A random v4 UUID. The server checks the format; uniqueness is the 122 random bits.
  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Consecutive entries sharing a superset id are one group; everything else is a group of one.
  List<List<int>> get groups {
    final result = <List<int>>[];
    for (var i = 0; i < entries.length; i++) {
      final ss = entries[i].superset;
      if (ss != null && i > 0 && entries[i - 1].superset == ss) {
        result.last.add(i);
      } else {
        result.add([i]);
      }
    }
    return result;
  }

  int get groupCount => groups.length;

  int get currentGroupIndex => groupCount == 0 ? 0 : cursor.clamp(0, groupCount - 1);

  List<int> get currentGroup => groupCount == 0 ? const [] : groups[currentGroupIndex];

  int groupOf(int entry) => groups.indexWhere((g) => g.contains(entry));

  int get totalSets => entries.fold(0, (n, e) => n + e.sets.length);

  int get doneSets => entries.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);

  bool isEntryDone(int entry) =>
      entries[entry].sets.isNotEmpty && entries[entry].sets.every((s) => s.done);

  bool isGroupDone(int group) => groups[group].every(isEntryDone);

  bool get allDone =>
      entries.isNotEmpty && Iterable<int>.generate(entries.length).every(isEntryDone);

  /// How many exercises have at least one set done — "finish early · 3/6 exercises".
  int get startedEntries => entries.where((e) => e.sets.any((s) => s.done)).length;

  Duration elapsed(DateTime now) => now.difference(startedAt);

  WorkoutSession _with({List<SessionEntry>? entries, int? cursor, Set<int>? asked}) =>
      WorkoutSession(
        id: id,
        name: name,
        routineId: routineId,
        startedAt: startedAt,
        bodyWeightKg: bodyWeightKg,
        entries: entries ?? this.entries,
        cursor: cursor ?? this.cursor,
        asked: asked ?? this.asked,
      );

  WorkoutSession _withEntry(int i, SessionEntry entry) => _with(entries: [...entries]..[i] = entry);

  /// A value typed or stepped into a set.
  WorkoutSession withSet(int entry, int set, WorkoutSet value) {
    final sets = [...entries[entry].sets]..[set] = value;
    return _withEntry(entry, entries[entry].copyWith(sets: sets));
  }

  /// Ticks a set on or off.
  ///
  /// Rest follows the group: inside a superset you move straight to its next exercise, and the
  /// rest comes after the LAST exercise of the group — and only while the group still has sets
  /// to do. After an exercise's final set there is no rest; the next exercise is up.
  (WorkoutSession, CheckOutcome) toggle(int entry, int set) {
    final current = entries[entry].sets[set];
    final next = withSet(entry, set, current.copyWith(done: !current.done));
    if (current.done) {
      return (next, (rest: false, entryFinished: false, groupFinished: false, allFinished: false));
    }
    final group = next.groups[next.groupOf(entry)];
    final groupFinished = group.every(next.isEntryDone);
    return (
      next,
      (
        rest: entry == group.last && !groupFinished,
        entryFinished: next.isEntryDone(entry),
        groupFinished: groupFinished,
        allFinished: next.allDone,
      ),
    );
  }

  /// One more set, copying the last one's numbers (not its tick).
  WorkoutSession addSet(int entry) {
    final sets = entries[entry].sets;
    final template = sets.isNotEmpty
        ? sets.last.copyWith(done: false)
        : _blankSet(entries[entry].mode);
    return _withEntry(entry, entries[entry].copyWith(sets: [...sets, template]));
  }

  /// Takes off the last set; the first set always stays.
  WorkoutSession removeSet(int entry) {
    final sets = entries[entry].sets;
    if (sets.length <= 1) return this;
    return _withEntry(entry, entries[entry].copyWith(sets: sets.sublist(0, sets.length - 1)));
  }

  /// An exercise added mid-workout lands as its own group, and the screen moves to it.
  WorkoutSession addEntry(SessionEntry entry) {
    final added = _with(entries: [...entries, entry]);
    return added._with(cursor: added.groupCount - 1);
  }

  WorkoutSession goTo(int group) => _with(cursor: group.clamp(0, max(groupCount - 1, 0)));

  WorkoutSession confirmWorkingWeight(int entry, double kg) => _withEntry(
    entry,
    entries[entry].copyWith(topWeightKg: () => kg),
  )._with(asked: {...asked, entry});

  WorkoutSession markAsked(int entry) => _with(asked: {...asked, entry});

  /// The heaviest done set, for prefilling the working-weight question.
  double heaviestDone(int entry) =>
      entries[entry].sets.where((s) => s.done).fold(0, (m, s) => max(m, s.weightKg ?? 0));

  /// A weighted rep exercise asks for its working weight once all its sets are done — cardio,
  /// timed holds and unloaded bodyweight work have none to confirm.
  bool asksWorkingWeight(int entry) {
    final e = entries[entry];
    return e.mode == ExerciseMode.reps &&
        !asked.contains(entry) &&
        isEntryDone(entry) &&
        heaviestDone(entry) > 0;
  }

  WorkoutDraft finish(DateTime endedAt) => WorkoutDraft(
    id: id,
    routineId: routineId,
    name: name,
    startedAt: startedAt,
    endedAt: endedAt.isBefore(startedAt) ? startedAt : endedAt,
    bodyWeightKg: bodyWeightKg,
    entries: entries,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'routine_id': routineId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'body_weight_kg': bodyWeightKg,
    'entries': [for (final e in entries) e.toJson()],
    'cursor': cursor,
    'asked': asked.toList(),
  };

  static WorkoutSet _blankSet(ExerciseMode mode) => switch (mode) {
    ExerciseMode.cardio => const WorkoutSet(minutes: 20, speedKmh: 8),
    ExerciseMode.time => const WorkoutSet(seconds: 45, weightKg: 0),
    ExerciseMode.reps => const WorkoutSet(weightKg: 0, reps: 10),
  };
}

/// Builds a session entry for an exercise added without a routine, when the server's own
/// `plan_entry` could not be fetched (no signal). Plain defaults, no progression.
SessionEntry offlineEntry({
  required String exerciseId,
  required String name,
  required String bodyPart,
  required bool isCardio,
  required bool isBodyweight,
  String? mediaUrl,
}) {
  final mode = isCardio ? ExerciseMode.cardio : ExerciseMode.reps;
  final target = isCardio
      ? RoutineExercise(exerciseId: exerciseId, mode: mode, sets: 1, minutes: 20, speedKmh: 8)
      : RoutineExercise(exerciseId: exerciseId, mode: mode, sets: 3, reps: 10, weightKg: 0);
  return SessionEntry(
    exerciseId: exerciseId,
    name: name,
    mode: mode,
    bodyPart: bodyPart,
    target: target,
    isBodyweight: isBodyweight,
    mediaUrl: mediaUrl,
    sets: List.generate(
      target.sets,
      (_) => isCardio
          ? const WorkoutSet(minutes: 20, speedKmh: 8)
          : const WorkoutSet(weightKg: 0, reps: 10),
    ),
  );
}
