import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/plan.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';

/// docs/09 §4.2 behind the four states (CLAUDE.md rule 6).
class PlanController extends GetxController {
  PlanController({required this.plans});

  final PlanRepository plans;

  final state = Rx<ViewState<Plan>>(const Loading());
  final generating = false.obs;

  /// The server's `user_message`, verbatim — including the docs/05 §7 referral copy when a gate
  /// blocks the plan (rule 7).
  final error = RxnString();

  /// Foods the user may pick from (D-82). Deliberately NOT part of [state]: the plan's targets are
  /// what this screen is about, and an options list that failed to load must not blank a plan that
  /// arrived perfectly well.
  final options = <String, List<FoodOption>>{}.obs;
  final loadingOptions = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await plans.current();
    state.value = result.fold(Failed.new, (plan) => plan == null ? const Empty() : Ready(plan));
    await loadOptions();
  }

  Future<void> loadOptions() async {
    loadingOptions.value = true;
    final result = await plans.options();
    loadingOptions.value = false;
    // A failure leaves the list empty and says so in the UI. It is secondary content.
    options.assignAll(result.fold((_) => const <String, List<FoodOption>>{}, (bySlot) => bySlot));
  }

  Future<void> generate() async {
    if (generating.value) return;

    generating.value = true;
    error.value = null;
    final result = await plans.generate();
    generating.value = false;

    final failed = result.fold((f) => f.userMessage, (_) => null);
    if (failed != null) {
      error.value = failed;
      return;
    }

    await load();
  }
}
