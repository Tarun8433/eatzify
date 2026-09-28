import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/usecases/exercise_filter.dart';
import 'package:health_pro/presentation/features/gym/custom_exercise_sheet.dart';
import 'package:health_pro/presentation/features/gym/exercise_media.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The exercise library: search, a body-part row, an equipment row built from what is left, and a
/// paged list. The Exercises tab and the "choose an exercise" picker are both this.
class ExerciseBrowser extends StatefulWidget {
  const ExerciseBrowser({required this.onTap, super.key, this.showCreate = true});

  final ValueChanged<Exercise> onTap;
  final bool showCreate;

  @override
  State<ExerciseBrowser> createState() => _ExerciseBrowserState();
}

class _ExerciseBrowserState extends State<ExerciseBrowser> {
  static const _page = 40;

  final _gym = Get.find<GymController>();
  var _query = const ExerciseQuery();
  var _shown = _page;

  @override
  void initState() {
    super.initState();
    _gym.loadExercises();
  }

  /// Exercise id → how many routines use it, for the "Chosen" chip.
  Map<String, int> get _usage {
    final usage = <String, int>{};
    for (final routine in _gym.ready?.routines ?? const <Routine>[]) {
      for (final item in routine.items) {
        usage[item.config.exerciseId] = (usage[item.config.exerciseId] ?? 0) + 1;
      }
    }
    return usage;
  }

  void _set(ExerciseQuery q) => setState(() {
    _query = q;
    _shown = _page;
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Obx(
      () => switch (_gym.exercises.value) {
        Loading<List<Exercise>>() => const LoadingView(lines: 6),
        Failed<List<Exercise>>(:final failure) => FailedView(
          failure: failure,
          onRetry: () => _gym.loadExercises(force: true),
          retryLabel: l.accountRetry,
        ),
        Empty<List<Exercise>>() => EmptyView(title: l.gymNoMatches),
        Ready<List<Exercise>>(:final data) => _list(context, data),
      },
    );
  }

  Widget _list(BuildContext context, List<Exercise> all) {
    final l = AppLocalizations.of(context);
    final usage = _usage;
    final filtered = filterExercises(all, _query, usage: usage);
    final visible = filtered.results.take(_shown).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.sm,
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: l.gymSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (text) => _set(_query.copyWith(text: text)),
          ),
        ),
        GymChipRow<String?>(
          options: [null, if (usage.isNotEmpty) '★', ...gymBodyParts],
          selected: _query.chosenOnly ? '★' : _query.bodyPart,
          label: (b) => switch (b) {
            null => l.gymAll,
            '★' => l.gymChosen(usage.length),
            _ => GymLabels.bodyPart(l, b),
          },
          onSelected: (b) => _set(
            ExerciseQuery(text: _query.text, chosenOnly: b == '★', bodyPart: b == '★' ? null : b),
          ),
        ),
        if (filtered.equipment.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          GymChipRow<String?>(
            options: [null, ...filtered.equipment],
            selected: filtered.equipmentApplied,
            label: (e) => e == null ? l.gymAnyEquipment : GymLabels.equipment(l, e),
            onSelected: (e) => _set(_query.copyWith(equipment: () => e)),
          ),
        ],
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.xxl,
            ),
            children: [
              if (widget.showCreate)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const GymIconDisc(icon: Icons.auto_awesome_outlined),
                  title: Text(l.gymCreateExercise),
                  subtitle: Text(l.gymCreateExerciseBody),
                  onTap: () async {
                    final made = await CustomExerciseSheet.show(context);
                    if (made != null) widget.onTap(made);
                  },
                ),
              if (filtered.results.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyView(title: l.gymNoMatches, body: l.gymNoMatchesBody),
                ),
              for (final e in visible) ExerciseRow(exercise: e, onTap: () => widget.onTap(e)),
              if (filtered.results.length > visible.length)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _shown += _page),
                    child: Text(l.gymShowMore),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One library exercise: its body part's glyph, its name, and what it works with what.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({required this.exercise, required this.onTap, super.key, this.trailing});

  final Exercise exercise;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = exercise;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: e.thumbUrl == null
          ? GymIconDisc(icon: GymLabels.bodyPartIcon(e.bodyPart))
          : ExerciseMedia(url: null, thumbUrl: e.thumbUrl, maxSide: AppSizes.choiceDisc),
      title: Text(GymLabels.name(e.name, custom: e.isCustom)),
      subtitle: Text(
        [
          if (e.target.isNotEmpty)
            GymLabels.target(l, e.target)
          else
            GymLabels.bodyPart(l, e.bodyPart),
          GymLabels.equipment(l, e.equipment),
        ].join(' · '),
      ),
      trailing: trailing ?? (e.isCustom ? Chip(label: Text(l.gymCustomTag)) : null),
    );
  }
}

/// "Choose an exercise": the browser on its own screen, answering with the one tapped.
class ExercisePickerPage extends StatelessWidget {
  const ExercisePickerPage({super.key});

  static Future<Exercise?> pick() =>
      Get.to<Exercise>(() => const ExercisePickerPage()) ?? Future.value();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).gymPickExerciseTitle)),
      body: ExerciseBrowser(onTap: (e) => Get.back<Exercise>(result: e)),
    );
  }
}
