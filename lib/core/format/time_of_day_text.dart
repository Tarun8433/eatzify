import 'package:flutter/material.dart';

/// The one place a time of day crosses between the wire and the screen.
///
/// Two different formats, deliberately:
/// * **On the wire** it is always `"HH:MM"`, 24-hour — `06:30`, `21:00`. The API validates that
///   shape and it sorts and compares correctly.
/// * **On screen** it is whatever the user's phone shows everywhere else, which for most of India
///   means `9:00 PM`. Showing them the stored `21:00` after they picked "9:00 PM" in the clock
///   reads as the app having misunderstood the answer.
///
/// CLAUDE.md rule 5 in spirit: the wire format is not a display string and must never be rendered.
abstract final class TimeOfDayText {
  /// Parses the wire format. Returns null for null, and for anything that is not `HH:MM` — a
  /// malformed stored value shows as "not set" rather than crashing a whole screen.
  static TimeOfDay? parse(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  /// To the wire format. Always zero-padded — `6:5` is not a time the API accepts.
  static String toWire(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// For display. Follows the device's 12/24-hour setting and the app's locale, so it matches both
  /// the clock the user just picked from and the rest of their phone.
  static String format(BuildContext context, TimeOfDay time) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

  /// Hours from a bedtime to a wake-up time, crossing midnight (D-77).
  ///
  /// `23:00` to `06:30` is 7.5, not -16.5: the subtraction wraps a day, because that is the only
  /// reading of those two numbers that means anything. Null when either time is missing or
  /// unparseable, and when they are the SAME time — 0 and 24 are both defensible readings of that
  /// and neither is worth guessing at.
  static double? hoursSlept({required String? bedtime, required String? wakeTime}) {
    final bed = parse(bedtime);
    final wake = parse(wakeTime);
    if (bed == null || wake == null) return null;

    final bedMinutes = bed.hour * 60 + bed.minute;
    final wakeMinutes = wake.hour * 60 + wake.minute;
    final span = (wakeMinutes - bedMinutes) % (24 * 60);
    if (span == 0) return null;

    return span / 60;
  }

  /// Wire string straight to display text. Null when there is nothing stored yet, so the caller
  /// decides what "not set" reads as.
  static String? formatWire(BuildContext context, String? hhmm) {
    final parsed = parse(hhmm);
    return parsed == null ? null : format(context, parsed);
  }
}
