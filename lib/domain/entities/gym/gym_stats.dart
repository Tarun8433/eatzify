import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';

/// One heatmap square. The grid — 53 Monday-first weeks ending this week — is laid out by the
/// server, so the phone never walks a calendar.
class HeatCell {
  const HeatCell({
    required this.date,
    required this.minutes,
    required this.workouts,
    required this.level,
    required this.future,
  });

  HeatCell.fromJson(Map<String, dynamic> json)
    : this(
        date: json['date']?.toString() ?? '',
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        workouts: (json['workouts'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 0,
        future: json['future'] as bool? ?? false,
      );

  final String date;
  final int minutes;
  final int workouts;

  /// 0 nothing … 4 among this person's longest days.
  final int level;
  final bool future;
}

class MuscleBalance {
  const MuscleBalance({
    required this.window,
    required this.hard,
    required this.hasHardSets,
    required this.workouts,
    required this.levels,
    required this.untrained,
    required this.top,
  });

  MuscleBalance.fromJson(Map<String, dynamic> json)
    : this(
        window: json['window']?.toString() ?? 'week',
        hard: json['hard'] as bool? ?? false,
        hasHardSets: json['has_hard_sets'] as bool? ?? false,
        workouts: (json['workouts'] as num?)?.toInt() ?? 0,
        levels: MuscleLevel.listFrom(json['levels']),
        untrained: (json['untrained'] as List? ?? []).map((m) => m.toString()).toList(),
        top: MuscleLevel.listFrom(json['top']),
      );

  final String window;
  final bool hard;
  final bool hasHardSets;
  final int workouts;
  final List<MuscleLevel> levels;

  /// Listed neutrally — "not trained in this period", never "missed" (docs/05 §6).
  final List<String> untrained;
  final List<MuscleLevel> top;

  Map<String, int> get levelByMuscle => {for (final l in levels) l.muscle: l.level};
}

class EffortSummary {
  const EffortSummary({
    required this.window,
    required this.scale,
    required this.rated,
    required this.finished,
    required this.weekly,
    required this.histogram,
    this.average,
    this.hardPct,
  });

  EffortSummary.fromJson(Map<String, dynamic> json)
    : this(
        window: json['window']?.toString() ?? '90d',
        scale: EffortScale.fromWire(json['scale']?.toString()),
        rated: (json['rated'] as num?)?.toInt() ?? 0,
        finished: (json['finished'] as num?)?.toInt() ?? 0,
        average: (json['average'] as num?)?.toDouble(),
        hardPct: (json['hard_pct'] as num?)?.toInt(),
        weekly: (json['weekly'] as List? ?? [])
            .map(
              (w) => (
                weekStart: (w as Map<String, dynamic>)['week_start'].toString(),
                average: (w['average'] as num).toDouble(),
              ),
            )
            .toList(),
        histogram: (json['histogram'] as List? ?? [])
            .map(
              (b) => (
                bucket: (b as Map<String, dynamic>)['bucket'].toString(),
                count: (b['count'] as num).toInt(),
              ),
            )
            .toList(),
      );

  final String window;

  /// The scale the averages are shown in — the one the person uses now.
  final EffortScale scale;
  final int rated;
  final int finished;

  /// Null below five rated sets: an average of three sets is noise.
  final double? average;
  final int? hardPct;
  final List<({String weekStart, double average})> weekly;

  /// Reps in reserve: '0', '1', '2', '3', '4+'.
  final List<({String bucket, int count})> histogram;
}

class GymStats {
  const GymStats({
    required this.totalWorkouts,
    required this.thisMonth,
    required this.streakWeeks,
    required this.heatmap,
    required this.muscles,
    required this.energyDays,
    required this.recent,
    required this.exercises,
    this.weekKcal,
    this.effort,
  });

  GymStats.fromJson(Map<String, dynamic> json)
    : this(
        totalWorkouts: _tile(json, 'total_workouts'),
        thisMonth: _tile(json, 'this_month'),
        streakWeeks: _tile(json, 'streak_weeks'),
        weekKcal: ((json['tiles'] as Map<String, dynamic>?)?['week_kcal'] as num?)?.toInt(),
        heatmap: (json['heatmap'] as List? ?? [])
            .map(
              (week) =>
                  (week as List).map((c) => HeatCell.fromJson(c as Map<String, dynamic>)).toList(),
            )
            .toList(),
        muscles: MuscleBalance.fromJson(json['muscles'] as Map<String, dynamic>? ?? const {}),
        effort: json['effort'] is Map<String, dynamic>
            ? EffortSummary.fromJson(json['effort'] as Map<String, dynamic>)
            : null,
        energyDays: (((json['energy'] as Map<String, dynamic>?)?['days'] as List?) ?? [])
            .map(
              (d) => (
                date: (d as Map<String, dynamic>)['date'].toString(),
                kcal: (d['kcal'] as num?)?.toInt(),
              ),
            )
            .toList(),
        recent: WorkoutSummary.listFrom(json['recent']),
        exercises: (json['exercises'] as List? ?? [])
            .map(
              (e) => (id: (e as Map<String, dynamic>)['id'].toString(), name: e['name'].toString()),
            )
            .toList(),
      );

  final int totalWorkouts;
  final int thisMonth;
  final int streakWeeks;
  final int? weekKcal;
  final List<List<HeatCell>> heatmap;
  final MuscleBalance muscles;

  /// Null until the person has rated a set.
  final EffortSummary? effort;

  /// The last 30 diary days, oldest first; kcal null where nothing was estimated.
  final List<({String date, int? kcal})> energyDays;
  final List<WorkoutSummary> recent;

  /// Exercises with history, for the progress picker.
  final List<({String id, String name})> exercises;

  bool get isEmpty => totalWorkouts == 0;

  static int _tile(Map<String, dynamic> json, String key) =>
      ((json['tiles'] as Map<String, dynamic>?)?[key] as num?)?.toInt() ?? 0;
}

class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.source,
    required this.workouts,
    this.routineId,
  });

  CalendarDay.fromJson(Map<String, dynamic> json)
    : this(
        date: json['date']?.toString() ?? '',
        inMonth: json['in_month'] as bool? ?? false,
        isToday: json['is_today'] as bool? ?? false,
        routineId: (json['routine_id'] as num?)?.toInt(),
        source: DaySource.fromWire(json['source']?.toString()),
        workouts: (json['workouts'] as List? ?? [])
            .map(
              (w) => (
                id: (w as Map<String, dynamic>)['id'].toString(),
                name: w['name'].toString(),
                energyKcal: (w['energy_kcal'] as num?)?.toInt(),
              ),
            )
            .toList(),
      );

  final String date;
  final bool inMonth;
  final bool isToday;
  final int? routineId;
  final DaySource source;
  final List<({String id, String name, int? energyKcal})> workouts;

  bool get trained => workouts.isNotEmpty;
}

class GymCalendar {
  const GymCalendar({
    required this.month,
    required this.weeks,
    required this.workouts,
    required this.minutes,
    required this.volumeKg,
    this.kcal,
  });

  GymCalendar.fromJson(Map<String, dynamic> json)
    : this(
        month: json['month']?.toString() ?? '',
        weeks: (json['weeks'] as List? ?? [])
            .map(
              (w) =>
                  (w as List).map((d) => CalendarDay.fromJson(d as Map<String, dynamic>)).toList(),
            )
            .toList(),
        workouts: _summary(json, 'workouts'),
        minutes: _summary(json, 'minutes'),
        volumeKg: _summary(json, 'volume_kg'),
        kcal: ((json['summary'] as Map<String, dynamic>?)?['kcal'] as num?)?.toInt(),
      );

  final String month;
  final List<List<CalendarDay>> weeks;
  final int workouts;
  final int minutes;
  final int volumeKg;
  final int? kcal;

  static int _summary(Map<String, dynamic> json, String key) =>
      ((json['summary'] as Map<String, dynamic>?)?[key] as num?)?.toInt() ?? 0;
}

class ProgressPoint {
  const ProgressPoint({required this.date, required this.top, this.e1rm, this.effort});

  ProgressPoint.fromJson(Map<String, dynamic> json)
    : this(
        date: json['date']?.toString() ?? '',
        top: (json['top'] as num?)?.toDouble() ?? 0,
        e1rm: (json['e1rm'] as num?)?.toDouble(),
        effort: (json['effort'] as num?)?.toDouble(),
      );

  final String date;

  /// Heaviest set (kg), longest hold (s) or top speed (km/h), by the exercise's mode.
  final double top;
  final double? e1rm;

  /// Average reps in reserve that session.
  final double? effort;
}

class ExerciseProgress {
  const ExerciseProgress({
    required this.exercise,
    required this.mode,
    required this.effortScale,
    required this.points,
    required this.sessions,
    this.bestValue,
    this.bestDate,
    this.bestE1rm,
  });

  ExerciseProgress.fromJson(Map<String, dynamic> json)
    : this(
        exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
        mode: ExerciseMode.fromWire(json['mode']?.toString()),
        effortScale: EffortScale.fromWire(json['effort_scale']?.toString()),
        points: (json['points'] as List? ?? [])
            .map((p) => ProgressPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        sessions: (json['sessions'] as List? ?? [])
            .map(
              (s) => (
                date: (s as Map<String, dynamic>)['date'].toString(),
                sets: WorkoutSet.listFrom(s['sets']),
              ),
            )
            .toList(),
        bestValue: ((json['best'] as Map<String, dynamic>?)?['value'] as num?)?.toDouble(),
        bestDate: (json['best'] as Map<String, dynamic>?)?['date']?.toString(),
        bestE1rm: OneRmRecord.fromJsonOrNull(json['best_e1rm']),
      );

  final Exercise exercise;
  final ExerciseMode mode;
  final EffortScale effortScale;
  final List<ProgressPoint> points;
  final List<({String date, List<WorkoutSet> sets})> sessions;
  final double? bestValue;
  final String? bestDate;
  final OneRmRecord? bestE1rm;
}
