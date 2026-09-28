import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/usecases/estimate_one_rm.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';

SessionEntry entry(
  String id, {
  int sets = 2,
  String? superset,
  ExerciseMode mode = ExerciseMode.reps,
}) => SessionEntry(
  exerciseId: id,
  name: 'exercise $id',
  mode: mode,
  bodyPart: 'chest',
  superset: superset,
  target: RoutineExercise(exerciseId: id, mode: mode, sets: sets, reps: 8, weightKg: 60),
  sets: List.generate(sets, (_) => const WorkoutSet(weightKg: 60, reps: 8)),
);

WorkoutSession session(List<SessionEntry> entries) => WorkoutSession.start(
  name: 'Push Day',
  plan: entries,
  now: DateTime.utc(2026, 9, 19, 7),
  routineId: 1,
  id: 'fixed',
);

void main() {
  group('WorkoutSession groups', () {
    test('adjacent entries sharing a superset id are one group', () {
      final s = session([
        entry('a'),
        entry('b', superset: 'x'),
        entry('c', superset: 'x'),
        entry('d'),
      ]);
      expect(s.groups, [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('the same superset id apart is two groups', () {
      final s = session([entry('a', superset: 'x'), entry('b'), entry('c', superset: 'x')]);
      expect(s.groupCount, 3);
    });
  });

  group('checking a set off', () {
    test('rests between the sets of a single exercise', () {
      final (next, outcome) = session([entry('a')]).toggle(0, 0);
      expect(outcome.rest, isTrue);
      expect(next.doneSets, 1);
    });

    test("does not rest after an exercise's final set", () {
      final (first, _) = session([entry('a'), entry('b')]).toggle(0, 0);
      final (_, outcome) = first.toggle(0, 1);
      expect(outcome.rest, isFalse);
      expect(outcome.entryFinished, isTrue);
      expect(outcome.groupFinished, isTrue);
      expect(outcome.allFinished, isFalse);
    });

    test('in a superset, moves straight on and rests only after the last exercise', () {
      final s = session([entry('a', superset: 'x'), entry('b', superset: 'x')]);
      final (afterA, a) = s.toggle(0, 0);
      expect(a.rest, isFalse);
      final (_, b) = afterA.toggle(1, 0);
      expect(b.rest, isTrue);
    });

    test('unchecking a set never starts a rest', () {
      final (checked, _) = session([entry('a')]).toggle(0, 0);
      final (unchecked, outcome) = checked.toggle(0, 0);
      expect(outcome.rest, isFalse);
      expect(unchecked.doneSets, 0);
    });

    test('says when the whole workout is done', () {
      final (s, outcome) = session([entry('a', sets: 1)]).toggle(0, 0);
      expect(outcome.allFinished, isTrue);
      expect(s.allDone, isTrue);
    });
  });

  group('editing', () {
    test("adds a set copying the last one's numbers but not its tick", () {
      final (checked, _) = session([entry('a', sets: 1)]).toggle(0, 0);
      final added = checked.addSet(0);
      expect(added.entries[0].sets.length, 2);
      expect(added.entries[0].sets.last.done, isFalse);
      expect(added.entries[0].sets.last.weightKg, 60);
    });

    test('never removes the first set', () {
      final s = session([entry('a', sets: 1)]);
      expect(identical(s.removeSet(0), s), isTrue);
      expect(session([entry('a', sets: 3)]).removeSet(0).entries[0].sets.length, 2);
    });

    test('a value edit leaves the original session untouched', () {
      final s = session([entry('a')]);
      final edited = s.withSet(0, 1, const WorkoutSet(weightKg: 62.5, reps: 8));
      expect(s.entries[0].sets[1].weightKg, 60);
      expect(edited.entries[0].sets[1].weightKg, 62.5);
    });

    test('an exercise added mid-workout becomes its own group and is shown', () {
      final s = session([entry('a')]).addEntry(entry('z'));
      expect(s.groupCount, 2);
      expect(s.currentGroupIndex, 1);
    });
  });

  group('working weight', () {
    test('is asked once all weighted sets are done, and only once', () {
      var s = session([entry('a', sets: 1)]);
      expect(s.asksWorkingWeight(0), isFalse);
      (s, _) = s.toggle(0, 0);
      expect(s.asksWorkingWeight(0), isTrue);
      s = s.confirmWorkingWeight(0, 62.5);
      expect(s.asksWorkingWeight(0), isFalse);
      expect(s.entries[0].topWeightKg, 62.5);
    });

    test('is never asked for cardio', () {
      const run = SessionEntry(
        exerciseId: '0685',
        name: 'run',
        mode: ExerciseMode.cardio,
        bodyPart: 'cardio',
        target: RoutineExercise(exerciseId: '0685', mode: ExerciseMode.cardio, sets: 1),
        sets: [WorkoutSet(minutes: 20, speedKmh: 8)],
      );
      final (s, _) = session([run]).toggle(0, 0);
      expect(s.asksWorkingWeight(0), isFalse);
    });
  });

  test("survives a round trip through the phone's store", () {
    final (s, _) = session([entry('a'), entry('b', superset: 'x')]).toggle(0, 0);
    final back = WorkoutSession.fromJson(s.markAsked(0).toJson());
    expect(back.id, 'fixed');
    expect(back.doneSets, 1);
    expect(back.asked, {0});
    expect(back.startedAt, s.startedAt);
    expect(back.entries[1].superset, 'x');
  });

  test('a finished session never ends before it started', () {
    final s = session([entry('a')]);
    expect(s.finish(DateTime.utc(2026, 9, 19, 6)).endedAt, s.startedAt);
  });

  test('ids are version-4 UUIDs', () {
    final id = WorkoutSession.newId(Random(1));
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id),
      isTrue,
    );
  });

  group('estimateOneRm (Epley)', () {
    test('is the weight itself for a single rep', () => expect(estimateOneRm(100, 1), 100));
    test('matches the server at 5 reps', () => expect(estimateOneRm(100, 5), 116.7));
    test('says nothing past twelve reps', () => expect(estimateOneRm(80, 13), isNull));
    test('says nothing without a weight', () => expect(estimateOneRm(0, 5), isNull));
  });
}
