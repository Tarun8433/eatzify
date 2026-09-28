import 'package:get/get.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';

/// `GET /profile` behind the four states CLAUDE.md rule 6 requires. No state is inferred from a
/// null: "no profile row" is Empty, a transport failure is Failed, and neither is a spinner.
class AccountController extends GetxController {
  AccountController({
    required this.profiles,
    required this.plans,
    this.diary,
    this.measurements,
    this.session,
    this.reminders,
  });

  final ProfileRepository profiles;
  final PlanRepository plans;

  /// Optional, the D-99 pattern: the glance card and the steps chip need it, the profile does
  /// not, and every test that is about the profile registers no diary.
  final DiaryRepository? diary;

  /// Optional likewise: only the body-stats card asks for it.
  final MeasurementsRepository? measurements;

  /// Optional, same pattern. Held so the screen can re-ask which shell this account gets: roles
  /// were fetched at boot and never again, so an account verified as a partner mid-session kept
  /// the client tabs until the app was killed — and the one gesture a user tries, pulling the
  /// profile to refresh it, did not ask.
  final SessionController? session;

  /// Optional, same pattern. The reminders' times come from the profile, so a profile that loads —
  /// after an edit, say — re-plans them (D-222).
  final RefreshReminders? reminders;

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

  /// [quiet] keeps whatever is already on screen while the reload runs. Pull-to-refresh passes
  /// it: the indicator is attached to the list, so flipping to `Loading` would blank the very
  /// widget the user is holding — a reload dressed as a refresh.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await profiles.profile();
    state.value = result.fold(
      Failed.new,
      (profile) => profile == null ? const Empty() : Ready(profile),
    );
    await Future.wait([_loadGoals(), _loadToday(), _loadWeight(), _loadRole(), _replan()]);
  }

  Future<void> _replan() async {
    final current = state.value;
    if (current is! Ready<ProfileView>) return;
    try {
      await reminders?.call(routine: ReminderRoutine.ofProfile(current.data));
    } on Object {
      // The reminders keep the times they had; nothing for this screen to show.
    }
  }

  /// Never fails the screen: [SessionController.loadRole] swallows its own errors, and a profile
  /// that loaded fine must not blank because the role call did not.
  Future<void> _loadRole() async => session?.loadRole();

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
