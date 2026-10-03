import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/ads/rewarded_ad_gate.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/food_list_parts.dart';
import 'package:health_pro/presentation/shell/food_log/food_log_controller.dart';
import 'package:health_pro/presentation/shell/food_log/food_scan_flow.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart';
import 'package:health_pro/presentation/shell/food_log/scan_result_sheet.dart';
import 'package:image_picker/image_picker.dart';

/// The food tab of the `+` sheet: search or browse → pick a portion → add. Or scan a plate (D-240).
///
/// The rows, the paging, the filters and every request live in [FoodLogController]; what is left
/// here is the text field, the scroll, the sheets and the snackbar.
class FoodLogTab extends StatefulWidget {
  const FoodLogTab({super.key});

  @override
  State<FoodLogTab> createState() => _FoodLogTabState();
}

class _FoodLogTabState extends State<FoodLogTab> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// How close to the end a scroll has to get before the next page is asked for. A page's worth of
  /// pixels, so the rows are already there by the time the user reaches where they would have been.
  static const _prefetchExtent = 600.0;

  /// Put here, and deleted with the tab: the `+` sheet is a modal route with no GetPage to hang a
  /// binding on, and a reopened sheet should start on a fresh first page rather than yesterday's.
  late final FoodLogController _c = Get.put(
    FoodLogController(
      diary: Get.find<DiaryRepository>(),
      scans: Get.isRegistered<ScanRepository>() ? Get.find<ScanRepository>() : null,
    ),
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _query.dispose();
    Get.delete<FoodLogController>();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining <= _prefetchExtent) unawaited(_c.loadMore());
  }

  void _onQueryChanged(String value) {
    // Debounced so a five-letter word is one request, not five — docs/18 treats bandwidth as a
    // real cost on Indian data plans.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_c.load(value)));
  }

  /// A different filter is a different list: from the first page again, scrolled back to the top.
  void _refilter(Future<void> Function() change) {
    unawaited(change());
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _search(String query) {
    _query.text = query;
    unawaited(_c.load(query));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _add(Food food) async {
    final choice = await PortionSheet.show(context, food);
    if (choice == null || !mounted) return;
    final result = await _c.log(food, choice);
    if (mounted) _logged(result, choice.slot);
  }

  /// D-240. A confirmed scan becomes ONE entry: the server sums the kept items of its own stored
  /// estimate and attaches the photo. "No" or not recognised lands back on search.
  Future<void> _scan() async {
    _c.error.value = null;
    final outcome = await FoodScanFlow(
      scans: _c.scans!,
      // Said on this sheet's own error line — a snackbar would sit hidden behind the sheet.
      onMessage: (message) {
        if (mounted) _c.error.value = message;
      },
      ads: Get.isRegistered<RewardedAdGate>() ? Get.find<RewardedAdGate>() : null,
      picker: Get.isRegistered<ImagePicker>() ? Get.find<ImagePicker>() : null,
    ).run(context);
    if (!mounted) return;

    switch (outcome) {
      case ScanConfirmed(:final scanId, :final slot, :final keep):
        final result = await _c.confirmScan(scanId, slot: slot, keep: keep);
        if (mounted) _logged(result, slot);
      case ScanSearchInstead(:final query):
        _search(query ?? '');
      case null:
        break;
    }
  }

  /// A new entry, however it was made: Home re-reads, the sheet closes, and "Added · Undo" says so.
  void _logged(Either<Failure, LogEntry> result, String slot) {
    final l = AppLocalizations.of(context);
    result.fold((failure) => _c.error.value = failure.userMessage, (entry) {
      _c.reloadHome();
      // Captured before the sheet closes: the snackbar belongs to the page underneath.
      final messenger = ScaffoldMessenger.maybeOf(context);
      // maybePop: the tab lives in the `+` sheet, which closes; hosted anywhere else, nothing does.
      unawaited(Navigator.of(context).maybePop());
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l.logAddedTo(slotLabel(l, slot))),
          action: SnackBarAction(
            label: l.logUndo,
            onPressed: () async {
              final undone = await _c.undo(entry.id);
              undone.fold(
                (failure) => messenger.showSnackBar(SnackBar(content: Text(failure.userMessage))),
                (_) => _c.reloadHome(),
              );
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      // A sheet is already inset from the page, so the list runs on `lg`, not a screen's `xl`.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Obx(() {
        final searching = _c.shownQuery.value.isNotEmpty;
        final quick = _c.quickAdds;
        final rows = _c.rows;
        final loading = _c.loading.value;
        final error = _c.error.value;

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quick.isNotEmpty) ...[
              SectionHeading(
                title: l.logQuickAdds,
                subtitle: l.logQuickAddsSubtitle,
                icon: Icons.bolt,
              ),
              const SizedBox(height: AppSpacing.md),
              QuickAddShelf(foods: quick, onAdd: _add),
              const SizedBox(height: AppSpacing.xl),
            ],
            // Says which list this is. Without it the browse case looks like a search that ran
            // itself, and the user cannot tell whether they are seeing everything or a guess.
            SectionHeading(
              title: searching ? l.logFoodsMatching(_c.shownQuery.value) : l.logFoodsAll,
              subtitle: l.logFoodsSubtitle,
              icon: Icons.eco,
              // Browsing: the diet filter. Searching: the way back out of the search.
              action: searching
                  ? ViewAllButton(label: l.logFoodsViewAll, onTap: () => _search(''))
                  : CategoryPill(
                      selected: _c.preference.value,
                      onChanged: (p) => _refilter(() => _c.setDiet(p, query: _query.text)),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            FoodGroupChips(
              selected: _c.group.value,
              onChanged: (g) => _refilter(() => _c.setGroup(g, query: _query.text)),
            ),
            // Under the heading rather than instead of the screen: the search box and what was
            // searched for stay put, which is what the user needs in order to change it.
            if (rows.isEmpty && quick.isEmpty && !loading)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Text(l.logSearchEmpty, style: theme.textTheme.bodySmall),
              ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  // The field sits ON something (D-123): on a white sheet a white field has no edge.
                  child: SearchSurface(
                    child: TextField(
                      controller: _query,
                      decoration: InputDecoration(
                        hintText: l.logSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        // Only while there is something to clear.
                        suffixIcon: searching
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: l.commonCancel,
                                onPressed: () => _search(''),
                              )
                            : null,
                      ),
                      onChanged: _onQueryChanged,
                    ),
                  ),
                ),
                // Only where scanning is wired up; whether this person may scan is the server's
                // call, asked when it is tapped (D-238).
                if (_c.scans != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(l.scanFood),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSpacing.minTouchTarget),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Expanded(
              child: PrimaryScrollController(
                controller: _scroll,
                child: ListView.separated(
                  // `primary: true` is what iOS's tap-the-clock-to-scroll-up looks for, and the
                  // framework refuses it alongside a `controller:` argument — so the controller is
                  // handed down as the PRIMARY one instead.
                  primary: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  // Row zero is the headings, the shelf and the chips: they scroll with what they
                  // name. While the first page loads the header stays (so the chips can still be
                  // changed) and the spinner takes the rows' place.
                  itemCount:
                      1 +
                      (loading ? 1 : rows.length + (_c.exhausted.value || rows.isEmpty ? 0 : 1)),
                  separatorBuilder: (_, i) =>
                      SizedBox(height: i == 0 ? AppSpacing.md : AppSpacing.sm),
                  itemBuilder: (_, i) {
                    if (i == 0) return header;
                    final index = i - 1;
                    // The first page loading, or one past the rows for the next page coming.
                    if (loading || index == rows.length) {
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return FoodRow(food: rows[index], onAdd: () => _add(rows[index]));
                  },
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
