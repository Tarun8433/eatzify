import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/presentation/features/gym/exercise_browser.dart';
import 'package:health_pro/presentation/features/gym/exercise_config_sheet.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/routine_edit_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Builds or changes a routine: its name and icon, its progression rule, and its exercises in
/// order — each tapped to set how it is done, moved, linked into a superset, or removed.
class RoutineEditPage extends StatelessWidget {
  const RoutineEditPage({super.key});

  static Future<void>? open({Routine? routine, List<RoutineItem> initialItems = const []}) =>
      Get.to<void>(
        () => const RoutineEditPage(),
        binding: BindingsBuilder<void>(() {
          final gym = Get.find<GymController>()..loadExercises();
          Get.lazyPut(
            () => RoutineEditController(gym: gym, routine: routine, initialItems: initialItems),
          );
        }),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<RoutineEditController>();

    Future<void> save() async {
      if (await c.save(l.gymNewRoutine) && context.mounted) Navigator.pop(context);
    }

    return Obx(
      () => PopScope(
        canPop: !c.dirty.value,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final discard = await confirmGym(
            context,
            title: l.gymDiscardChanges,
            confirm: l.gymDiscard,
            destructive: true,
          );
          if (discard && context.mounted) {
            c.dirty.value = false;
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(c.isNew ? l.gymNewRoutine : l.gymRoutines),
            actions: [
              Obx(
                () => TextButton(onPressed: c.gym.busy.value ? null : save, child: Text(l.gymSave)),
              ),
            ],
          ),
          body: _Body(controller: c),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final RoutineEditController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      children: [
        TextFormField(
          initialValue: c.name.value,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l.gymRoutineName, hintText: l.gymNewRoutine),
          onChanged: c.rename,
        ),
        Text(l.gymRoutineIcon, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Obx(
          () => Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final icon in RoutineIcon.values)
                IconButton(
                  tooltip: GymLabels.icon(l, icon),
                  isSelected: c.icon.value == icon,
                  style: IconButton.styleFrom(
                    backgroundColor: c.icon.value == icon
                        ? theme.colorScheme.secondaryContainer
                        : null,
                  ),
                  onPressed: () => c.setIcon(icon),
                  icon: Icon(GymLabels.iconFor(icon)),
                ),
            ],
          ),
        ),
        GymHeading(l.gymProgression),
        Obx(
          () => DropdownButtonFormField<ProgressionRule>(
            initialValue: c.progression.value,
            isExpanded: true,
            items: [
              for (final rule in ProgressionRule.routineRules)
                DropdownMenuItem(value: rule, child: Text(GymLabels.rule(l, rule))),
            ],
            onChanged: (rule) {
              if (rule != null) c.setRule(rule);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Obx(
          () => Text(
            '${GymLabels.ruleBody(l, c.progression.value)} ${l.gymProgressionNote}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        GymHeading(l.gymTabExercises),
        Obx(
          () => Column(
            children: [
              if (c.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(l.gymRoutineEmpty, style: theme.textTheme.bodySmall),
                ),
              for (var i = 0; i < c.items.length; i++) _ItemRow(controller: c, index: i),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await ExercisePickerPage.pick();
            if (picked != null) c.add(picked);
          },
          icon: const Icon(Icons.add),
          label: Text(l.gymAddExercise),
        ),
        Obx(() {
          final levels = c.muscleLevels;
          if (levels.isEmpty) return const SizedBox.shrink();
          final female = c.gym.ready?.settings.bodyFigure == BodyFigure.female;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GymHeading(l.gymWhatThisWorks),
              AppCard(
                child: BodyMap(
                  levels: levels,
                  female: female,
                  semanticsLabel: l.gymMuscleMapLabel(
                    levels.keys.map((m) => GymLabels.muscle(l, m)).join(', '),
                  ),
                ),
              ),
            ],
          );
        }),
        if (!c.isNew) ...[
          const SizedBox(height: AppSpacing.xl),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () async {
              final sure = await confirmGym(
                context,
                title: l.gymDeleteRoutine,
                body: l.gymDeleteRoutineConfirm,
                confirm: l.gymDelete,
                destructive: true,
              );
              if (!sure) return;
              if (await c.delete() && context.mounted) {
                c.dirty.value = false;
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(l.gymDeleteRoutine),
          ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.controller, required this.index});

  final RoutineEditController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final item = c.items[index];
    final linked = c.linkedToAbove(index);
    final inSuperset = item.config.superset != null;

    return Container(
      margin: EdgeInsets.only(top: linked ? 0 : AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: inSuperset ? theme.colorScheme.secondary : Colors.transparent,
            width: AppSpacing.xs,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: AppSpacing.sm),
        leading: GymIconDisc(icon: GymLabels.bodyPartIcon(item.bodyPart)),
        title: Text(GymLabels.name(item.name)),
        subtitle: Text(
          [
            if (linked) l.gymSuperset,
            GymLabels.summary(l, item.config, bodyweight: item.isBodyweight),
          ].join(' · '),
        ),
        onTap: () async {
          final next = await ExerciseConfigSheet.show(context, item, c.progression.value);
          if (next != null) c.updateConfig(index, next);
        },
        trailing: PopupMenuButton<String>(
          onSelected: (action) => switch (action) {
            'up' => c.move(index, -1),
            'down' => c.move(index, 1),
            'superset' => c.toggleSuperset(index),
            _ => c.remove(index),
          },
          itemBuilder: (context) => [
            if (index > 0) PopupMenuItem(value: 'up', child: Text(l.gymMoveUp)),
            if (index < c.items.length - 1)
              PopupMenuItem(value: 'down', child: Text(l.gymMoveDown)),
            if (index > 0)
              CheckedPopupMenuItem(
                value: 'superset',
                checked: linked,
                child: Text(l.gymSupersetAbove),
              ),
            PopupMenuItem(value: 'remove', child: Text(l.gymRemoveFromRoutine)),
          ],
        ),
      ),
    );
  }
}
