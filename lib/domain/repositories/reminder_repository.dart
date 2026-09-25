import 'package:health_pro/domain/entities/reminder.dart';

/// The phone's own reminders (D-222): what is scheduled, and the state a re-plan starts from.
abstract class ReminderRepository {
  /// What was stored last, or the all-off default when nothing was or it cannot be read.
  Future<ReminderState> readState();

  Future<void> writeState(ReminderState state);

  Future<ReminderPermission> permission();

  /// Shows the system's question when it has not been answered yet.
  Future<ReminderPermission> requestPermission();

  /// Cancels everything scheduled and schedules exactly [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}
