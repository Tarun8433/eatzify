import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';

/// Renders [child] with a known 12/24-hour setting, since that is a device preference and the whole
/// point of the helper is that it follows it.
Widget _host({required bool use24Hour, required Widget child}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
    child: Scaffold(body: Builder(builder: (context) => child)),
  ),
);

void main() {
  group('the wire format is 24-hour and stays that way', () {
    test('parses HH:MM', () {
      expect(TimeOfDayText.parse('06:30'), const TimeOfDay(hour: 6, minute: 30));
      expect(TimeOfDayText.parse('21:00'), const TimeOfDay(hour: 21, minute: 0));
      expect(TimeOfDayText.parse('00:00'), const TimeOfDay(hour: 0, minute: 0));
    });

    test('a malformed stored value is "not set", not a crash', () {
      for (final bad in [null, '', '7', '7:5:3', 'half past six', '25:00', '12:75', 'ab:cd']) {
        expect(TimeOfDayText.parse(bad), isNull, reason: '$bad');
      }
    });

    test('serialises zero-padded — the API rejects 6:5', () {
      expect(TimeOfDayText.toWire(const TimeOfDay(hour: 6, minute: 5)), '06:05');
      expect(TimeOfDayText.toWire(const TimeOfDay(hour: 20, minute: 30)), '20:30');
    });
  });

  group('the screen shows what the picker showed', () {
    testWidgets('a 12-hour phone reads back "9:00 PM", not "21:00"', (tester) async {
      late String shown;
      await tester.pumpWidget(
        _host(
          use24Hour: false,
          child: Builder(
            builder: (context) {
              shown = TimeOfDayText.formatWire(context, '21:00')!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(shown, contains('9:00'));
      expect(shown.toUpperCase(), contains('PM'));
      expect(shown, isNot(contains('21')), reason: 'the stored form is not a display string');
    });

    testWidgets('a 24-hour phone still reads back 21:00', (tester) async {
      late String shown;
      await tester.pumpWidget(
        _host(
          use24Hour: true,
          child: Builder(
            builder: (context) {
              shown = TimeOfDayText.formatWire(context, '21:00')!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(shown, '21:00');
    });

    testWidgets('nothing stored yet formats to null so the caller can say "not set"', (
      tester,
    ) async {
      String? shown = 'unset';
      await tester.pumpWidget(
        _host(
          use24Hour: false,
          child: Builder(
            builder: (context) {
              shown = TimeOfDayText.formatWire(context, null);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(shown, isNull);
    });
  });

  group('hours slept, derived from the two clock times (D-77)', () {
    double? slept(String? bed, String? wake) =>
        TimeOfDayText.hoursSlept(bedtime: bed, wakeTime: wake);

    test('crosses midnight — the normal case, and the one a subtraction gets wrong', () {
      expect(slept('23:00', '06:30'), 7.5);
      expect(slept('22:15', '05:45'), 7.5);
      expect(slept('00:30', '08:00'), 7.5);
    });

    test('a nap inside one day still works', () {
      expect(slept('01:00', '09:00'), 8);
      expect(slept('13:00', '14:30'), 1.5);
    });

    test('a night-shift sleep — days in bed, up in the evening', () {
      expect(slept('09:00', '16:00'), 7);
    });

    test('the same time twice is unanswerable, not zero and not twenty-four', () {
      // 0 and 24 are both defensible readings, so it returns neither.
      expect(slept('23:00', '23:00'), isNull);
    });

    test('a missing or malformed half yields nothing', () {
      expect(slept(null, '06:30'), isNull);
      expect(slept('23:00', null), isNull);
      expect(slept('half ten', '06:30'), isNull);
      expect(slept('25:00', '06:30'), isNull);
    });

    test('never negative, whatever order the times fall in', () {
      for (final bed in ['00:00', '06:00', '12:00', '18:00', '23:59']) {
        for (final wake in ['00:01', '07:30', '13:45', '21:10']) {
          final hours = slept(bed, wake);
          if (hours == null) continue;
          expect(hours, greaterThan(0), reason: '$bed to $wake');
          expect(hours, lessThan(24), reason: '$bed to $wake');
        }
      }
    });
  });
}
