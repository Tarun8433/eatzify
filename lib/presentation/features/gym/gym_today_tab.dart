import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/presentation/features/gym/gym_calendar_sheet.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_history_page.dart';
import 'package:health_pro/presentation/features/gym/gym_labels.dart';
import 'package:health_pro/presentation/features/gym/gym_routines_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/routine_edit_page.dart';
import 'package:health_pro/presentation/features/gym/workout_launcher.dart';
import 'package:health_pro/presentation/features/gym/workout_page.dart';
import 'package:health_pro/presentation/features/gym/workout_summary_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Today: this week at a glance, what is planned now, what the workouts burned, and the latest.
class GymTodayTab extends StatelessWidget {
  const GymTodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<GymController>();
    return Obx(
      () => switch (c.overview.value) {
        Loading<GymOverview>() => const LoadingView(lines: 5),
        Empty<GymOverview>() => EmptyView(title: l.gymNoRoutines),
        Failed<GymOverview>(:final failure) => FailedView(
          failure: failure,
          onRetry: c.load,
          retryLabel: l.accountRetry,
        ),
        Ready<GymOverview>(:final data) => RefreshIndicator(
          onRefresh: () => c.load(quietly: true),
          child: _Today(overview: data, controller: c),
        ),
      },
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.overview, required this.controller});

  final GymOverview overview;
  final GymController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final o = overview;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      children: [
        if (o.fromCache) ...[
          HintCard(icon: Icons.cloud_off_outlined, text: l.gymOffline),
          const SizedBox(height: AppSpacing.md),
        ],
        Obx(
          () => c.pending.value == 0
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_upload_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(l.gymPending(c.pending.value))),
                        TextButton(onPressed: c.sendPending, child: Text(l.gymSendNow)),
                      ],
                    ),
                  ),
                ),
        ),
        Obx(() {
          final active = c.active.value;
          if (active == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              onTap: () => WorkoutPage.open(active),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.gymResume, style: theme.textTheme.titleMedium),
                        Text(l.gymResumeBody(active.name, active.doneSets, active.totalSets)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (!o.hasPlan) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.gymWelcomeTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(l.gymWelcomeBody),
                const SizedBox(height: AppSpacing.lg),
                Obx(
                  () => FilledButton(
                    onPressed: c.busy.value ? null : c.loadStarterPlan,
                    child: Text(l.gymLoadStarter),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(onPressed: RoutineEditPage.open, child: Text(l.gymBuildOwn)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _WeekStrip(overview: o),
        const SizedBox(height: AppSpacing.md),
        _TodayCard(overview: o),
        const SizedBox(height: AppSpacing.md),
        GymEnergyCard(totals: o.totals),
        const SizedBox(height: AppSpacing.md),
        _StreakCard(totals: o.totals),
        GymHeading(
          l.gymRecent,
          trailing: o.recent.isEmpty
              ? null
              : TextButton(onPressed: GymHistoryPage.open, child: Text(l.gymSeeAll)),
        ),
        if (o.recent.isEmpty)
          Text(l.gymNoWorkoutsYet, style: theme.textTheme.bodySmall)
        else
          for (final w in o.recent)
            WorkoutTile(workout: w, onTap: () => WorkoutDetailPage.open(w.id)),
      ],
    );
  }
}

/// The streak, in the warm role rather than the data one: this card is encouragement, and it is
/// the way into the month's calendar. Weeks trained, never a weight number (docs/05 §6).
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.totals});

  final GymTotals totals;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = scheme.onTertiaryContainer;

    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GymCalendarSheet.show(context),
        // The card takes the banner's own shape (1961 × 802). Any other shape crops the runner —
        // there is no fit that squeezes a wide banner into a short strip without cutting it.
        child: AspectRatio(
          aspectRatio: 1961 / 802,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: theme.brightness == Brightness.dark ? 0.35 : 1,
                    child: Image.asset(
                      'assets/gym/streak_banner.png',
                      key: const Key('gymStreakArt'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FractionallySizedBox(
                  widthFactor: 0.6,
                  alignment: AlignmentDirectional.centerStart,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: AppSizes.choiceDisc,
                            height: AppSizes.choiceDisc,
                            decoration: BoxDecoration(
                              color: ink.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(AppRadius.card),
                            ),
                            child: Icon(Icons.local_fire_department, color: ink),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              l.gymStreak(totals.streakWeeks),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l.gymWeekProgress(
                          totals.thisWeekWorkouts,
                          totals.plannedPerWeek,
                          totals.totalWorkouts,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monday to Sunday as tiles: a dot for a day trained, an outline for one planned, today filled
/// and ticked. Tapping a day changes that date only.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.overview});

  final GymOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.gymThisWeek, style: theme.textTheme.titleMedium),
                    Text(l.gymWeekTagline, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => GymCalendarSheet.show(context),
                icon: const Icon(Icons.calendar_month_outlined, size: AppSpacing.lg),
                label: Text(l.gymCalendar),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final day in overview.weekDays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
                    child: _DayTile(day: day, overview: overview, scheme: scheme),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.overview, required this.scheme});

  final PlannedDay day;
  final GymOverview overview;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = day.isToday ? scheme.onPrimary : scheme.onSurface;

    return Semantics(
      button: true,
      label: [
        GymLabels.weekdayName(context, day.weekday),
        if (day.trained) l.gymLegendTrained,
        if (day.routineId != null) overview.routineById(day.routineId)?.name ?? '',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => DayPlanSheet.show(context, day),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: day.isToday ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: day.isToday ? Colors.transparent : scheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                child: Text(
                  GymLabels.weekdayName(context, day.weekday, short: true),
                  style: theme.textTheme.bodySmall?.copyWith(color: ink),
                ),
              ),
              FittedBox(
                child: Text(
                  day.diaryDate.substring(8),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Trained is a tick, planned a dot, an empty day a dot at rest — never a red mark.
              Icon(
                day.trained
                    ? Icons.check_circle
                    : day.isRescheduled
                    ? Icons.swap_horiz
                    : Icons.circle,
                size: day.trained || day.isRescheduled ? AppSpacing.md : AppSpacing.xs + 2,
                color: day.trained
                    ? (day.isToday ? scheme.onPrimary : scheme.secondary)
                    : ink.withValues(alpha: day.routineId != null ? 0.55 : 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.overview});

  final GymOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final routine = overview.todaysRoutine;
    final day = overview.today;
    final rest = day.source == DaySource.restOverride;
    final meta = [
      if (routine != null) l.gymExerciseCount(routine.items.length),
      if (day.isRescheduled) l.gymRescheduled,
    ].join(' · ');

    // Green, not the warm beige the other emphasised cards use: this is the one card on the screen
    // that is about doing something rather than reading something.
    return Container(
      decoration: BoxDecoration(
        color: routine == null ? scheme.surface : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(
          color: routine == null ? scheme.outline : scheme.primary.withValues(alpha: 0.25),
        ),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // The figure fills the trailing 40 % of the card, top to bottom, sized by fractions of
          // the card rather than by the 1536 px bitmap.
          Positioned.fill(
            child: ExcludeSemantics(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FractionallySizedBox(
                  widthFactor: 0.4,
                  heightFactor: 1,
                  child: Opacity(
                    opacity: theme.brightness == Brightness.dark ? 0.35 : 1,
                    child: Image.asset(
                      'assets/gym/today_card.png',
                      key: const Key('gymTodayArt'),
                      // Contain, never cover: cover fills the box by cutting the figure off.
                      fit: BoxFit.contain,
                      alignment: AlignmentDirectional.bottomEnd,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FractionallySizedBox(
              widthFactor: 0.58,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        l.gymToday,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    routine?.name ?? (rest ? l.gymRestDay : l.gymNothingPlanned),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (meta.isNotEmpty) Text(meta, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      // A card action: the theme's primary button is 56 dp of h2 text, sized for
                      // the one thing a whole screen asks for, not a button inside a card.
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, AppSpacing.minTouchTarget),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        textStyle: theme.textTheme.labelLarge,
                      ),
                      onPressed: () => routine != null
                          ? WorkoutLauncher.start(context, routine: routine)
                          : WorkoutLauncher.start(context, chooseFirst: true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(routine != null ? l.gymStart : l.gymStartWorkout),
                    ),
                  ),
                  if (routine != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => RoutineEditPage.open(routine: routine),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right, size: AppSpacing.lg),
                        label: Text(l.gymViewDetails),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GymEnergyCard extends StatelessWidget {
  const GymEnergyCard({required this.totals, super.key});

  final GymTotals totals;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String figure(int? kcal) => kcal == null ? '—' : l.gymKcalValue(kcal);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GymIconDisc(icon: Icons.bolt_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.gymKcalTitle, style: theme.textTheme.titleMedium),
                    Text(l.gymEnergySubtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.gymEnergyInfoTitle,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l.gymEnergyInfoTitle),
                    content: Text(l.gymKcalExplainer),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(l.gymDone)),
                    ],
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Figure(label: l.gymToday, value: figure(totals.todayKcal)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Figure(label: l.gymThisWeek, value: figure(totals.weekKcal)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
