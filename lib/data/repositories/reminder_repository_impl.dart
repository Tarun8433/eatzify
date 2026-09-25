import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The words on a reminder, in the phone's language. Passed in because this layer has no
/// `BuildContext` to look them up with.
typedef ReminderCopy = ({
  String channel,
  String waterTitle,
  String waterBody,
  String logGlass,
  String mealTitle,
  Map<String, String> mealBodies,
  String dayEndTitle,
  String dayEndBody,
  String workoutTitle,
  String Function(String routine) workoutBody,
});

/// Reminders scheduled on the phone with `flutter_local_notifications` (D-222). No server, no push.
class ReminderRepositoryImpl implements ReminderRepository {
  ReminderRepositoryImpl({
    required this.copy,
    SecureStore? store,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _store = store ?? SecureStore(),
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The button on a water reminder that logs a glass without opening the app.
  static const logGlassAction = 'log_glass';

  static const _waterCategory = 'water';
  static const _channelId = 'reminders';

  final ReminderCopy Function() copy;
  final SecureStore _store;
  final FlutterLocalNotificationsPlugin _plugin;

  /// Sets the plugin up, in the app and in every background isolate that schedules. Safe to repeat.
  ///
  /// The time zone is the phone's own — the one the phone picked from where it is — so a reminder
  /// set for 09:00 rings at 09:00 wherever the person is.
  static Future<void> init({
    required String logGlassLabel,
    required DidReceiveNotificationResponseCallback onTap,
    required DidReceiveBackgroundNotificationResponseCallback onBackgroundTap,
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // An unknown name leaves the zone at UTC; India is the app's home, and a reminder at the
      // right hour there beats one five and a half hours off.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    await (plugin ?? FlutterLocalNotificationsPlugin()).initialize(
      InitializationSettings(
        // A monochrome glyph the app already ships for its widget.
        android: const AndroidInitializationSettings('ic_widget_water'),
        iOS: DarwinInitializationSettings(
          // Never at launch: only when someone switches a reminder on (D-222).
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _waterCategory,
              actions: [DarwinNotificationAction.plain(logGlassAction, logGlassLabel)],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );
  }

  @override
  Future<ReminderState> readState() async {
    final raw = await _store.readReminders();
    if (raw == null) return const ReminderState();
    try {
      return ReminderState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Unreadable is "nothing switched on", which is where a person can simply start again.
      return const ReminderState();
    }
  }

  @override
  Future<void> writeState(ReminderState state) => _store.writeReminders(jsonEncode(state.toJson()));

  @override
  Future<ReminderPermission> permission() async {
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android => await _android?.areNotificationsEnabled(),
      TargetPlatform.iOS => (await _ios?.checkPermissions())?.isEnabled,
      _ => null,
    };
    return _answer(granted);
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    final granted = switch (defaultTargetPlatform) {
      // Below Android 13 there is nothing to ask, and the answer is whatever system settings say.
      TargetPlatform.android =>
        await _android?.requestNotificationsPermission() ??
            await _android?.areNotificationsEnabled(),
      TargetPlatform.iOS => await _ios?.requestPermissions(alert: true, sound: true),
      _ => null,
    };
    return _answer(granted);
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    await cancelAll();
    // Nobody signed in, nobody to remind: a refresh racing a sign-out must not re-arm the week.
    if (reminders.isEmpty || await _store.read() == null) return;

    final words = copy();
    for (final (index, reminder) in reminders.indexed) {
      final (title, body) = switch (reminder.kind) {
        ReminderKind.water => (words.waterTitle, words.waterBody),
        ReminderKind.meal => (words.mealTitle, words.mealBodies[reminder.meal] ?? ''),
        ReminderKind.dayEnd => (words.dayEndTitle, words.dayEndBody),
        ReminderKind.workout => (words.workoutTitle, words.workoutBody(reminder.meal ?? '')),
      };
      final water = reminder.kind == ReminderKind.water;
      final at = reminder.at;

      await _plugin.zonedSchedule(
        index,
        title,
        body,
        tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            words.channel,
            icon: water ? 'ic_widget_water' : 'ic_widget_meal',
            category: AndroidNotificationCategory.reminder,
            actions: water ? [AndroidNotificationAction(logGlassAction, words.logGlass)] : null,
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: water ? _waterCategory : null),
        ),
        // A few minutes late is fine for a glass of water, and exact alarms need a permission
        // Play only grants to alarm-clock apps.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.kind.name,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  static ReminderPermission _answer(bool? granted) => switch (granted) {
    true => ReminderPermission.granted,
    false => ReminderPermission.denied,
    null => ReminderPermission.unsupported,
  };
}
