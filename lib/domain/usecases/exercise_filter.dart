import 'package:health_pro/domain/entities/gym/exercise.dart';

/// What the library is being narrowed by.
class ExerciseQuery {
  const ExerciseQuery({this.text = '', this.bodyPart, this.equipment, this.chosenOnly = false});

  final String text;
  final String? bodyPart;
  final String? equipment;

  /// Only exercises already in one of the person's routines, most-used first.
  final bool chosenOnly;

  ExerciseQuery copyWith({
    String? text,
    String? Function()? bodyPart,
    String? Function()? equipment,
    bool? chosenOnly,
  }) => ExerciseQuery(
    text: text ?? this.text,
    bodyPart: bodyPart != null ? bodyPart() : this.bodyPart,
    equipment: equipment != null ? equipment() : this.equipment,
    chosenOnly: chosenOnly ?? this.chosenOnly,
  );
}

/// The library narrowed by [query]. Equipment options are worked out from what the other filters
/// leave, most common first — so every equipment chip on screen has results behind it, and a
/// chip the other filters have emptied is dropped rather than leaving an empty list.
({List<Exercise> results, List<String> equipment, String? equipmentApplied}) filterExercises(
  List<Exercise> all,
  ExerciseQuery query, {
  Map<String, int> usage = const {},
}) {
  final text = query.text.trim().toLowerCase();
  var list = query.chosenOnly
      ? (all.where((e) => usage.containsKey(e.id)).toList()
          ..sort((a, b) => (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0)))
      : all;
  if (query.bodyPart != null) list = list.where((e) => e.bodyPart == query.bodyPart).toList();
  if (text.isNotEmpty) {
    list = list
        .where(
          (e) =>
              e.name.toLowerCase().contains(text) ||
              e.target.toLowerCase().contains(text) ||
              e.equipment.toLowerCase().contains(text) ||
              (e.description?.toLowerCase().contains(text) ?? false),
        )
        .toList();
  }

  final counts = <String, int>{};
  for (final e in list) {
    counts[e.equipment] = (counts[e.equipment] ?? 0) + 1;
  }
  final equipment = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  final applied = equipment.contains(query.equipment) ? query.equipment : null;
  if (applied != null) list = list.where((e) => e.equipment == applied).toList();
  return (results: list, equipment: equipment, equipmentApplied: applied);
}
