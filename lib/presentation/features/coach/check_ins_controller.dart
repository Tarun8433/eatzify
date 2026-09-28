import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// The coach's Check-ins tab (docs/02 FR-5.2, FR-5.3).
///
/// The queue and the alerts are two reads of the same roster, and both are the SERVER's answer:
/// which client needs attention, and in what order, is not something the app works out.
class CheckInsController extends GetxController {
  CheckInsController({required this.coach});

  final CoachRepository coach;

  final state = Rx<ViewState<List<CheckIn>>>(const Loading());

  /// docs/02 FR-5.3. Kept apart from [state] so a failed alert read never blanks the queue —
  /// the reviews are the screen's subject, the alerts are what sits above them.
  final alerts = <CoachAlert>[].obs;

  /// The review being saved. Its card waits; the rest of the list does not.
  final saving = RxnString();

  /// The server's `user_message` from the last refusal (rule 7).
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();

    final queue = await coach.checkIns();
    state.value = queue.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));

    final signals = await coach.alerts();
    signals.fold((_) => alerts.clear(), (rows) => alerts.value = rows);
  }

  /// docs/09 §6: close one review with what was said and what was agreed.
  Future<bool> complete(String id, {String? notes, List<String> actions = const []}) async {
    if (saving.value != null) return false;
    saving.value = id;
    error.value = null;

    final result = await coach.completeCheckIn(id: id, notes: notes, actions: actions);
    saving.value = null;

    return result.fold(
      (f) {
        error.value = f.userMessage;
        return false;
      },
      (saved) {
        _replace(saved);
        return true;
      },
    );
  }

  /// The saved row from the server, in place of the one that was open. The list is not re-read:
  /// a queue that jumped around after each review would lose the coach's place in it.
  void _replace(CheckIn saved) {
    final current = state.value;
    if (current is! Ready<List<CheckIn>>) return;

    state.value = Ready([
      for (final row in current.data)
        if (row.id == saved.id) saved else row,
    ]);
    // The alerts are left alone: completing a review does not make somebody start logging again,
    // and quietly clearing a signal the server still reports would be the app inventing one.
  }
}
