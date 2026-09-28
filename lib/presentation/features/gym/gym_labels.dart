import 'package:flutter/material.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Every word the Gym section shows for a server vocabulary (CLAUDE.md rule 4): body parts,
/// equipment, muscles, rules, reasons. An unknown word from a newer server shows as itself rather
/// than crashing — the one place a raw string may reach the screen, and only a word nobody taught
/// this build.
abstract final class GymLabels {
  static String bodyPart(AppLocalizations l, String wire) => switch (wire) {
    'back' => l.gymBpBack,
    'cardio' => l.gymBpCardio,
    'chest' => l.gymBpChest,
    'lower arms' => l.gymBpLowerArms,
    'lower legs' => l.gymBpLowerLegs,
    'neck' => l.gymBpNeck,
    'shoulders' => l.gymBpShoulders,
    'upper arms' => l.gymBpUpperArms,
    'upper legs' => l.gymBpUpperLegs,
    'waist' => l.gymBpWaist,
    _ => wire,
  };

  static String equipment(AppLocalizations l, String wire) => switch (wire) {
    'body weight' => l.gymEqBodyWeight,
    'dumbbell' => l.gymEqDumbbell,
    'cable' => l.gymEqCable,
    'barbell' => l.gymEqBarbell,
    'leverage machine' => l.gymEqLeverageMachine,
    'band' => l.gymEqBand,
    'smith machine' => l.gymEqSmithMachine,
    'kettlebell' => l.gymEqKettlebell,
    'weighted' => l.gymEqWeighted,
    'stability ball' => l.gymEqStabilityBall,
    'ez barbell' => l.gymEqEzBarbell,
    'assisted' => l.gymEqAssisted,
    'sled machine' => l.gymEqSledMachine,
    'medicine ball' => l.gymEqMedicineBall,
    'rope' => l.gymEqRope,
    'roller' => l.gymEqRoller,
    'resistance band' => l.gymEqResistanceBand,
    'bosu ball' => l.gymEqBosuBall,
    'olympic barbell' => l.gymEqOlympicBarbell,
    'wheel roller' => l.gymEqWheelRoller,
    'upper body ergometer' => l.gymEqUpperBodyErgometer,
    'skierg machine' => l.gymEqSkiergMachine,
    'hammer' => l.gymEqHammer,
    'stationary bike' => l.gymEqStationaryBike,
    'tire' => l.gymEqTire,
    'trap bar' => l.gymEqTrapBar,
    'elliptical machine' => l.gymEqEllipticalMachine,
    'stepmill machine' => l.gymEqStepmillMachine,
    'custom' => l.gymEqCustom,
    _ => wire,
  };

  /// The dataset's primary-muscle word.
  static String target(AppLocalizations l, String wire) => switch (wire) {
    'abs' => l.gymTargetAbs,
    'pectorals' => l.gymTargetPectorals,
    'biceps' => l.gymTargetBiceps,
    'glutes' => l.gymTargetGlutes,
    'delts' => l.gymTargetDelts,
    'triceps' => l.gymTargetTriceps,
    'upper back' => l.gymTargetUpperBack,
    'lats' => l.gymTargetLats,
    'calves' => l.gymTargetCalves,
    'quads' => l.gymTargetQuads,
    'forearms' => l.gymTargetForearms,
    'cardiovascular system' => l.gymTargetCardiovascularSystem,
    'hamstrings' => l.gymTargetHamstrings,
    'spine' => l.gymTargetSpine,
    'traps' => l.gymTargetTraps,
    'adductors' => l.gymTargetAdductors,
    'serratus anterior' => l.gymTargetSerratusAnterior,
    'abductors' => l.gymTargetAbductors,
    'levator scapulae' => l.gymTargetLevatorScapulae,
    _ => wire,
  };

  /// A drawn muscle (the body map's vocabulary).
  static String muscle(AppLocalizations l, String wire) => switch (wire) {
    'trapezius' => l.gymMuscleTrapezius,
    'deltoids' => l.gymMuscleDeltoids,
    'chest' => l.gymMuscleChest,
    'upper-back' => l.gymMuscleUpperBack,
    'serratus' => l.gymMuscleSerratus,
    'biceps' => l.gymMuscleBiceps,
    'triceps' => l.gymMuscleTriceps,
    'forearm' => l.gymMuscleForearm,
    'abs' => l.gymMuscleAbs,
    'obliques' => l.gymMuscleObliques,
    'lower-back' => l.gymMuscleLowerBack,
    'gluteal' => l.gymMuscleGluteal,
    'quadriceps' => l.gymMuscleQuadriceps,
    'hamstring' => l.gymMuscleHamstring,
    'adductors' => l.gymMuscleAdductors,
    'hip-flexors' => l.gymMuscleHipFlexors,
    'calves' => l.gymMuscleCalves,
    'tibialis' => l.gymMuscleTibialis,
    _ => wire,
  };

  static String mode(AppLocalizations l, ExerciseMode m) => switch (m) {
    ExerciseMode.reps => l.gymModeReps,
    ExerciseMode.time => l.gymModeTime,
    ExerciseMode.cardio => l.gymModeCardio,
  };

  static String rule(AppLocalizations l, ProgressionRule r) => switch (r) {
    ProgressionRule.off => l.gymRuleOff,
    ProgressionRule.linear => l.gymRuleLinear,
    ProgressionRule.greyskull => l.gymRuleGreyskull,
    ProgressionRule.doubleProgression => l.gymRuleDouble,
    ProgressionRule.time => l.gymRuleTime,
  };

  static String ruleBody(AppLocalizations l, ProgressionRule r) => switch (r) {
    ProgressionRule.off => l.gymRuleOffBody,
    ProgressionRule.linear => l.gymRuleLinearBody,
    ProgressionRule.greyskull => l.gymRuleGreyskullBody,
    ProgressionRule.doubleProgression => l.gymRuleDoubleBody,
    ProgressionRule.time => l.gymRuleTimeBody,
  };

  static String icon(AppLocalizations l, RoutineIcon i) => switch (i) {
    RoutineIcon.strength => l.gymIconStrength,
    RoutineIcon.gymnastics => l.gymIconGymnastics,
    RoutineIcon.body => l.gymIconBody,
    RoutineIcon.martial => l.gymIconMartial,
    RoutineIcon.rowing => l.gymIconRowing,
    RoutineIcon.run => l.gymIconRun,
    RoutineIcon.walk => l.gymIconWalk,
    RoutineIcon.bike => l.gymIconBike,
    RoutineIcon.heart => l.gymIconHeart,
    RoutineIcon.fire => l.gymIconFire,
    RoutineIcon.timer => l.gymIconTimer,
    RoutineIcon.yoga => l.gymIconYoga,
  };

  static String effortScale(AppLocalizations l, EffortScale s) => switch (s) {
    EffortScale.off => l.gymEffortOff,
    EffortScale.rir => l.gymEffortRir,
    EffortScale.rpe => l.gymEffortRpe,
  };

  /// The progression's reason, worded from its code and figures.
  static String why(AppLocalizations l, Prescription p) {
    String num(String key) => kg(p.arg(key)?.toDouble() ?? 0);
    int whole(String key) => p.arg(key)?.toInt() ?? 0;
    return switch (p.whyCode) {
      'baseline' => l.gymWhyBaseline,
      'up_weight' => l.gymWhyUpWeight(num('step')),
      'up_weight_double' => l.gymWhyUpWeightDouble(num('step')),
      'hold' => l.gymWhyHold,
      'deload' => l.gymWhyDeload(num('weight_kg')),
      'double_up' => l.gymWhyDoubleUp(num('step'), whole('reps')),
      'double_reps' => l.gymWhyDoubleReps(whole('reps')),
      'double_deload' => l.gymWhyDoubleDeload(num('weight_kg'), whole('reps')),
      'bw_up_reps' => l.gymWhyBwUpReps(whole('reps')),
      'bw_add_set' => l.gymWhyBwAddSet(whole('sets')),
      'bw_max' => l.gymWhyBwMax,
      'bw_hold' => l.gymWhyBwHold,
      'time_up' => l.gymWhyTimeUp(num('step')),
      'time_hold' => l.gymWhyTimeHold,
      'time_deload' => l.gymWhyTimeDeload(num('seconds')),
      _ => l.gymWhyOff,
    };
  }

  /// One line for a routine exercise: "3 × 10 · 60 kg", "3 × 16 · 8 per side", "3 × 0:45",
  /// "1 × 20 min at 8 km/h", "+10 kg".
  static String summary(AppLocalizations l, RoutineExercise e, {required bool bodyweight}) {
    switch (e.mode) {
      case ExerciseMode.cardio:
        return l.gymSetsCardio(e.sets, kg(e.minutes ?? 20), kg(e.speedKmh ?? 8));
      case ExerciseMode.time:
        final time = l.gymSetsTime(e.sets, clock(e.seconds ?? 45));
        final w = e.weightKg ?? 0;
        return w > 0 ? '$time · ${l.gymAddedKg(kg(w))}' : time;
      case ExerciseMode.reps:
        final reps = e.reps ?? 10;
        final base = l.gymSetsReps(e.sets, reps);
        final side = (e.perSide ?? false) ? ' · ${l.gymPerSide(reps ~/ 2)}' : '';
        final w = e.weightKg ?? 0;
        final load = w <= 0 ? '' : ' · ${bodyweight ? l.gymAddedKg(kg(w)) : l.gymKg(kg(w))}';
        return '$base$side$load';
    }
  }

  /// One logged set: "60 × 8", "0:45", "20 min · 8 km/h".
  static String set(AppLocalizations l, ExerciseMode mode, WorkoutSet s) => switch (mode) {
    ExerciseMode.cardio =>
      '${l.gymDurationValue((s.minutes ?? 0).round())} · ${l.gymSpeedValue(kg(s.speedKmh ?? 0))}',
    ExerciseMode.time => clock(s.seconds ?? 0),
    ExerciseMode.reps =>
      (s.weightKg ?? 0) > 0 ? '${kg(s.weightKg!)} × ${s.reps ?? 0}' : '${s.reps ?? 0}',
  };

  static String sets(AppLocalizations l, ExerciseMode mode, List<WorkoutSet> sets) =>
      sets.where((s) => s.done).map((s) => set(l, mode, s)).join(', ');

  /// The dataset writes names in lower case ("barbell bench press"); shown in title case. A name
  /// someone typed for their own exercise keeps exactly the capitals they gave it.
  static String name(String name, {bool custom = false}) => custom
      ? name
      : name.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  /// Kilograms and other decimals: one place of precision at most, no trailing ".0".
  static String kg(num value) => NumberFormat('#,##0.#').format(value);

  /// Seconds as m:ss, or h:mm:ss past an hour.
  static String clock(int seconds) {
    final d = Duration(seconds: seconds.abs());
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '${d.inMinutes}:$ss';
  }

  /// A diary date from the server, shown as "19 Sep" in the phone's language. Parsing the date for
  /// display is not deciding which day something belongs to — the server already did (rule 8).
  static String day(BuildContext context, String diaryDate) {
    final date = DateTime.tryParse(diaryDate);
    if (date == null) return diaryDate;
    return DateFormat.MMMd(Localizations.localeOf(context).toString()).format(date);
  }

  static String weekdayName(BuildContext context, int isoWeekday, {bool short = false}) {
    // 2024-01-01 was a Monday: any date with the right weekday names it.
    final date = DateTime(2024, 1, isoWeekday);
    final locale = Localizations.localeOf(context).toString();
    return (short ? DateFormat.E(locale) : DateFormat.EEEE(locale)).format(date);
  }

  static IconData iconFor(RoutineIcon i) => switch (i) {
    RoutineIcon.strength => Icons.fitness_center,
    RoutineIcon.gymnastics => Icons.sports_gymnastics,
    RoutineIcon.body => Icons.accessibility_new,
    RoutineIcon.martial => Icons.sports_martial_arts,
    RoutineIcon.rowing => Icons.rowing,
    RoutineIcon.run => Icons.directions_run,
    RoutineIcon.walk => Icons.directions_walk,
    RoutineIcon.bike => Icons.directions_bike,
    RoutineIcon.heart => Icons.monitor_heart_outlined,
    RoutineIcon.fire => Icons.local_fire_department_outlined,
    RoutineIcon.timer => Icons.timer_outlined,
    RoutineIcon.yoga => Icons.self_improvement,
  };

  static IconData bodyPartIcon(String wire) => switch (wire) {
    'cardio' => Icons.directions_run,
    'chest' => Icons.fitness_center,
    'back' => Icons.rowing,
    'shoulders' => Icons.sports_gymnastics,
    'upper arms' => Icons.sports_handball,
    'lower arms' => Icons.front_hand_outlined,
    'upper legs' => Icons.directions_walk,
    'lower legs' => Icons.hiking,
    'waist' => Icons.accessibility_new,
    'neck' => Icons.face_outlined,
    _ => Icons.fitness_center,
  };
}
