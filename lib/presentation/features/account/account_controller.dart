import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';

/// `GET /profile` behind the four states CLAUDE.md rule 6 requires. No state is inferred from a
/// null: "no profile row" is Empty, a transport failure is Failed, and neither is a spinner.
class AccountController extends GetxController {
  AccountController({
    required this.profiles,
    required this.plans,
    this.diary,
    this.measurements,
  });

  final ProfileRepository profiles;
  final PlanRepository plans;

  /// Optional, the D-99 pattern: the glance card and the steps chip need it, the profile does
  /// not, and every test that is about the profile registers no diary.
  final DiaryRepository? diary;

  /// Optional likewise: only the body-stats card asks for it.
  final MeasurementsRepository? measurements;

  final state = Rx<ViewState<ProfileView>>(const Loading());

  /// The plan's daily targets, for the goal tiles (D-59). Deliberately NOT part of [state]: the
  /// plan is secondary content on this screen, so a plan that is missing or that failed to load
  /// leaves the tiles out and the profile intact. Folding it into the screen's state would mean a
  /// plan outage blanked a page whose actual subject — the profile — arrived fine.
  final goals = Rxn<Macros>();

  /// Today's diary, for the glance card (D-144). Null — not loaded, no diary — hides the card.
  final today = Rxn<DiaryDay>();

  /// The weight history, for the body-stats card. Null hides the card; the server's `change`
  /// figure travels with it so the trend sentence is never computed here.
  final weight = Rxn<MeasurementHistory>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await profiles.profile();
    state.value = result.fold(
      Failed.new,
      (profile) => profile == null ? const Empty() : Ready(profile),
    );
    await Future.wait([_loadGoals(), _loadToday(), _loadWeight()]);
  }

  Future<void> _loadGoals() async {
    final result = await plans.current();
    goals.value = result.fold((_) => null, (plan) => plan?.targets);
  }

  Future<void> _loadToday() async {
    final d = diary;
    if (d == null) return;
    (await d.day()).fold((_) {}, (day) => today.value = day);
  }

  Future<void> _loadWeight() async {
    final m = measurements;
    if (m == null) return;
    (await m.history('weight')).fold((_) {}, (h) => weight.value = h.isEmpty ? null : h);
  }
}
