import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/ads/rewarded_ad_gate.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/food_list_parts.dart';
import 'package:health_pro/presentation/shell/food_log/food_scan_flow.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart';
import 'package:health_pro/presentation/shell/food_log/scan_result_sheet.dart';
import 'package:image_picker/image_picker.dart';

/// The food tab of the `+` sheet: search or browse → pick a portion → add.
///
/// CLAUDE.md rule 2: nothing here multiplies grams by nutrition. The client sends the measure and
/// the count; the server scales, previews and stores. That keeps one implementation of the
/// arithmetic.
class FoodLogTab extends StatefulWidget {
  const FoodLogTab({super.key});

  @override
  State<FoodLogTab> createState() => _FoodLogTabState();
}

class _FoodLogTabState extends State<FoodLogTab> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// One page. Twenty rows is what fits a scroll and a half with a photograph each, and it is what
  /// the server's default `limit` agrees to (D-121).
  static const _pageSize = 20;

  /// How close to the end a scroll has to get before the next page is asked for. A page's worth of
  /// pixels, so the rows are already there by the time the user reaches where they would have been.
  static const _prefetchExtent = 600.0;

  /// How many of the browse page's foods are drawn as tiles above the list (the reference's
  /// "Quick adds" shelf). They are the SAME page, not a second request: the four tiles are the
  /// first four rows, and the list below starts at the fifth, so nothing appears twice.
  static const _quickAddCount = 4;

  final _results = <Food>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  /// The diet the rows on screen suit; null is the whole table. Sent to the server as a
  /// `suitableFor` preference — the app never filters rows it happens to be holding, which would
  /// only ever filter the pages already fetched.
  FoodPreference? _preference;

  /// The food-group chip the rows belong to (D-238). Server-filtered, for the same reason.
  FoodGroupChip _group = FoodGroupChip.all;

  /// The query the rows on screen belong to. A response for a query the user has since changed is
  /// dropped rather than shown — the alternative is results for "pan" landing under "paneer".
  String _shownQuery = '';

  @override
  void initState() {
    super.initState();
    // The tab opens on the table rather than on an empty box with a hint in it (D-121).
    unawaited(_load(''));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _query.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining <= _prefetchExtent) unawaited(_loadMore());
  }

  void _onQueryChanged(String value) {
    // Debounced so a five-letter word is one request, not five — docs/18 treats bandwidth as a
    // real cost on Indian data plans.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_load(value)));
  }

  /// Whether a response still belongs to what is on screen. The widget may be gone, or the user may
  /// have typed on — or changed a filter — while it was in flight; anything else puts non-vegetarian
  /// rows under a vegetarian heading.
  bool _stillAsked(String query, FoodPreference? preference, FoodGroupChip group) =>
      mounted && query == _shownQuery && preference == _preference && group == _group;

  /// The first page for [value], replacing whatever is on screen.
  Future<void> _load(String value) async {
    final preference = _preference;
    final group = _group;
    setState(() {
      _loading = true;
      _error = null;
      _shownQuery = value;
    });

    final result = await Get.find<DiaryRepository>().searchFoods(
      value,
      limit: _pageSize,
      suitableFor: preference?.wire,
      groups: group.groups,
    );
    if (!_stillAsked(value, preference, group)) return;

    setState(() {
      _loading = false;
      result.fold((failure) => _error = failure.userMessage, (foods) {
        _results
          ..clear()
          ..addAll(foods);
        // A short page is the last page.
        _exhausted = foods.length < _pageSize;
      });
    });
  }

  /// The next page, appended.
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _exhausted) return;
    setState(() => _loadingMore = true);

    final query = _shownQuery;
    final preference = _preference;
    final group = _group;
    final result = await Get.find<DiaryRepository>().searchFoods(
      query,
      limit: _pageSize,
      offset: _results.length,
      suitableFor: preference?.wire,
      groups: group.groups,
    );
    if (!_stillAsked(query, preference, group)) return;

    setState(() {
      _loadingMore = false;
      result.fold(
        // A failed page is not a failed screen: the rows already loaded stay.
        (failure) => _error = failure.userMessage,
        (foods) {
          _results.addAll(foods);
          _exhausted = foods.length < _pageSize;
        },
      );
    });
  }

  /// A different filter is a different list: replaced from the first page, scrolled to the top.
  void _refilter(VoidCallback change) {
    setState(change);
    unawaited(_load(_query.text));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _add(Food food) async {
    final choice = await PortionSheet.show(context, food);
    if (choice == null || !mounted) return;
    await _log(food, choice);
  }

  /// D-240. A confirmed scan becomes ONE entry: the server sums the kept items of its own stored
  /// estimate and attaches the photo. "No" or not recognised lands back on search.
  Future<void> _scan() async {
    final outcome = await FoodScanFlow(
      scans: Get.find<ScanRepository>(),
      ads: Get.isRegistered<RewardedAdGate>() ? Get.find<RewardedAdGate>() : null,
      picker: Get.isRegistered<ImagePicker>() ? Get.find<ImagePicker>() : null,
    ).run(context);
    if (!mounted) return;

    switch (outcome) {
      case ScanConfirmed(:final scanId, :final slot, :final keep):
        final result = await Get.find<ScanRepository>().confirm(scanId, slot: slot, keep: keep);
        if (mounted) _logged(result, slot);
      case ScanSearchInstead(:final query):
        _query.text = query ?? '';
        unawaited(_load(_query.text));
      case null:
        break;
    }
  }

  Future<void> _log(Food food, PortionChoice choice) async {
    final result = await Get.find<DiaryRepository>().logFood(
      slot: choice.slot,
      foodId: food.id,
      measure: choice.measure,
      measureCount: choice.measure == null ? null : choice.count,
      quantityG: choice.measure == null ? choice.count : null,
    );
    if (mounted) _logged(result, choice.slot);
  }

  /// A new entry, however it was made: Home re-reads, the sheet closes, and "Added · Undo" says so.
  void _logged(Either<Failure, LogEntry> result, String slot) {
    final l = AppLocalizations.of(context);
    final repo = Get.find<DiaryRepository>();
    result.fold((failure) => setState(() => _error = failure.userMessage), (entry) {
      _reloadHome();
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
              final undone = await repo.remove(entry.id);
              undone.fold(
                (failure) => messenger.showSnackBar(SnackBar(content: Text(failure.userMessage))),
                (_) => _reloadHome(),
              );
            },
          ),
        ),
      );
    });
  }

  /// The Home tab holds today's totals, so it must re-read rather than guess at the new sum.
  void _reloadHome() {
    if (Get.isRegistered<HomeController>()) unawaited(Get.find<HomeController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Browsing only, and only the unfiltered table: a search or a category is a list of answers,
    // and a shelf of unrelated foods above it is in the way of the one the user asked for.
    final browsing = _shownQuery.isEmpty && _group == FoodGroupChip.all;
    final quick = browsing ? _results.take(_quickAddCount).toList(growable: false) : const <Food>[];
    final rows = _results.skip(quick.length).toList(growable: false);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quick.isNotEmpty) ...[
          SectionHeading(title: l.logQuickAdds, subtitle: l.logQuickAddsSubtitle, icon: Icons.bolt),
          const SizedBox(height: AppSpacing.md),
          QuickAddShelf(foods: quick, onAdd: _add),
          const SizedBox(height: AppSpacing.xl),
        ],
        // Says which list this is. Without it the browse case looks like a search that ran itself.
        SectionHeading(
          title: _shownQuery.isEmpty ? l.logFoodsAll : l.logFoodsMatching(_shownQuery),
          subtitle: l.logFoodsSubtitle,
          icon: Icons.eco,
          // Browsing: the diet filter. Searching: the way back out of the search.
          action: _shownQuery.isEmpty
              ? CategoryPill(
                  selected: _preference,
                  onChanged: (p) {
                    if (p != _preference) _refilter(() => _preference = p);
                  },
                )
              : ViewAllButton(
                  label: l.logFoodsViewAll,
                  onTap: () {
                    _query.clear();
                    unawaited(_load(''));
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        FoodGroupChips(
          selected: _group,
          onChanged: (g) {
            if (g != _group) _refilter(() => _group = g);
          },
        ),
        // Under the heading rather than instead of the screen: the search box and what was
        // searched for stay put, which is what the user needs in order to change it.
        if (_results.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Text(l.logSearchEmpty, style: theme.textTheme.bodySmall),
          ),
      ],
    );

    return Padding(
      // A sheet is already inset from the page, so the list runs on `lg`, not a screen's `xl`.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
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
                      suffixIcon: _shownQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: l.commonCancel,
                              onPressed: () {
                                _query.clear();
                                unawaited(_load(''));
                              },
                            ),
                    ),
                    onChanged: _onQueryChanged,
                  ),
                ),
              ),
              // Only where scanning is wired up; whether this person may scan is the server's call,
              // asked when it is tapped (D-238).
              if (Get.isRegistered<ScanRepository>()) ...[
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                _error!,
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
                itemCount: 1 + (_loading ? 1 : rows.length + (_exhausted || rows.isEmpty ? 0 : 1)),
                separatorBuilder: (_, i) =>
                    SizedBox(height: i == 0 ? AppSpacing.md : AppSpacing.sm),
                itemBuilder: (_, i) {
                  if (i == 0) return header;
                  final index = i - 1;
                  // The first page loading, or one past the rows for the next page coming.
                  if (_loading || index == rows.length) {
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
      ),
    );
  }
}
