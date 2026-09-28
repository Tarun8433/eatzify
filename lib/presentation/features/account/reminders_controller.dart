import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';

/// What the Reminders screen shows. `blocked` is "switched on, but the phone will not show them" —
/// the switches then read off, so the screen never claims a reminder the phone will not deliver
/// (the docs/15 defect).
typedef RemindersView = ({ReminderSettings settings, ReminderRoutine routine, bool blocked});

/// The Reminders screen (D-222). The only place the notification permission is asked for, and only
/// after a switch is turned on.
class RemindersController extends FullLifeCycleController with FullLifeCycleMixin {
  RemindersController({required this.reminders, required this.replan, required this.profiles});

  final ReminderRepository reminders;
  final RefreshReminders replan;
  final ProfileRepository profiles;

  final state = Rx<ViewState<RemindersView>>(const Loading());

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Back from the Settings app is when notifications get turned on.
  @override
  void onResumed() => unawaited(_recheck());

  @override
  void onPaused() {}

  @override
  void onInactive() {}

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  /// Empty on a phone with nothing to schedule on; Failed when the profile — where the times come
  /// from — could not be read, because reminders at made-up times are worse than none.
  Future<void> load() async {
    state.value = const Loading();
    final permission = await reminders.permission();
    if (permission == ReminderPermission.unsupported) {
      state.value = const Empty();
      return;
    }

    final profile = await profiles.profile();
    final failure = profile.fold((f) => f, (_) => null);
    if (failure != null) {
      state.value = Failed(failure);
      return;
    }

    final routine = ReminderRoutine.ofProfile(profile.getOrElse(() => null));
    final settings = (await reminders.readState()).settings;
    state.value = Ready((
      settings: settings,
      routine: routine,
      blocked: settings.anyOn && permission != ReminderPermission.granted,
    ));
    // The profile may have changed since the week was planned.
    await replan(routine: routine);
  }

  /// Every switch and choice. Turning something on is what asks the phone for permission.
  Future<void> change(ReminderSettings next) async {
    final current = state.value;
    if (current is! Ready<RemindersView>) return;

    var permission = await reminders.permission();
    if (next.anyOn && permission != ReminderPermission.granted) {
      permission = await reminders.requestPermission();
    }
    state.value = Ready((
      settings: next,
      routine: current.data.routine,
      blocked: next.anyOn && permission != ReminderPermission.granted,
    ));
    await replan(settings: next, routine: current.data.routine);
  }

  Future<void> _recheck() async {
    final current = state.value;
    if (current is! Ready<RemindersView>) return;

    final permission = await reminders.permission();
    final data = current.data;
    state.value = Ready((
      settings: data.settings,
      routine: data.routine,
      blocked: data.settings.anyOn && permission != ReminderPermission.granted,
    ));
    await replan();
  }
}
