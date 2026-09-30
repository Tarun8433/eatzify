import 'dart:async';

import 'package:dartz/dartz.dart' show Either, Unit;
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/shell/food_log/food_list_parts.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart';

/// What the food tab knows and asks for: the rows on screen, which page they came from, which
/// filters they belong to, and every call the tab makes.
///
/// CLAUDE.md rule 2 keeps this out of the widget — and nothing here multiplies grams by nutrition
/// either. The client sends the measure and the count; the server scales, previews and stores.
class FoodLogController extends GetxController {
  FoodLogController({required this.diary, this.scans});

  final DiaryRepository diary;

  /// Null where meal scanning is not wired up — the tab then draws no Scan button (D-238).
  final ScanRepository? scans;

  /// One page. Twenty rows is what fits a scroll and a half with a photograph each, and it is what
  /// the server's default `limit` agrees to (D-121).
  static const pageSize = 20;

  /// How many of the browse page's foods are drawn as tiles above the list (the reference's
  /// "Quick adds" shelf). They are the SAME page, not a second request: the four tiles are the
  /// first four rows, and the list below starts at the fifth, so nothing appears twice.
  static const quickAddCount = 4;

  /// A plain observable list rather than `RxList`: reading `.value` is how the tab's `Obx`
  /// subscribes, and every change replaces the list instead of mutating it.
  final results = Rx<List<Food>>(const []);

  /// True from construction: the first page is asked for in [onInit], so the tab never paints an
  /// empty list it is about to replace.
  final loading = true.obs;
  final exhausted = false.obs;
  final error = Rxn<String>();

  /// The diet the rows on screen suit; null is the whole table. Sent to the server as a
  /// `suitableFor` preference — the app never filters rows it happens to be holding, which would
  /// only ever filter the pages already fetched.
  final preference = Rxn<FoodPreference>();

  /// The food-group chip the rows belong to (D-238). Server-filtered, for the same reason.
  final group = FoodGroupChip.all.obs;

  /// The query the rows on screen belong to. A response for a query the user has since changed is
  /// dropped rather than shown — the alternative is results for "pan" landing under "paneer".
  final shownQuery = ''.obs;

  bool _loadingMore = false;

  @override
  void onInit() {
    super.onInit();
    // The tab opens on the table rather than on an empty box with a hint in it (D-121).
    unawaited(load(''));
  }

  /// Browsing is the unfiltered table: a search or a category is a list of answers, and a shelf of
  /// unrelated foods above it is in the way of the one the user asked for.
  bool get browsing => shownQuery.value.isEmpty && group.value == FoodGroupChip.all;

  List<Food> get quickAdds =>
      browsing ? results.value.take(quickAddCount).toList(growable: false) : const <Food>[];

  List<Food> get rows => results.value.skip(quickAdds.length).toList(growable: false);

  /// Whether a response still belongs to what is on screen: the user may have typed on — or changed
  /// a filter — while it was in flight, and anything else puts non-vegetarian rows under a
  /// vegetarian heading.
  bool _stillAsked(String query, FoodPreference? diet, FoodGroupChip chip) =>
      query == shownQuery.value && diet == preference.value && chip == group.value;

  /// The first page for [query], replacing whatever is on screen.
  Future<void> load(String query) async {
    final diet = preference.value;
    final chip = group.value;
    shownQuery.value = query;
    error.value = null;
    loading.value = true;

    final result = await diary.searchFoods(
      query,
      limit: pageSize,
      suitableFor: diet?.wire,
      groups: chip.groups,
    );
    if (!_stillAsked(query, diet, chip)) return;

    loading.value = false;
    result.fold((failure) => error.value = failure.userMessage, (foods) {
      results.value = foods;
      // A short page is the last page.
      exhausted.value = foods.length < pageSize;
    });
  }

  /// The next page, appended.
  Future<void> loadMore() async {
    if (loading.value || _loadingMore || exhausted.value) return;
    _loadingMore = true;

    final query = shownQuery.value;
    final diet = preference.value;
    final chip = group.value;
    final result = await diary.searchFoods(
      query,
      limit: pageSize,
      offset: results.value.length,
      suitableFor: diet?.wire,
      groups: chip.groups,
    );
    if (!_stillAsked(query, diet, chip)) return;

    _loadingMore = false;
    result.fold(
      // A failed page is not a failed screen: the rows already loaded stay.
      (failure) => error.value = failure.userMessage,
      (foods) {
        results.value = [...results.value, ...foods];
        exhausted.value = foods.length < pageSize;
      },
    );
  }

  /// A different diet is a different list: replaced from the first page. [query] is what is in the
  /// search box now, which is not always what was last loaded.
  Future<void> setDiet(FoodPreference? diet, {required String query}) async {
    if (diet == preference.value) return;
    preference.value = diet;
    await load(query);
  }

  Future<void> setGroup(FoodGroupChip chip, {required String query}) async {
    if (chip == group.value) return;
    group.value = chip;
    await load(query);
  }

  /// docs/03 §units: the client sends the measure and the count the user chose, never grams it
  /// worked out itself.
  Future<Either<Failure, LogEntry>> log(Food food, PortionChoice choice) => diary.logFood(
    slot: choice.slot,
    foodId: food.id,
    measure: choice.measure,
    measureCount: choice.measure == null ? null : choice.count,
    quantityG: choice.measure == null ? choice.count : null,
  );

  /// D-240. "Yes" on a scan: the server sums the kept items of its own stored estimate and attaches
  /// the photo. Which items, never numbers.
  Future<Either<Failure, LogEntry>> confirmScan(
    int scanId, {
    required String slot,
    required List<int> keep,
  }) => scans!.confirm(scanId, slot: slot, keep: keep);

  Future<Either<Failure, Unit>> undo(String entryId) => diary.remove(entryId);

  /// The Home tab holds today's totals, so it must re-read rather than guess at the new sum.
  void reloadHome() {
    if (Get.isRegistered<HomeController>()) unawaited(Get.find<HomeController>().load());
  }
}
