import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

/// Everything a workout does to the phone itself: a tick and a buzz on a set, the screen held on,
/// a notification when rest ends while the app is in the background. Behind an interface so the
/// workout controller stays free of Flutter (controllers rule) and tests run silent.
abstract class WorkoutFeedback {
  Future<void> setChecked({required bool sound});

  /// Each of the last three seconds of rest.
  Future<void> restEnding({required bool sound});

  Future<void> restOver({required bool sound});

  Future<void> workoutSaved({required bool sound});

  Future<void> keepAwake({required bool on});

  /// Rings at [at] if the app is still in the background then. Replaces any earlier one.
  Future<void> scheduleRestAlert(DateTime at, {required String title, required String body});

  Future<void> cancelRestAlert();
}

class DeviceWorkoutFeedback implements WorkoutFeedback {
  DeviceWorkoutFeedback({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Well clear of the reminders, which number from 0 upward for the week ahead.
  static const _restAlertId = 900001;
  static const _channelId = 'reminders';

  @override
  Future<void> setChecked({required bool sound}) async {
    await HapticFeedback.lightImpact();
    if (sound) await SystemSound.play(SystemSoundType.click);
  }

  @override
  Future<void> restEnding({required bool sound}) async {
    if (sound) await SystemSound.play(SystemSoundType.click);
  }

  @override
  Future<void> restOver({required bool sound}) async {
    await HapticFeedback.heavyImpact();
    if (sound) await SystemSound.play(SystemSoundType.alert);
  }

  @override
  Future<void> workoutSaved({required bool sound}) async {
    await HapticFeedback.mediumImpact();
    if (sound) await SystemSound.play(SystemSoundType.alert);
  }

  @override
  Future<void> keepAwake({required bool on}) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object {
      // A phone that will not hold the screen on still runs the workout.
    }
  }

  @override
  Future<void> scheduleRestAlert(DateTime at, {required String title, required String body}) async {
    try {
      await _plugin.zonedSchedule(
        _restAlertId,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(_channelId, 'Reminders', icon: 'ic_widget_water'),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on Object {
      // No permission, or the plugin was never set up: the on-screen timer still counts.
    }
  }

  @override
  Future<void> cancelRestAlert() async {
    try {
      await _plugin.cancel(_restAlertId);
    } on Object {
      // Nothing scheduled is the usual case.
    }
  }
}
