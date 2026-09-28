import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';

/// Where this phone stands with its health store.
typedef HealthConnection = ({HealthAvailability availability, HealthPermission permission});

/// The "Health data" screen (D-215): what is read, whether it is connected, and the one place a
/// permission sheet is allowed to appear.
class HealthConnectController extends FullLifeCycleController with FullLifeCycleMixin {
  HealthConnectController({required this.health, required this.sync});

  final HealthRepository health;
  final SyncHealth sync;

  final state = Rx<ViewState<HealthConnection>>(const Loading());

  /// A connect, an install or a fill-in is running. The buttons wait rather than stack.
  final busy = false.obs;

  /// How the last tapped sync on this screen ended. Null until one has run.
  final lastSync = Rxn<SyncHealthResult>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Coming back from the Play Store or the Settings app is exactly when the answer changes.
  @override
  void onResumed() => unawaited(load());

  @override
  void onPaused() {}

  @override
  void onInactive() {}

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  /// Neither question can fail — each answers with a state, and "cannot tell" is one of them — so
  /// this screen is never Failed or Empty in practice. The page still renders both (rule 6).
  Future<void> load() async {
    final availability = await health.availability();
    final permission = availability == HealthAvailability.ready
        ? await health.permission()
        : HealthPermission.denied;
    state.value = Ready((availability: availability, permission: permission));
  }

  /// Connect and Sync are the same tap (D-218): ask for access if it is not settled, then fill in
  /// the last 30 days with today's device figures taking over from typed ones. Connecting and then
  /// seeing nothing would read as "it did not work".
  Future<void> syncNow() => _whileBusy(() async {
    final result = await sync.syncNow();
    lastSync.value = result;
    // Home shares this sync, so it now believes today is already sent and would never reload to
    // show it. Tell it directly.
    if (result.changedTheDay && Get.isRegistered<HomeController>()) {
      unawaited(Get.find<HomeController>().load(quietly: true));
    }
    await load();
  });

  Future<void> install() => _whileBusy(() async {
    await health.openInstall();
    await load();
  });

  Future<void> _whileBusy(Future<void> Function() work) async {
    if (busy.value) return;
    busy.value = true;
    try {
      await work();
    } finally {
      busy.value = false;
    }
  }
}
