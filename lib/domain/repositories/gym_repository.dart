import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';

/// The Gym section (ADR-013). The server decides the diary day, progression, records and energy;
/// the phone keeps only the workout in progress and anything it could not send yet.
abstract class GymRepository {
  /// The hub. With no signal, the last copy — marked [GymOverview.fromCache] — so a workout can
  /// still start from the plan the server last prepared.
  Future<Either<Failure, GymOverview>> overview();

  /// The library plus the person's own exercises; the last copy when offline.
  Future<Either<Failure, List<Exercise>>> exercises();

  Future<Either<Failure, ExerciseDetail>> exercise(String id);

  Future<Either<Failure, ExerciseProgress>> progress(String id);

  Future<Either<Failure, Exercise>> createExercise({
    required String name,
    required String bodyPart,
    String? description,
  });

  Future<Either<Failure, Exercise>> updateExercise(
    String id, {
    required String name,
    required String bodyPart,
    String? description,
  });

  Future<Either<Failure, Unit>> deleteExercise(String id);

  /// Creates when [RoutineDraft.id] is null.
  Future<Either<Failure, Routine>> saveRoutine(RoutineDraft draft);

  Future<Either<Failure, Unit>> deleteRoutine(int id);

  Future<Either<Failure, GymOverview>> loadStarterPlan();

  /// ISO weekday → routine id, null for rest.
  Future<Either<Failure, GymOverview>> setSchedule(Map<int, int?> week);

  /// One date only: a routine, rest, or (neither) back to the weekly plan.
  Future<Either<Failure, GymOverview>> setDay({
    required String date,
    int? routineId,
    bool rest = false,
  });

  Future<Either<Failure, GymSettings>> updateSettings(GymSettings settings);

  /// Queued on the phone before it is sent, so a lost connection loses nothing; the queue is
  /// retried by [sendPending].
  Future<Either<Failure, WorkoutDetail>> saveWorkout(WorkoutDraft draft);

  /// Retries workouts that could not be sent. Returns how many are still waiting.
  Future<int> sendPending();

  Future<List<WorkoutDraft>> pendingWorkouts();

  Future<Either<Failure, ({List<WorkoutSummary> workouts, String? nextCursor})>> history({
    String? before,
  });

  Future<Either<Failure, WorkoutDetail>> workout(String id);

  Future<Either<Failure, Unit>> deleteWorkout(String id);

  Future<Either<Failure, GymStats>> stats({String? muscleWindow, String? effortWindow, bool? hard});

  Future<Either<Failure, GymCalendar>> calendar(String month);

  Future<WorkoutSession?> activeWorkout();

  /// Null clears it.
  Future<void> saveActiveWorkout(WorkoutSession? session);

  /// At sign-out: nothing of one person's training stays on the phone for the next.
  Future<void> clearLocal();
}
