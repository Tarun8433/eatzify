import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';

/// Which figure the exercise progress chart plots.
enum ProgressMetric { top, e1rm, effort }

/// The Stats tab. Every figure is the server's (`GET /gym/stats`); the windows and the exercise
/// picked are the only state held here.
class GymStatsController extends GetxController {
  GymStatsController({required this.gym});

  final GymRepository gym;

  final state = Rx<ViewState<GymStats>>(const Loading());
  final muscleWindow = 'week'.obs;
  final effortWindow = '90d'.obs;
  final hardOnly = false.obs;

  final exerciseId = RxnString();
  final progress = Rxn<ViewState<ExerciseProgress>>();
  final metric = ProgressMetric.top.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quietly = false}) async {
    // onInit runs from a Get.find inside the tab's build: no Rx write in that call stack (see
    // GymController.load).
    await Future<void>.value();
    if (!quietly) state.value = const Loading();
    final result = await gym.stats(
      muscleWindow: muscleWindow.value,
      effortWindow: effortWindow.value,
      hard: hardOnly.value,
    );
    state.value = result.fold(Failed.new, (s) => s.isEmpty ? const Empty() : Ready(s));
    final stats = switch (state.value) {
      Ready<GymStats>(:final data) => data,
      _ => null,
    };
    // First visit: chart the exercise done most recently.
    if (exerciseId.value == null && stats != null && stats.exercises.isNotEmpty) {
      await pickExercise(stats.exercises.first.id);
    }
  }

  Future<void> setMuscleWindow(String window) async {
    muscleWindow.value = window;
    await load(quietly: true);
  }

  Future<void> setEffortWindow(String window) async {
    effortWindow.value = window;
    await load(quietly: true);
  }

  Future<void> setHardOnly({required bool on}) async {
    hardOnly.value = on;
    await load(quietly: true);
  }

  Future<void> pickExercise(String id) async {
    exerciseId.value = id;
    metric.value = ProgressMetric.top;
    progress.value = const Loading();
    final result = await gym.progress(id);
    progress.value = result.fold(Failed.new, Ready.new);
  }
}
