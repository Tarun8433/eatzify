import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/macro_tile.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// One day of a client's diary, for the coach they shared it with (D-206).
///
/// **The date comes from the server.** `CLAUDE.md` rule 8 — the 04:00 IST diary boundary is never
/// computed in the app, so the first load asks for "today" by sending no date at all and every
/// step from there moves relative to the date that came back.
class ClientDiaryController extends GetxController {
  ClientDiaryController({required this.coach, required this.clientUserId});

  final CoachRepository coach;
  final int clientUserId;

  final state = Rx<ViewState<DiaryDay>>(const Loading());

  /// Null until the first day arrives. The app never invents one.
  final date = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({String? on}) async {
    state.value = const Loading();
    final result = await coach.clientDiary(clientUserId, date: on);

    state.value = result.fold(
      (f) {
        // A 404 is the grant not carrying `progress`, which is the client's decision rather than a
        // fault. Nothing to retry.
        if (f is ApiFailure && f.status == 404) return const Empty();
        return Failed(f);
      },
      (day) {
        date.value = day.diaryDate;
        return day.entries.isEmpty ? const Empty() : Ready(day);
      },
    );
  }

  /// Step back or forward a day from whatever the server last said.
  ///
  /// Nothing forward of today: a diary for tomorrow does not exist, and an arrow that leads to an
  /// empty day teaches a coach the screen is broken.
  Future<void> step(int days) async {
    final from = date.value;
    if (from == null) return;

    final moved = DateTime.parse(from).add(Duration(days: days));
    await load(on: DateFormat('yyyy-MM-dd').format(moved));
  }
}

class ClientDiaryPage extends StatelessWidget {
  const ClientDiaryPage({required this.clientUserId, required this.name, super.key});

  final int clientUserId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.put(
      ClientDiaryController(coach: Get.find<CoachRepository>(), clientUserId: clientUserId),
      tag: 'diary-$clientUserId',
    );

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Column(
        children: [
          _DayBar(controller: c),
          Expanded(
            child: Obx(
              () => switch (c.state.value) {
                Loading<DiaryDay>() => const LoadingView(),
                // Nothing logged is not a failure and not a missing screen. It is the answer, and
                // for a coach it is a useful one.
                Empty<DiaryDay>() => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: EmptyView(title: l.coachDiaryTitle, body: l.coachDiaryEmpty),
                ),
                Failed<DiaryDay>(:final failure) => FailedView(failure: failure, onRetry: c.load),
                Ready<DiaryDay>(:final data) => _Day(day: data),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Which day is on screen, and the two arrows that change it.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.controller});

  final ClientDiaryController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final on = controller.date.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              onPressed: on == null ? null : () => controller.step(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
            ),
            Expanded(
              child: Text(
                on == null ? '' : _dayLabel(l, on),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              // Dead on the newest day the server has given us. There is no diary for tomorrow.
              onPressed: on == null || _isToday(on) ? null : () => controller.step(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
            ),
          ],
        ),
      );
    });
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bySlot = <String, List<LogEntry>>{};
    for (final entry in day.entries) {
      (bySlot[entry.slot] ??= []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      children: [
        _Totals(day: day),
        const SizedBox(height: AppSpacing.md),
        // In the order the day happens, not the order rows arrived. A coach reads a diary
        // chronologically because that is how somebody ate it.
        for (final slot in _slotOrder.where(bySlot.containsKey))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _Slot(slot: slot, entries: bySlot[slot]!),
          ),
        const SizedBox(height: AppSpacing.sm),
        _Activity(day: day),
        // Only when there IS no plan. It was printing under a screen full of targets, which is a
        // screen telling a coach two different things at once.
        if (day.targets == null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l.coachDiaryNoTargets,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// The day against the plan, as one line per macro.
class _Totals extends StatelessWidget {
  const _Totals({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = day.targets;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.coachDiaryTotals,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A ring, not `CalorieGauge`. That widget headlines what is LEFT — the number a person
          // eats against — and a coach is asking the opposite question: what did they eat, against
          // what were they asked to. Same shape, honest framing.
          Center(
            child: ProgressRing(
              size: AppSizes.ringMacro * 2,
              strokeWidth: 10,
              sweep: 0.78,
              color: AppColors.warmCoral,
              trackColor: AppColors.warmCoral.withValues(alpha: 0.18),
              progress: targets == null || targets.kcal == 0
                  ? null
                  : day.totals.kcal / targets.kcal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${day.totals.kcal.round()}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (targets case final plan?)
                    Text(
                      l.coachOfTarget('', '${plan.kcal.round()}').trim(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    l.coachDiaryCalories,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // The same three tiles the client sees on their own Home tab. An even share of the row
          // when they fit, and a horizontal scroll when the text scale means they do not — one
          // branch, the way Home's nutrient row does it.
          LayoutBuilder(
            builder: (context, box) {
              const gap = AppSpacing.sm;
              final even = (box.maxWidth - gap * 2) / 3;
              final width = math.max(even, AppSizes.nutrientTile);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Room for the tiles' shadow inside the scroll clip.
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: width,
                        child: MacroTile(
                          icon: Icons.egg_outlined,
                          color: AppColors.macroProtein,
                          label: l.homeProtein,
                          eaten: day.totals.proteinG,
                          target: targets?.proteinG,
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: width,
                        child: MacroTile(
                          icon: Icons.grain,
                          color: AppColors.macroCarb,
                          label: l.homeCarbs,
                          eaten: day.totals.carbG,
                          target: targets?.carbG,
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: width,
                        child: MacroTile(
                          icon: Icons.water_drop_outlined,
                          color: AppColors.macroFat,
                          label: l.homeFat,
                          eaten: day.totals.fatG,
                          target: targets?.fatG,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One meal, and what went into it.
class _Slot extends StatelessWidget {
  const _Slot({required this.slot, required this.entries});

  final String slot;
  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kcal = entries.fold<double>(0, (sum, e) => sum + e.kcal);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  coachSlotLabel(l, slot),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${kcal.round()} ${l.coachDiaryKcal}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Divider(),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // What they ate and how much of it. The measure the client actually chose —
                      // "1.5 katori" is what they logged; 137 g is what a database stored.
                      entry.measureLabel == null
                          ? entry.name
                          : '${entry.name}  ·  ${entry.measureLabel}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${entry.kcal.round()}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Steps, calories burned and water for the same day.
///
/// Null is "not recorded", never zero — "they burned nothing" and "nobody measured" are different
/// sentences and only one of them is ever true.
class _Activity extends StatelessWidget {
  const _Activity({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final rows = <(IconData, Color, String, String)>[
      (
        Icons.directions_walk,
        AppColors.success,
        l.coachDiaryMoved,
        day.steps?.toString() ?? l.coachDiaryNotRecorded,
      ),
      (
        Icons.local_fire_department_outlined,
        AppColors.warmCoral,
        l.coachDiaryBurned,
        day.energyBurnedKcal == null
            ? l.coachDiaryNotRecorded
            : '${day.energyBurnedKcal} ${l.coachDiaryKcal}',
      ),
      (
        Icons.water_drop_outlined,
        AppColors.macroFat,
        l.coachDiaryWater,
        day.waterLoggedMl == null ? l.coachDiaryNotRecorded : '${day.waterLoggedMl} ml',
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (final (icon, tint, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      height: AppSizes.choiceDisc,
                      width: AppSizes.choiceDisc,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Icon(icon, size: AppSpacing.lg, color: tint),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The order a day happens in, so the diary reads the way it was eaten.
const _slotOrder = ['breakfast', 'mid_morning', 'lunch', 'snack', 'evening', 'dinner', 'bedtime'];

/// The same words the client's own diary uses. Two vocabularies for one meal would have a coach
/// and a client talking past each other (rule 4).
String coachSlotLabel(AppLocalizations l, String slot) => switch (slot) {
  'breakfast' => l.slotBreakfast,
  'mid_morning' => l.slotMidMorning,
  'lunch' => l.slotLunch,
  'snack' => l.slotSnack,
  'evening' => l.slotEvening,
  'dinner' => l.slotDinner,
  _ => l.slotBedtime,
};

String _dayLabel(AppLocalizations l, String diaryDate) {
  if (_isToday(diaryDate)) return l.coachDiaryToday;

  final on = DateTime.tryParse(diaryDate);
  if (on == null) return diaryDate;

  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  if (DateFormat('yyyy-MM-dd').format(yesterday) == diaryDate) {
    return l.coachDiaryYesterday;
  }

  return DateFormat.yMMMEd().format(on);
}

/// Only a label decision, never an access one. The SERVER owns the diary boundary (rule 8); this
/// just decides whether to print "Today" or a date, and being an hour off says the wrong word
/// rather than showing the wrong day.
bool _isToday(String diaryDate) => DateFormat('yyyy-MM-dd').format(DateTime.now()) == diaryDate;
