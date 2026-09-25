import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/presentation/features/gym/exercise_browser.dart';
import 'package:health_pro/presentation/features/gym/exercise_detail_sheet.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_routines_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_settings_page.dart';
import 'package:health_pro/presentation/features/gym/gym_stats_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_stats_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_today_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The Gym section (ADR-013, D-241): a pushed hub with its own tabs — Today, Routines, Exercises,
/// Stats — reached from Home's workout card and from You. Not a sixth tab on the shell.
class GymPage extends StatefulWidget {
  const GymPage({super.key, this.initialTab = 0});

  final int initialTab;

  static Future<void>? open({int initialTab = 0}) => Get.to<void>(
    () => GymPage(initialTab: initialTab),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => GymStatsController(gym: Get.find<GymRepository>()));
    }),
  );

  @override
  State<GymPage> createState() => _GymPageState();
}

class _GymPageState extends State<GymPage> {
  final _gym = Get.find<GymController>();
  late final Worker _messages;

  @override
  void initState() {
    super.initState();
    _gym.load(quietly: true);
    // A refused action says why once, in the server's words (rule 7), then the message is spent.
    _messages = ever(_gym.message, (String? text) {
      if (text == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      _gym.message.value = null;
    });
  }

  @override
  void dispose() {
    _messages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const GymIconDisc(icon: Icons.fitness_center),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.gymTitle),
                    Text(
                      l.gymHeaderTagline,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: IconButton.filledTonal(
                tooltip: l.gymSettings,
                onPressed: GymSettingsPage.open,
                icon: const Icon(Icons.tune),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // A lit pill for the tab you are on, the way the + sheet's tabs read (D-122) — with the
            // label colour carrying it too, since a tint alone is a colour-only difference.
            indicator: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(AppRadius.pill),
            labelColor: Theme.of(context).colorScheme.onSecondaryContainer,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            tabs: [
              Tab(text: l.gymTabToday),
              Tab(text: l.gymTabRoutines),
              Tab(text: l.gymTabExercises),
              Tab(text: l.gymTabStats),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const GymTodayTab(),
            const GymRoutinesTab(),
            ExerciseBrowser(onTap: (e) => ExerciseDetailSheet.show(context, e.id)),
            const GymStatsTab(),
          ],
        ),
      ),
    );
  }
}
