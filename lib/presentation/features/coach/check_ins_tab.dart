import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/check_ins_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// The coach's Check-ins tab (docs/02 FR-5.2 and FR-5.3): who needs attention, and this week's
/// reviews in the order the server says they matter.
class CheckInsTab extends StatelessWidget {
  const CheckInsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.put(CheckInsController(coach: Get.find<CoachRepository>()), permanent: true);

    return Obx(
      () => switch (c.state.value) {
        Loading<List<CheckIn>>() => const LoadingView(),
        Failed<List<CheckIn>>(:final failure) => FailedView(failure: failure, onRetry: c.load),
        Empty<List<CheckIn>>() => EmptyView(title: l.checkinsEmpty, body: l.checkinsEmptyBody),
        Ready<List<CheckIn>>(:final data) => _Queue(controller: c, rows: data),
      },
    );
  }
}

class _Queue extends StatelessWidget {
  const _Queue({required this.controller, required this.rows});

  final CheckInsController controller;
  final List<CheckIn> rows;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final open = rows.where((r) => r.isOpen).toList();
    final done = rows.where((r) => !r.isOpen).toList();

    return RefreshIndicator(
      onRefresh: () => controller.load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          // docs/02 FR-5.3, above the queue: the four signals are what decides where to start.
          Obx(() {
            final alerts = controller.alerts;
            if (alerts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.checkinsAlerts, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final alert in alerts) ...[
                  _AlertCard(alert: alert),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            );
          }),

          Obx(() {
            final message = controller.error.value;
            return message == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  );
          }),

          if (open.isNotEmpty) ...[
            Text(l.checkinsThisWeek, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final row in open) ...[
              _CheckInCard(controller: controller, row: row),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],

          if (done.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l.checkinsDone, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final row in done) ...[
              _CheckInCard(controller: controller, row: row),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final CoachAlert alert;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alert.name, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          // Rule 4: the wire value never reaches the screen.
          for (final kind in alert.kinds)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_outlined, size: AppSpacing.lg, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(_label(l, kind), style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _label(AppLocalizations l, String kind) => switch (kind) {
    'no_logs' => l.alertNoLogs('${alert.daysSinceLastLog ?? 0}'),
    'off_trend' => l.alertOffTrend,
    'plan_expiring' => l.alertPlanExpiring('${alert.planEndsInDays ?? 0}'),
    'checkin_missed' => l.alertCheckinMissed,
    // A signal this build has no words for is left out rather than printed raw.
    _ => '',
  };
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.controller, required this.row});

  final CheckInsController controller;
  final CheckIn row;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final due = DateTime.tryParse(row.dueOn);
    final dates = DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag());

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(row.name, style: theme.textTheme.titleMedium)),
              if (row.isMissed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(l.checkinsMissed, style: muted),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(due == null ? row.dueOn : l.checkinsDueOn(dates.format(due)), style: muted),
          const SizedBox(height: AppSpacing.xs),
          Text(_activity(l), style: theme.textTheme.bodyMedium),
          if (row.actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final action in row.actions)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: AppSpacing.lg, color: AppColors.success),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(action, style: theme.textTheme.bodyMedium)),
                ],
              ),
          ],
          if (row.isOpen) ...[
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  onPressed: controller.saving.value != null
                      ? null
                      : () => _review(context, controller, row),
                  child: Text(l.checkinsReview),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What the coach opened this to find out: whether the person is still logging.
  String _activity(AppLocalizations l) {
    final days = row.daysSinceLastLog;
    if (days != null && days >= 1) return l.checkinsNoLogsFor('$days');
    if (row.adherencePct case final pct?) return l.checkinsAdherence('$pct');
    return l.checkinsLoggedToday;
  }

  static Future<void> _review(
    BuildContext context,
    CheckInsController controller,
    CheckIn row,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await showModalBottomSheet<({String notes, List<String> actions})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(name: row.name),
    );
    if (result == null) return;

    final saved = await controller.complete(row.id, notes: result.notes, actions: result.actions);
    if (!saved) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.checkinsSaved)));
  }
}

/// docs/09 §6's body: a note for the coach, and the actions the client will actually see.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.name});

  final String name;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _notes = TextEditingController();
  final _action = TextEditingController();
  final _actions = <String>[];

  @override
  void dispose() {
    _notes.dispose();
    _action.dispose();
    super.dispose();
  }

  void _add() {
    final text = _action.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _actions.add(text);
      _action.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.checkinsReviewTitle(widget.name),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _notes,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: l.checkinsNotes,
                  helperText: l.checkinsNotesHint,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _action,
                      maxLength: 200,
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(labelText: l.checkinsAction),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: FilledButton.tonal(onPressed: _add, child: Text(l.checkinsActionAdd)),
                  ),
                ],
              ),
              if (_actions.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final action in _actions)
                      InputChip(
                        label: Text(action),
                        onDeleted: () => setState(() => _actions.remove(action)),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSizes.primaryButton,
                child: FilledButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop((notes: _notes.text, actions: List<String>.unmodifiable(_actions))),
                  child: Text(l.checkinsSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
