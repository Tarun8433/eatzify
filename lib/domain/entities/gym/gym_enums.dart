/// The Gym section's closed vocabularies (ADR-013). Each carries its wire string, and an unknown
/// string from a newer server degrades to a safe default rather than crashing a screen. None is
/// ever shown raw — `gym_labels.dart` localises every one (CLAUDE.md rule 4).
library;

/// How a set is logged: weight × reps, a timed hold, or minutes at a speed.
enum ExerciseMode {
  reps('reps'),
  time('time'),
  cardio('cardio');

  const ExerciseMode(this.wire);

  final String wire;

  static ExerciseMode fromWire(String? wire) =>
      values.firstWhere((m) => m.wire == wire, orElse: () => reps);
}

/// How the next session's numbers follow from the last. 'double' is the wire name of double
/// progression; `doubleProgression` only because `double` reads as the type.
enum ProgressionRule {
  off('off'),
  linear('linear'),
  greyskull('greyskull'),
  doubleProgression('double'),
  time('time');

  const ProgressionRule(this.wire);

  final String wire;

  static ProgressionRule fromWire(String? wire) =>
      values.firstWhere((r) => r.wire == wire, orElse: () => linear);

  static ProgressionRule? fromWireOrNull(String? wire) =>
      wire == null ? null : values.firstWhere((r) => r.wire == wire, orElse: () => off);

  /// The rules a whole routine may carry; 'time' only means something per timed exercise.
  static const routineRules = [off, linear, greyskull, doubleProgression];

  /// Which rules a mode can use — the server enforces the same list.
  static List<ProgressionRule> allowedFor(ExerciseMode mode) => switch (mode) {
    ExerciseMode.reps => routineRules,
    ExerciseMode.time => const [off, time],
    ExerciseMode.cardio => const [off],
  };
}

/// Where a day's routine came from: the weekly plan, or a one-off change for that date.
enum DaySource {
  weekly('weekly'),
  rescheduled('rescheduled'),
  restOverride('rest_override'),
  none('none');

  const DaySource(this.wire);

  final String wire;

  static DaySource fromWire(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => none);
}

/// Effort per set: reps in reserve, or rate of perceived exertion. Off by default.
enum EffortScale {
  off('off'),
  rir('rir'),
  rpe('rpe');

  const EffortScale(this.wire);

  final String wire;

  static EffortScale fromWire(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => off);
}

/// Which outline the muscle map is drawn on.
enum BodyFigure {
  male('male'),
  female('female');

  const BodyFigure(this.wire);

  final String wire;

  static BodyFigure fromWire(String? wire) =>
      values.firstWhere((f) => f.wire == wire, orElse: () => male);
}

/// A routine's icon, by name. The server stores the name; the app draws its own glyph.
enum RoutineIcon {
  strength('strength'),
  gymnastics('gymnastics'),
  body('body'),
  martial('martial'),
  rowing('rowing'),
  run('run'),
  walk('walk'),
  bike('bike'),
  heart('heart'),
  fire('fire'),
  timer('timer'),
  yoga('yoga');

  const RoutineIcon(this.wire);

  final String wire;

  static RoutineIcon fromWire(String? wire) =>
      values.firstWhere((i) => i.wire == wire, orElse: () => strength);
}

/// The dataset's ten body parts — the library's first filter.
const gymBodyParts = [
  'back',
  'cardio',
  'chest',
  'lower arms',
  'lower legs',
  'neck',
  'shoulders',
  'upper arms',
  'upper legs',
  'waist',
];

/// The drawn muscles, in the order the server reports them (MuscleMap's outline set).
const gymMuscles = [
  'trapezius',
  'deltoids',
  'chest',
  'upper-back',
  'serratus',
  'biceps',
  'triceps',
  'forearm',
  'abs',
  'obliques',
  'lower-back',
  'gluteal',
  'quadriceps',
  'hamstring',
  'adductors',
  'hip-flexors',
  'calves',
  'tibialis',
];
