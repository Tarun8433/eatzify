import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';

/// One routine being edited: name, icon, rule and its exercises, saved whole. Supersets are
/// adjacent exercises sharing an id; an id left alone after a remove or a move is cleared here
/// (the server does the same, so the two never disagree).
class RoutineEditController extends GetxController {
  RoutineEditController({
    required this.gym,
    Routine? routine,
    List<RoutineItem> initialItems = const [],
  }) : id = routine?.id,
       name = (routine?.name ?? '').obs,
       icon = (routine?.icon ?? RoutineIcon.strength).obs,
       progression = (routine?.progression ?? ProgressionRule.linear).obs,
       items = <RoutineItem>[...?routine?.items, ...initialItems].obs,
       dirty = initialItems.isNotEmpty.obs;

  final GymController gym;
  final int? id;
  final RxString name;
  final Rx<RoutineIcon> icon;
  final Rx<ProgressionRule> progression;
  final RxList<RoutineItem> items;
  final RxBool dirty;

  bool get isNew => id == null;

  void rename(String value) => _change(() => name.value = value);

  void setIcon(RoutineIcon value) => _change(() => icon.value = value);

  void setRule(ProgressionRule value) => _change(() => progression.value = value);

  /// An exercise lands with plain numbers: 3 × 10 unloaded, or 20 minutes at 8 km/h for cardio.
  void add(Exercise e) => _change(
    () => items.add(
      RoutineItem(
        config: e.isCardio
            ? RoutineExercise(
                exerciseId: e.id,
                mode: ExerciseMode.cardio,
                sets: 1,
                minutes: 20,
                speedKmh: 8,
              )
            : RoutineExercise(
                exerciseId: e.id,
                mode: ExerciseMode.reps,
                sets: 3,
                reps: 10,
                weightKg: 0,
              ),
        name: e.name,
        bodyPart: e.bodyPart,
        equipment: e.equipment,
        isBodyweight: e.isBodyweight,
        isCardio: e.isCardio,
      ),
    ),
  );

  void updateConfig(int i, RoutineExercise config) =>
      _change(() => items[i] = items[i].withConfig(config));

  void remove(int i) => _change(() {
    items.removeAt(i);
    _clean();
  });

  void move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= items.length) return;
    _change(() {
      final item = items.removeAt(i);
      items.insert(to, item);
      _clean();
    });
  }

  /// Links an exercise to the one above it, or unlinks it if they already share a superset.
  void toggleSuperset(int i) {
    if (i == 0) return;
    final above = items[i - 1].config.superset;
    final mine = items[i].config.superset;
    _change(() {
      if (mine != null && mine == above) {
        items[i] = items[i].withConfig(items[i].config.copyWith(superset: () => null));
      } else {
        final group = above ?? 'ss${DateTime.now().microsecondsSinceEpoch}';
        items[i - 1] = items[i - 1].withConfig(items[i - 1].config.copyWith(superset: () => group));
        items[i] = items[i].withConfig(items[i].config.copyWith(superset: () => group));
      }
      _clean();
    });
  }

  bool linkedToAbove(int i) =>
      i > 0 &&
      items[i].config.superset != null &&
      items[i].config.superset == items[i - 1].config.superset;

  /// What the routine works, for the preview map: a target at full shade, a supporting muscle at
  /// half. Read from the library already loaded; nothing is fetched for a preview.
  Map<String, int> get muscleLevels {
    final library = switch (gym.exercises.value) {
      Ready<List<Exercise>>(:final data) => {for (final e in data) e.id: e},
      _ => const <String, Exercise>{},
    };
    final levels = <String, int>{};
    for (final item in items) {
      for (final m in library[item.config.exerciseId]?.muscles ?? const <MuscleShare>[]) {
        final level = m.isPrimary ? 4 : 2;
        if (level > (levels[m.muscle] ?? 0)) levels[m.muscle] = level;
      }
    }
    return levels;
  }

  Future<bool> save(String fallbackName) async {
    final saved = await gym.saveRoutine(
      RoutineDraft(
        id: id,
        name: name.value.trim().isEmpty ? fallbackName : name.value.trim(),
        icon: icon.value,
        progression: progression.value,
        exercises: [for (final i in items) i.config],
      ),
    );
    if (saved != null) dirty.value = false;
    return saved != null;
  }

  Future<bool> delete() async {
    final routineId = id;
    if (routineId == null) return true;
    return gym.deleteRoutine(routineId);
  }

  void _change(void Function() change) {
    change();
    dirty.value = true;
  }

  void _clean() {
    for (var i = 0; i < items.length; i++) {
      final ss = items[i].config.superset;
      if (ss == null) continue;
      final paired =
          (i > 0 && items[i - 1].config.superset == ss) ||
          (i + 1 < items.length && items[i + 1].config.superset == ss);
      if (!paired) items[i] = items[i].withConfig(items[i].config.copyWith(superset: () => null));
    }
  }
}
