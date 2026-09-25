import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/profile_view.dart';

/// What a reminder is about (D-222). Scheduled by the phone; the server never sends one.
enum ReminderKind { water, meal, dayEnd, workout }

/// The meals a reminder follows. The profile holds a time for each; the snacks are left out on
/// purpose — a nudge after every snack is a nudge too many.
const reminderMeals = ['breakfast', 'lunch', 'dinner'];

/// One reminder, at a wall-clock time on this phone. `meal` is the meal slot for
/// [ReminderKind.meal], and the routine's name for [ReminderKind.workout] (ADR-013).
typedef PlannedReminder = ({ReminderKind kind, DateTime at, String? meal});

enum ReminderPermission {
  granted,
  denied,

  /// Nothing to schedule on: a test, or a platform without notifications.
  unsupported,
}

/// What the person switched on. Everything starts off — a reminder nobody asked for is noise.
class ReminderSettings {
  const ReminderSettings({
    this.water = false,
    this.waterEveryMinutes = 120,
    this.stopWhenMet = true,
    this.meals = false,
    this.dayEnd = false,
    this.workout = false,
    this.workoutAtMinutes = defaultWorkoutAt,
  });

  factory ReminderSettings.fromJson(Map<String, dynamic> json) => ReminderSettings(
    water: json['water'] == true,
    waterEveryMinutes: switch (json['water_every']) {
      final int every when waterIntervals.contains(every) => every,
      _ => 120,
    },
    stopWhenMet: json['stop_when_met'] != false,
    meals: json['meals'] == true,
    dayEnd: json['day_end'] == true,
    workout: json['workout'] == true,
    workoutAtMinutes: switch (json['workout_at']) {
      final int at when at >= 0 && at < Duration.minutesPerDay => at,
      _ => defaultWorkoutAt,
    },
  );

  /// 07:00 — a nudge in the morning of a planned workout, early enough to plan the day around it.
  static const defaultWorkoutAt = 7 * 60;

  /// The gaps on offer, in minutes.
  static const waterIntervals = [1, 90, 120, 180];

  final bool water;
  final int waterEveryMinutes;

  /// Drop the rest of today's water reminders once the target is reached.
  final bool stopWhenMet;
  final bool meals;
  final bool dayEnd;

  /// A nudge on days the Gym plan has a workout (ADR-013), at [workoutAtMinutes] past midnight.
  final bool workout;
  final int workoutAtMinutes;

  bool get anyOn => water || meals || dayEnd || workout;

  ReminderSettings copyWith({
    bool? water,
    int? waterEveryMinutes,
    bool? stopWhenMet,
    bool? meals,
    bool? dayEnd,
    bool? workout,
    int? workoutAtMinutes,
  }) => ReminderSettings(
    water: water ?? this.water,
    waterEveryMinutes: waterEveryMinutes ?? this.waterEveryMinutes,
    stopWhenMet: stopWhenMet ?? this.stopWhenMet,
    meals: meals ?? this.meals,
    dayEnd: dayEnd ?? this.dayEnd,
    workout: workout ?? this.workout,
    workoutAtMinutes: workoutAtMinutes ?? this.workoutAtMinutes,
  );

  Map<String, dynamic> toJson() => {
    'water': water,
    'water_every': waterEveryMinutes,
    'stop_when_met': stopWhenMet,
    'meals': meals,
    'day_end': dayEnd,
    'workout': workout,
    'workout_at': workoutAtMinutes,
  };
}

/// The person's day, from their profile: minutes after midnight, null where they gave no time.
class ReminderRoutine {
  const ReminderRoutine({this.wake, this.sleep, this.meals = const {}});

  factory ReminderRoutine.fromJson(Map<String, dynamic> json) => ReminderRoutine(
    wake: json['wake'] as int?,
    sleep: json['sleep'] as int?,
    meals: {
      for (final MapEntry(:key, :value) in (json['meals'] as Map? ?? const {}).entries)
        if (value is int) key.toString(): value,
    },
  );

  /// From the profile's "HH:MM" strings.
  factory ReminderRoutine.fromProfile({
    required String? wake,
    required String? sleep,
    required Map<String, String?> meals,
  }) => ReminderRoutine(
    wake: minutesOf(wake),
    sleep: minutesOf(sleep),
    meals: {
      for (final MapEntry(:key, :value) in meals.entries)
        if (minutesOf(value) case final minutes?) key: minutes,
    },
  );

  factory ReminderRoutine.ofProfile(ProfileView? profile) => ReminderRoutine.fromProfile(
    wake: profile?.wakeTime,
    sleep: profile?.sleepTime,
    meals: {
      'breakfast': profile?.breakfastTime,
      'lunch': profile?.lunchTime,
      'dinner': profile?.dinnerTime,
    },
  );

  /// Used when the profile has no wake or sleep time.
  static const defaultWake = 8 * 60;
  static const defaultSleep = 22 * 60;

  final int? wake;
  final int? sleep;

  /// Keyed by [reminderMeals].
  final Map<String, int> meals;

  int get wakeOrDefault => wake ?? defaultWake;
  int get sleepOrDefault => sleep ?? defaultSleep;

  Map<String, dynamic> toJson() => {'wake': wake, 'sleep': sleep, 'meals': meals};

  /// "07:30" → 450. Null for anything else.
  static int? minutesOf(String? hhmm) {
    final parts = hhmm?.split(':');
    if (parts == null || parts.length < 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null || hours > 23 || minutes > 59) return null;
    return hours * 60 + minutes;
  }
}

/// What today already holds, for the reminders it makes pointless. [end] is the SERVER's end of
/// the diary day (rule 8) — "today" for a reminder means before it.
class ReminderDay {
  const ReminderDay({
    required this.end,
    this.waterMl,
    this.waterTargetMl,
    this.mealsLogged = const {},
  });

  factory ReminderDay.fromJson(Map<String, dynamic> json) => ReminderDay(
    end: DateTime.parse(json['end'] as String),
    waterMl: json['water_ml'] as int?,
    waterTargetMl: json['water_target_ml'] as int?,
    mealsLogged: {...(json['meals_logged'] as List? ?? const []).map((m) => m.toString())},
  );

  /// Null when the server sent no window: without it, nothing can be said about "today".
  static ReminderDay? fromDiary(DiaryDay day) => switch (day.windowEnd) {
    null => null,
    final end => ReminderDay(
      end: end,
      waterMl: day.waterLoggedMl,
      waterTargetMl: day.waterTargetMl,
      mealsLogged: {...day.entries.map((e) => e.slot)},
    ),
  };

  final DateTime end;
  final int? waterMl;
  final int? waterTargetMl;
  final Set<String> mealsLogged;

  bool get waterMet => switch ((waterMl, waterTargetMl)) {
    (final logged?, final target?) => target > 0 && logged >= target,
    _ => false,
  };

  ReminderDay withWater(int waterMl) => ReminderDay(
    end: end,
    waterMl: waterMl,
    waterTargetMl: waterTargetMl,
    mealsLogged: mealsLogged,
  );

  Map<String, dynamic> toJson() => {
    'end': end.toUtc().toIso8601String(),
    'water_ml': waterMl,
    'water_target_ml': waterTargetMl,
    'meals_logged': mealsLogged.toList(),
  };
}

/// Everything a re-plan needs, kept on the phone so a background tap can re-plan too.
class ReminderState {
  const ReminderState({
    this.settings = const ReminderSettings(),
    this.routine,
    this.day,
    this.workoutWeek = const {},
  });

  factory ReminderState.fromJson(Map<String, dynamic> json) => ReminderState(
    settings: ReminderSettings.fromJson(json['settings'] as Map<String, dynamic>? ?? const {}),
    routine: switch (json['routine']) {
      final Map<String, dynamic> routine => ReminderRoutine.fromJson(routine),
      _ => null,
    },
    day: switch (json['day']) {
      final Map<String, dynamic> day => ReminderDay.fromJson(day),
      _ => null,
    },
    workoutWeek: {
      for (final MapEntry(:key, :value) in (json['workout_week'] as Map? ?? const {}).entries)
        if ((int.tryParse(key.toString()), value) case (final int day, final String name))
          day: name,
    },
  );

  final ReminderSettings settings;
  final ReminderRoutine? routine;
  final ReminderDay? day;

  /// The Gym's weekly plan, ISO weekday → routine name, as the Gym last loaded it (ADR-013).
  final Map<int, String> workoutWeek;

  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'routine': routine?.toJson(),
    'day': day?.toJson(),
    'workout_week': {for (final MapEntry(:key, :value) in workoutWeek.entries) '$key': value},
  };
}
