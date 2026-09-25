import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/presentation/features/gym/gym_widgets.dart';
import 'package:health_pro/presentation/features/gym/workout_summary_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Every workout, newest first, a page at a time (cursor paging — the list only grows).
class GymHistoryPage extends StatefulWidget {
  const GymHistoryPage({super.key});

  static Future<void>? open() => Get.to<void>(() => const GymHistoryPage());

  @override
  State<GymHistoryPage> createState() => _GymHistoryPageState();
}

class _GymHistoryPageState extends State<GymHistoryPage> {
  ViewState<List<WorkoutSummary>> _state = const Loading();
  String? _cursor;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    final result = await Get.find<GymRepository>().history();
    if (!mounted) return;
    setState(() {
      _state = result.fold(Failed.new, (page) {
        _cursor = page.nextCursor;
        return page.workouts.isEmpty ? const Empty() : Ready(page.workouts);
      });
    });
  }

  Future<void> _more(List<WorkoutSummary> shown) async {
    setState(() => _loadingMore = true);
    final result = await Get.find<GymRepository>().history(before: _cursor);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      result.fold((_) {}, (page) {
        _cursor = page.nextCursor;
        _state = Ready([...shown, ...page.workouts]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.gymHistory)),
      body: switch (_state) {
        Loading<List<WorkoutSummary>>() => const LoadingView(lines: 6),
        Empty<List<WorkoutSummary>>() => EmptyView(
          title: l.gymStatsEmptyTitle,
          body: l.gymStatsEmptyBody,
        ),
        Failed<List<WorkoutSummary>>(:final failure) => FailedView(
          failure: failure,
          onRetry: _load,
          retryLabel: l.accountRetry,
        ),
        Ready<List<WorkoutSummary>>(:final data) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.xxl,
            ),
            children: [
              for (final w in data)
                WorkoutTile(
                  workout: w,
                  onTap: () async {
                    await WorkoutDetailPage.open(w.id);
                    if (mounted) await _load();
                  },
                ),
              if (_cursor != null)
                Center(
                  child: TextButton(
                    onPressed: _loadingMore ? null : () => _more(data),
                    child: Text(l.gymLoadMore),
                  ),
                ),
            ],
          ),
        ),
      },
    );
  }
}
