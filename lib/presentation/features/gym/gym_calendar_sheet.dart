import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_routines_tab.dart';
import 'package:health_pro/presentation/features/gym/workout_summary_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// A month of training: days trained, days planned, days changed. The grid — which days, which
/// weekday each falls on — comes from the server; the phone lays it out.
class GymCalendarSheet extends StatefulWidget {
  const GymCalendarSheet({required this.month, super.key});

  /// YYYY-MM.
  final String month;

  /// Opens on the month of the server's today — the phone's clock only when there is no overview.
  static Future<void> show(BuildContext context, {String? month}) {
    final today = Get.find<GymController>().ready?.today.diaryDate;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => GymCalendarSheet(
        month: month ?? today?.substring(0, 7) ?? DateFormat('yyyy-MM').format(DateTime.now()),
      ),
    );
  }

  @override
  State<GymCalendarSheet> createState() => _GymCalendarSheetState();
}

class _GymCalendarSheetState extends State<GymCalendarSheet> {
  late String _month = widget.month;
  ViewState<GymCalendar> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    final result = await Get.find<GymRepository>().calendar(_month);
    if (mounted) setState(() => _state = result.fold(Failed.new, Ready.new));
  }

  /// Moving a month is calendar arithmetic, not a diary boundary: the server still says what each
  /// day is.
  void _shift(int months) {
    final d = DateTime.parse('$_month-01');
    _month = DateFormat('yyyy-MM').format(DateTime(d.year, d.month + months));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l.gymPrevMonth,
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM(locale).format(DateTime.parse('$_month-01')),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l.gymNextMonth,
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            switch (_state) {
              Loading<GymCalendar>() => const LoadingView(lines: 4),
              Empty<GymCalendar>() => EmptyView(title: l.gymNoWorkoutsYet),
              Failed<GymCalendar>(:final failure) => FailedView(
                failure: failure,
                onRetry: _load,
                retryLabel: l.accountRetry,
              ),
              Ready<GymCalendar>(:final data) => _Grid(calendar: data),
            },
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.calendar});

  final GymCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (var d = 1; d <= DateTime.daysPerWeek; d++)
              Expanded(
                child: Center(
                  child: Text(
                    GymLabels.weekdayName(context, d, short: true),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
        for (final week in calendar.weeks)
          Row(
            children: [
              for (final day in week)
                Expanded(
                  child: Opacity(
                    opacity: day.inMonth ? 1 : 0.35,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      onTap: () => _open(context, day),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: AppSpacing.xl + AppSpacing.sm,
                              height: AppSpacing.xl + AppSpacing.sm,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: day.trained ? scheme.secondary : null,
                                border: day.isToday
                                    ? Border.all(color: scheme.primary, width: 2)
                                    : null,
                              ),
                              child: FittedBox(
                                child: Text(
                                  '${int.parse(day.date.substring(8))}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: day.trained ? scheme.onSecondary : null,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: AppSpacing.xs + 2,
                              height: AppSpacing.xs + 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: day.routineId != null && !day.trained
                                    ? (day.source.wire == 'weekly'
                                          ? scheme.outline
                                          : scheme.primary)
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l.gymCalendarSummary(calendar.workouts, calendar.minutes),
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, CalendarDay day) async {
    if (day.trained) {
      await WorkoutDetailPage.open(day.workouts.first.id);
      return;
    }
    await DayPlanSheet.show(
      context,
      PlannedDay(
        diaryDate: day.date,
        weekday: DateTime.parse(day.date).weekday,
        source: day.source,
        routineId: day.routineId,
        isToday: day.isToday,
      ),
    );
  }
}
