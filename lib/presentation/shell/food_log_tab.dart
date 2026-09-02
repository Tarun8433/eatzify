import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/food_image.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// docs/09 §5 slots, in the order a day runs.
const _slots = ['breakfast', 'mid_morning', 'lunch', 'snack', 'evening', 'dinner', 'bedtime'];

/// The food tab of the `+` sheet: search → pick a measure → add.
///
/// CLAUDE.md rule 2: nothing here multiplies grams by nutrition. The client sends the measure and
/// the count; the server scales and stores. That keeps one implementation of the arithmetic.
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
  /// first four rows, and the list below starts at the fifth, so nothing appears twice and the
  /// shelf costs no bandwidth.
  static const _quickAddCount = 4;

  final _results = <Food>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  /// The category the rows on screen belong to; null is the whole table. Sent to the server as a
  /// `suitableFor` preference — the app never filters rows it happens to be holding, which would
  /// only ever filter the pages already fetched.
  FoodPreference? _preference;

  /// The query the rows on screen belong to. A response for a query the user has since changed is
  /// dropped rather than shown — the alternative is results for "pan" landing under "paneer".
  String _shownQuery = '';

  @override
  void initState() {
    super.initState();
    // The tab opens on the table rather than on an empty box with a hint in it (D-121). Someone
    // opening "add food" has already decided to add food; a blank screen asks them to guess what
    // the app knows about before it will show them anything.
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

  /// The first page for [value], replacing whatever is on screen.
  Future<void> _load(String value) async {
    final preference = _preference;
    setState(() {
      _loading = true;
      _error = null;
      _shownQuery = value;
    });

    final result = await Get.find<DiaryRepository>().searchFoods(
      value,
      limit: _pageSize,
      suitableFor: preference?.wire,
    );
    // Three guards, not one: the widget may be gone, or the user may have typed on — or changed
    // the category — while this was in flight. Only the response for what is asked for NOW may be
    // shown; anything else puts non-vegetarian rows under a vegetarian heading.
    if (!mounted || value != _shownQuery || preference != _preference) return;

    setState(() {
      _loading = false;
      result.fold((failure) => _error = failure.userMessage, (foods) {
        _results
          ..clear()
          ..addAll(foods);
        // A short page is the last page. Asking for one more to be told it is empty is a round
        // trip that buys nothing.
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
    final result = await Get.find<DiaryRepository>().searchFoods(
      query,
      limit: _pageSize,
      offset: _results.length,
      suitableFor: preference?.wire,
    );
    if (!mounted || query != _shownQuery || preference != _preference) return;

    setState(() {
      _loadingMore = false;
      result.fold(
        // A failed page is not a failed screen: the rows already loaded stay, and the message sits
        // under them rather than replacing them.
        (failure) => _error = failure.userMessage,
        (foods) {
          _results.addAll(foods);
          _exhausted = foods.length < _pageSize;
        },
      );
    });
  }

  /// A different category is a different list: the rows are replaced from the first page rather
  /// than appended to, and the scroll goes back to the top so the user is not left mid-way down a
  /// list they have not seen the start of.
  void _onCategoryChanged(FoodPreference? preference) {
    if (preference == _preference) return;
    setState(() => _preference = preference);
    unawaited(_load(_query.text));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _add(Food food) async {
    final choice = await showModalBottomSheet<({String slot, String? measure, double count})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PortionSheet(food: food),
    );
    if (choice == null || !mounted) return;

    final result = await Get.find<DiaryRepository>().logFood(
      slot: choice.slot,
      foodId: food.id,
      measure: choice.measure,
      measureCount: choice.measure == null ? null : choice.count,
      quantityG: choice.measure == null ? choice.count : null,
    );
    if (!mounted) return;

    result.fold((failure) => setState(() => _error = failure.userMessage), (_) {
      // The Home tab holds today's totals, so it must re-read rather than guess at the new sum.
      if (Get.isRegistered<HomeController>()) Get.find<HomeController>().load();
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Browsing only. A search is a list of answers, and a shelf of unrelated foods above it is in
    // the way of the one the user asked for.
    final quick = _shownQuery.isEmpty
        ? _results.take(_quickAddCount).toList(growable: false)
        : const <Food>[];
    final rows = _results.skip(quick.length).toList(growable: false);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quick.isNotEmpty) ...[
          _SectionHeading(
            title: l.logQuickAdds,
            subtitle: l.logQuickAddsSubtitle,
            icon: Icons.bolt,
          ),
          const SizedBox(height: AppSpacing.md),
          _QuickAdds(foods: quick, onAdd: _add),
          const SizedBox(height: AppSpacing.xl),
        ],
        // Says which list this is. Without it the browse case looks like a search that ran
        // itself, and the user cannot tell whether they are seeing everything or a guess.
        _SectionHeading(
          title: _shownQuery.isEmpty ? l.logFoodsAll : l.logFoodsMatching(_shownQuery),
          subtitle: l.logFoodsSubtitle,
          icon: Icons.eco,
          // Browsing: the category filter. Searching: the way back out of the search. One slot,
          // because two pills side by side in a heading is a toolbar, and this is a heading.
          action: _shownQuery.isEmpty
              ? _CategoryPill(selected: _preference, onChanged: _onCategoryChanged)
              : _ViewAllButton(
                  label: l.logFoodsViewAll,
                  onTap: () {
                    _query.clear();
                    unawaited(_load(''));
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                ),
        ),
        // Under the heading rather than instead of the screen: the search box and what was
        // searched for stay put, which is what the user needs in order to change it.
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Text(l.logSearchEmpty, style: theme.textTheme.bodySmall),
          ),
      ],
    );

    return Padding(
      // docs/DESIGN-SYSTEM §5 puts a SCREEN on an `xl` gutter; this is a sheet, already inset from
      // the page, so the list runs on `lg` — at 24 the rows read as a narrow column where the
      // reference's run a step wider.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The field sits ON something (D-123). The sheet is white and the app's fields are
          // filled white, so the box had no edge at all — an icon and a grey hint floating on the
          // page. A pill with a hairline and a shadow is the shape a search box has, and the
          // shadow is what separates two whites.
          _SearchSurface(
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
                // Only while there is something to clear. An always-on × on an empty field is a
                // control that does nothing most of the time it is visible.
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
          const SizedBox(height: AppSpacing.xl),
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      // `primary: true` is what iOS's tap-the-clock-to-scroll-up looks for, and the
                      // framework refuses it alongside a `controller:` argument — so the controller
                      // is handed down as the PRIMARY one instead of passed in. That keeps the
                      // prefetch listener and gets the gesture, which a supplied controller silently
                      // loses.
                      primary: true,
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      // Row zero is the headings and the quick-add shelf: they scroll with what
                      // they name rather than sitting above it as a fixed band.
                      // No trailing spinner when there is nothing to page: an empty result or a
                      // failed first page is not "more is coming", and a spinner that never ends
                      // is how a screen says the opposite of what it means.
                      itemCount: 1 + rows.length + (_exhausted || rows.isEmpty ? 0 : 1),
                      separatorBuilder: (_, i) =>
                          SizedBox(height: i == 0 ? AppSpacing.md : AppSpacing.xs),
                      itemBuilder: (_, i) {
                        if (i == 0) return header;
                        final index = i - 1;
                        // One past the rows, for the spinner that says another page is coming.
                        if (index == rows.length) {
                          return const Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _FoodRow(food: rows[index], onAdd: () => _add(rows[index]));
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The white pill the search field sits in.
///
/// Separate from the field because `inputDecorationTheme` is the app's ANSWER field — filled
/// white, tile radius, hairline outline — and on a white sheet that is invisible. This one carries
/// its own edge and its own shadow.
class _SearchSurface extends StatelessWidget {
  const _SearchSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: child,
    );
  }
}

/// A section's title, what it is for, and the one thing that can be done to it.
///
/// Two sections use it — the quick-add shelf and the list — and they must not drift: a screen
/// whose two headings size their type differently reads as two screens stapled together.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });

  final String title;
  final String subtitle;

  /// Decoration beside the title. Excluded from semantics — the words carry the meaning.
  final IconData icon;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ExcludeSemantics(
                    child: Icon(icon, size: AppSpacing.lg, color: theme.colorScheme.secondary),
                  ),
                ],
              ),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// The shelf of tiles above the list: the foods a user is most likely to be here for, one tap
/// from the portion sheet.
///
/// A row of four rather than a horizontal scroller. Four is what fits a phone's width at a
/// readable tile size, and a scroller that only ever holds four is a gesture that leads nowhere.
class _QuickAdds extends StatelessWidget {
  const _QuickAdds({required this.foods, required this.onAdd});

  final List<Food> foods;
  final void Function(Food) onAdd;

  @override
  Widget build(BuildContext context) {
    // The tiles divide the width they are given rather than carrying a fixed one: the same four
    // have to sit on a 320 pt phone and on a tablet's sheet.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = AppSpacing.sm * (foods.length - 1);
        final tile = (constraints.maxWidth - gaps) / foods.length;

        return IntrinsicHeight(
          child: Row(
            // Equal-height tiles: a two-line name must not make one card taller than its
            // neighbours, which is what turns a shelf into a staircase.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final food in foods) ...[
                if (food != foods.first) const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: tile,
                  child: _QuickAddTile(
                    food: food,
                    // The tile's own width, less its padding: a `LayoutBuilder` inside the tile
                    // would read it for itself, but nothing can measure through one — and equal
                    // heights across the shelf need exactly that measurement.
                    imageWidth: tile - AppSpacing.sm * 2,
                    onAdd: () => onAdd(food),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One tile on the shelf: the photograph, the name, what it costs per 100 g.
class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({required this.food, required this.imageWidth, required this.onAdd});

  final Food food;

  /// Handed down rather than measured — see the call site.
  final double imageWidth;

  final VoidCallback onAdd;

  /// The `+` badge on the photograph. Decoration — the whole tile adds — so it is not held to the
  /// 48 pt interactive minimum.
  static const _badge = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onAdd,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: FoodImage(
                  url: food.imageUrl,
                  attribution: food.imageAttribution,
                  size: imageWidth,
                  height: imageWidth * 0.8,
                ),
              ),
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: ExcludeSemantics(
                  child: Container(
                    height: _badge,
                    width: _badge,
                    decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                    child: Icon(Icons.add, size: AppSpacing.lg, color: scheme.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            food.name,
            // Two lines then an ellipsis: "Amaranth leaves (cooked)" in a quarter of a phone
            // is three lines of type, and a tile that grows to fit it drags the whole shelf
            // down with it.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${food.kcalPer100g.round()} kcal / 100 g',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The category filter: every food, or the ones that suit one food preference (docs/03 §2).
///
/// A menu rather than a row of chips. Five preferences plus "all" is six controls, and six chips
/// in a heading is a second navigation bar; the reference draws one pill that says what is showing
/// now and opens the rest.
///
/// The preferences are the app's OWN vocabulary — the same enum and the same l10n labels
/// onboarding asks the question with, so a user who chose "Eggetarian" there reads the same word
/// here (CLAUDE.md rule 4: never a raw enum).
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.selected, required this.onChanged});

  final FoodPreference? selected;
  final ValueChanged<FoodPreference?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = selected?.label(l) ?? l.logFoodsCategoryAll;

    return PopupMenuButton<FoodPreference?>(
      tooltip: l.logFoodsCategory,
      initialValue: selected,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        // Null first: "all" is where the list starts and where a user backs out to.
        PopupMenuItem<FoodPreference?>(child: Text(l.logFoodsCategoryAll)),
        for (final preference in FoodPreference.values)
          PopupMenuItem<FoodPreference?>(value: preference, child: Text(preference.label(l))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          // Filled once it is doing something: a filter that is ON must not look like a filter
          // that is off, and the label alone is a word most eyes skip.
          color: selected == null
              ? Colors.transparent
              : scheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            Icon(Icons.expand_more, size: AppSpacing.xl, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// The way back to the whole table from a search. A pill, because it is the one thing in the
/// heading that can be pressed and it must not read as another caption.
class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
              Icon(Icons.chevron_right, size: AppSpacing.xl, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One food: its photograph, its name, what it costs per 100 g, and the way to add it.
///
/// A card rather than a `ListTile` — a list of 280 rows on one flat surface is a wall, and the
/// separation is what lets the eye stop on one. The whole card adds; the `+` is where the eye
/// goes, not the only place a finger may land.
class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onAdd});

  final Food food;
  final VoidCallback onAdd;

  /// The photograph's width; its height is a landscape crop of that, as the reference draws it.
  /// Sized so a row is the reference's ~60 pt band rather than the 80 pt one a 72 pt square forced
  /// — nine rows on a phone is what makes the list read as a table instead of as a stack of cards.
  static const _thumb = 64.0;
  static const _thumbHeight = _thumb * 0.72;

  /// The `+` disc. Decoration, not a target (the whole card taps), so it follows the reference's
  /// proportion rather than the 48 pt minimum.
  static const _addDisc = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onAdd,
      // Not equal on all four sides: the photograph sits almost on the card's edge, and what is
      // left goes to the right of the `+` so the disc is not jammed against the corner.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          // A picture per row, and a placeholder of the same size when there is none — 14 of the
          // 281 foods have no photograph, and a gap reads as a broken row.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            // Bigger than the 48 default: on this screen the photograph is how a dish is
            // recognised — "aloo sabzi" and "aloo gobhi" are one word apart and two glances apart.
            child: FoodImage(
              url: food.imageUrl,
              attribution: food.imageAttribution,
              size: _thumb,
              height: _thumbHeight,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // One step down from the section heading. At heading size every row shouted as
                  // loudly as the title above them, which is what made the list read heavier than
                  // the reference's.
                  food.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('${food.kcalPer100g.round()} kcal / 100 g', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ExcludeSemantics(
            child: Container(
              height: _addDisc,
              width: _addDisc,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick a slot and an amount. The household measure is offered first (docs/03 §units); grams are
/// the fallback for a food that has none.
class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.food});

  final Food food;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  late String _slot = 'lunch';
  late HouseholdMeasure? _measure = widget.food.defaultMeasure;
  double _count = 1;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final measures = widget.food.measures;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.food.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Text(l.logSlot, style: theme.textTheme.bodySmall),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final slot in _slots)
                ChoiceChip(
                  label: Text(_slotLabel(l, slot)),
                  selected: _slot == slot,
                  onSelected: (_) => setState(() => _slot = slot),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l.logHowMuch, style: theme.textTheme.bodySmall),
          if (measures.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in measures)
                  ChoiceChip(
                    label: Text('${m.label} · ${m.grams.round()} g'),
                    selected: _measure?.label == m.label,
                    onSelected: (_) => setState(() => _measure = m),
                  ),
              ],
            ),
          Row(
            children: [
              IconButton(
                // An icon-only button announces as just "button" without this.
                tooltip: l.logDecrease,
                onPressed: _count > 0.5 ? () => setState(() => _count -= 0.5) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                _measure == null ? '${_count.round()} g' : '$_count × ${_measure!.label}',
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                tooltip: l.logIncrease,
                onPressed: () => setState(() => _count += 0.5),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop((slot: _slot, measure: _measure?.label, count: _count)),
              child: Text(l.logAdd),
            ),
          ),
        ],
      ),
    );
  }

  /// CLAUDE.md rule 4: a slot is an enum on the wire and l10n on screen.
  String _slotLabel(AppLocalizations l, String slot) => switch (slot) {
    'breakfast' => l.slotBreakfast,
    'mid_morning' => l.slotMidMorning,
    'lunch' => l.slotLunch,
    'snack' => l.slotSnack,
    'evening' => l.slotEvening,
    'dinner' => l.slotDinner,
    _ => l.slotBedtime,
  };
}
