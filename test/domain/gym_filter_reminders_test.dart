import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/usecases/exercise_filter.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';

const _library = [
  Exercise(
    id: '1',
    name: 'barbell bench press',
    bodyPart: 'chest',
    equipment: 'barbell',
    target: 'pectorals',
  ),
  Exercise(
    id: '2',
    name: 'dumbbell fly',
    bodyPart: 'chest',
    equipment: 'dumbbell',
    target: 'pectorals',
  ),
  Exercise(
    id: '3',
    name: 'push-up',
    bodyPart: 'chest',
    equipment: 'body weight',
    target: 'pectorals',
  ),
  Exercise(
    id: '4',
    name: 'barbell squat',
    bodyPart: 'upper legs',
    equipment: 'barbell',
    target: 'quads',
  ),
  Exercise(
    id: '5',
    name: 'goblet squat',
    bodyPart: 'upper legs',
    equipment: 'kettlebell',
    target: 'quads',
  ),
];

void main() {
  group('filterExercises', () {
    test('should match name, target and equipment', () {
      expect(
        filterExercises(_library, const ExerciseQuery(text: 'squat')).results.map((e) => e.id),
        ['4', '5'],
      );
      expect(filterExercises(_library, const ExerciseQuery(text: 'quads')).results, hasLength(2));
      expect(filterExercises(_library, const ExerciseQuery(text: 'KETTLE')).results.single.id, '5');
    });

    test('should offer only equipment the other filters leave, most common first', () {
      final chest = filterExercises(_library, const ExerciseQuery(bodyPart: 'chest'));
      expect(chest.equipment, ['barbell', 'body weight', 'dumbbell']);
      expect(filterExercises(_library, const ExerciseQuery()).equipment.first, 'barbell');
    });

    test('should drop an equipment filter the body part has emptied', () {
      final r = filterExercises(
        _library,
        const ExerciseQuery(bodyPart: 'upper legs', equipment: 'dumbbell'),
      );
      expect(r.equipmentApplied, isNull);
      expect(r.results, hasLength(2));
    });

    test('should list chosen exercises by how many routines use them', () {
      final r = filterExercises(
        _library,
        const ExerciseQuery(chosenOnly: true),
        usage: {'2': 1, '4': 3},
      );
      expect(r.results.map((e) => e.id), ['4', '2']);
    });
  });

  group('workout-day reminders (ADR-013)', () {
    // Monday 21 September 2026, 06:00 on the phone.
    final monday = DateTime(2026, 9, 21, 6);
    const settings = ReminderSettings(workout: true);

    test('should remind on planned weekdays, at the chosen time, naming the routine', () {
      final planned = PlanReminders.plan(
        settings: settings,
        routine: const ReminderRoutine(),
        now: monday,
        workoutWeek: const {1: 'Push Day', 3: 'Pull Day'},
      );
      expect(planned.map((r) => (r.at.weekday, r.at.hour, r.meal)).toList(), [
        (DateTime.monday, 7, 'Push Day'),
        (DateTime.wednesday, 7, 'Pull Day'),
      ]);
      expect(planned.every((r) => r.kind == ReminderKind.workout), isTrue);
    });

    test('should schedule nothing on rest days or when switched off', () {
      expect(
        PlanReminders.plan(settings: settings, routine: const ReminderRoutine(), now: monday),
        isEmpty,
      );
      expect(
        PlanReminders.plan(
          settings: const ReminderSettings(),
          routine: const ReminderRoutine(),
          now: monday,
          workoutWeek: const {1: 'Push Day'},
        ),
        isEmpty,
      );
    });

    test('should keep the weekly plan through the phone store', () {
      const state = ReminderState(settings: settings, workoutWeek: {5: 'Leg Day'});
      final back = ReminderState.fromJson(state.toJson());
      expect(back.workoutWeek, {5: 'Leg Day'});
      expect(back.settings.workout, isTrue);
      expect(back.settings.workoutAtMinutes, 7 * 60);
    });
  });
}
