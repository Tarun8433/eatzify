import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Create or edit one of the person's own exercises: a name and a body part, a description if
/// they want one. The server refuses a duplicate name and its message is what is shown.
class CustomExerciseSheet extends StatefulWidget {
  const CustomExerciseSheet({super.key, this.editing});

  final Exercise? editing;

  static Future<Exercise?> show(BuildContext context, {Exercise? editing}) =>
      showModalBottomSheet<Exercise>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => CustomExerciseSheet(editing: editing),
      );

  @override
  State<CustomExerciseSheet> createState() => _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends State<CustomExerciseSheet> {
  static const _nameMax = 60;
  static const _descriptionMax = 1000;

  final _gym = Get.find<GymController>();
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _description = TextEditingController(text: widget.editing?.description ?? '');
  late String? _bodyPart = widget.editing?.bodyPart;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bodyPart = _bodyPart;
    if (_name.text.trim().isEmpty || bodyPart == null) return;
    _gym.message.value = null;
    final saved = await _gym.saveExercise(
      id: widget.editing?.id,
      name: _name.text.trim(),
      bodyPart: bodyPart,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    );
    if (!mounted) return;
    if (saved != null) {
      Navigator.pop(context, saved);
    } else {
      setState(() => _error = _gym.message.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.editing == null ? l.gymCreateExercise : l.gymEditExercise,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              maxLength: _nameMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.gymExerciseName),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l.gymBodyPart, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final part in gymBodyParts)
                  ChoiceChip(
                    label: Text(GymLabels.bodyPart(l, part)),
                    selected: _bodyPart == part,
                    onSelected: (_) => setState(() => _bodyPart = part),
                  ),
              ],
            ),
            if (_bodyPart == 'cardio') ...[
              const SizedBox(height: AppSpacing.sm),
              Text(l.gymCardioNote, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _description,
              maxLength: _descriptionMax,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.gymDescription),
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Obx(
              () => FilledButton(
                onPressed: _gym.busy.value || _name.text.trim().isEmpty || _bodyPart == null
                    ? null
                    : _save,
                child: Text(l.gymSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
