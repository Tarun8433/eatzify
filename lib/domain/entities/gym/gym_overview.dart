import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';

class GymSettings {
  const GymSettings({
    this.restSec = 90,
    this.effortScale = EffortScale.off,
    this.keepAwake = true,
    this.sound = true,
    this.bodyFigure = BodyFigure.male,
  });

  GymSettings.fromJson(Map<String, dynamic> json)
    : this(
        restSec: (json['rest_sec'] as num?)?.toInt() ?? 90,
        effortScale: EffortScale.fromWire(json['effort_scale']?.toString()),
        keepAwake: json['keep_awake'] as bool? ?? true,
        sound: json['sound'] as bool? ?? true,
        bodyFigure: BodyFigure.fromWire(json['body_figure']?.toString()),
      );

  /// The rest options offered, in seconds.
  static const restOptions = [60, 90, 120, 150, 180];

  final int restSec;
  final EffortScale effortScale;
  final bool keepAwake;
  final bool sound;
  final BodyFigure bodyFigure;

  GymSettings copyWith({
    int? restSec,
    EffortScale? effortScale,
    bool? keepAwake,
    bool? sound,
    BodyFigure? bodyFigure,
  }) => GymSettings(
    restSec: restSec ?? this.restSec,
    effortScale: effortScale ?? this.effortScale,
    keepAwake: keepAwake ?? this.keepAwake,
    sound: sound ?? this.sound,
    bodyFigure: bodyFigure ?? this.bodyFigure,
  );

  Map<String, dynamic> toJson() => {
    'rest_sec': restSec,
    'effort_scale': effortScale.wire,
    'keep_awake': keepAwake,
    'sound': sound,
    'body_figure': bodyFigure.wire,
  };
}

/// A day as the server resolved it — its date, weekday and routine all decided there (rule 8).
class PlannedDay {
  const PlannedDay({
    required this.diaryDate,
    required this.weekday,
    required this.source,
    this.routineId,
    this.workouts = 0,
    this.isToday = false,
  });

  PlannedDay.fromJson(Map<String, dynamic> json)
    : this(
        diaryDate: json['diary_date']?.toString() ?? '',
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        routineId: (json['routine_id'] as num?)?.toInt(),
        source: DaySource.fromWire(json['source']?.toString()),
        workouts: (json['workouts'] as num?)?.toInt() ?? 0,
        isToday: json['is_today'] as bool? ?? false,
      );

  final String diaryDate;

  /// 1 Monday … 7 Sunday.
  final int weekday;
  final int? routineId;
  final DaySource source;
  final int workouts;
  final bool isToday;

  bool get trained => workouts > 0;
  bool get isRescheduled => source == DaySource.rescheduled || source == DaySource.restOverride;
}

class GymTotals {
  const GymTotals({
    this.todayKcal,
    this.weekKcal,
    this.streakWeeks = 0,
    this.thisWeekWorkouts = 0,
    this.plannedPerWeek = 0,
    this.totalWorkouts = 0,
  });

  GymTotals.fromJson(Map<String, dynamic> json)
    : this(
        todayKcal: (json['today_kcal'] as num?)?.toInt(),
        weekKcal: (json['week_kcal'] as num?)?.toInt(),
        streakWeeks: (json['streak_weeks'] as num?)?.toInt() ?? 0,
        thisWeekWorkouts: (json['this_week_workouts'] as num?)?.toInt() ?? 0,
        plannedPerWeek: (json['planned_per_week'] as num?)?.toInt() ?? 0,
        totalWorkouts: (json['total_workouts'] as num?)?.toInt() ?? 0,
      );

  /// D-242 estimates; null when nothing could be estimated, never a fabricated 0.
  final int? todayKcal;
  final int? weekKcal;
  final int streakWeeks;
  final int thisWeekWorkouts;
  final int plannedPerWeek;
  final int totalWorkouts;
}

/// `GET /gym` — the hub in one response, including every routine's session ready to start.
class GymOverview {
  const GymOverview({
    required this.settings,
    required this.week,
    required this.routines,
    required this.today,
    required this.weekDays,
    required this.sessionPlans,
    required this.totals,
    required this.recent,
    this.fromCache = false,
  });

  GymOverview.fromJson(Map<String, dynamic> json, {bool fromCache = false})
    : this(
        settings: GymSettings.fromJson(json['settings'] as Map<String, dynamic>? ?? const {}),
        week: (json['week'] as Map<String, dynamic>? ?? const {}).map(
          (day, routine) => MapEntry(int.parse(day), (routine as num).toInt()),
        ),
        routines: (json['routines'] as List? ?? [])
            .map((r) => Routine.fromJson(r as Map<String, dynamic>))
            .toList(),
        today: PlannedDay.fromJson(json['today'] as Map<String, dynamic>? ?? const {}),
        weekDays: (json['week_days'] as List? ?? [])
            .map((d) => PlannedDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        sessionPlans: (json['session_plans'] as Map<String, dynamic>? ?? const {}).map(
          (routine, entries) => MapEntry(
            int.parse(routine),
            (entries as List).map((e) => SessionEntry.fromJson(e as Map<String, dynamic>)).toList(),
          ),
        ),
        totals: GymTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? const {}),
        recent: WorkoutSummary.listFrom(json['recent']),
        fromCache: fromCache,
      );

  final GymSettings settings;

  /// ISO weekday → routine id. A missing day is a rest day.
  final Map<int, int> week;
  final List<Routine> routines;
  final PlannedDay today;

  /// This week, Monday first.
  final List<PlannedDay> weekDays;

  /// Routine id → its next session, prefilled and progressed by the server.
  final Map<int, List<SessionEntry>> sessionPlans;
  final GymTotals totals;
  final List<WorkoutSummary> recent;

  /// Shown from the phone's last copy because the server could not be reached.
  final bool fromCache;

  Routine? routineById(int? id) {
    if (id == null) return null;
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  Routine? get todaysRoutine => routineById(today.routineId);

  bool get hasPlan => routines.isNotEmpty;
}
