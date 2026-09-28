import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_pro/data/repositories/health_repository_impl.dart';
import 'package:health_pro/domain/entities/health_metric.dart';

/// D-214. The metric list is written in Dart, but three other places have to agree with it: the
/// server's measurement kinds, the plugin's per-platform type lists, and the Android manifest. None
/// of those can be checked by the type system, and every mismatch is silent — a 422 swallowed by a
/// background sync, or a read the plugin refuses at runtime. So these tests read the files.

void main() {
  group('the server knows every metric', () {
    final rules = File('api/src/measurements/measurement-rules.ts').readAsStringSync();

    for (final metric in HealthMetric.values) {
      test('should accept ${metric.kind} in ${metric.unit}', () {
        final bound = RegExp(
          "^\\s*${metric.kind}:\\s*\\{[^}]*unit:\\s*'([^']+)'",
          multiLine: true,
        ).firstMatch(rules)?.group(1);

        expect(bound, isNotNull, reason: 'no BOUNDS row for ${metric.kind} — every sync 422s');
        expect(bound, metric.unit, reason: 'the server would answer UNIT_MISMATCH');
        expect(rules, contains("'${metric.kind}',"), reason: 'not in MEASUREMENT_KINDS');
      });
    }
  });

  group('the plugin can read every metric', () {
    for (final metric in HealthMetric.values) {
      test('should map ${metric.name} to a type iOS has', () {
        expect(dataTypeKeysIOS, contains(HealthRepositoryImpl.typeFor(metric, isIOS: true)));
      });

      test('should map ${metric.name} to a type Android has', () {
        expect(dataTypeKeysAndroid, contains(HealthRepositoryImpl.typeFor(metric, isIOS: false)));
      });
    }

    /// Total and basal energy both include resting metabolism, which the plan already counts.
    test('should read active energy and nothing that includes BMR', () {
      for (final isIOS in [true, false]) {
        final type = HealthRepositoryImpl.typeFor(HealthMetric.activeEnergy, isIOS: isIOS);
        expect(type, HealthDataType.ACTIVE_ENERGY_BURNED);
      }
    });
  });

  group('the Android manifest declares every read', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    const permissionFor = {
      HealthMetric.steps: 'READ_STEPS',
      HealthMetric.activeEnergy: 'READ_ACTIVE_CALORIES_BURNED',
      HealthMetric.distance: 'READ_DISTANCE',
    };

    test('should have a permission for each metric', () {
      expect(permissionFor.keys, containsAll(HealthMetric.values));
      for (final permission in permissionFor.values) {
        expect(manifest, contains('android.permission.health.$permission"'));
      }
    });

    /// Declaring more than is read makes the Play review ask why, and the sheet look alarming.
    test('should declare no health permission beyond those', () {
      final declared = RegExp(
        r'android\.permission\.health\.(\w+)"',
      ).allMatches(manifest).map((m) => m.group(1)).toSet();
      expect(declared, permissionFor.values.toSet());
    });

    test('should carry the rationale link Health Connect requires on both Android lines', () {
      expect(manifest, contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'));
      expect(manifest, contains('android.intent.category.HEALTH_PERMISSIONS'));
      expect(manifest, contains('<package android:name="com.google.android.apps.healthdata" />'));
    });

    /// Google review taps the "privacy policy" link on the permission screen. Both Android lines
    /// have to land on the activity that opens it — not on MainActivity, which just opens the app.
    test('should send the privacy link to the policy on both Android lines', () {
      final rationale = RegExp(
        r'<activity\s+android:name="\.PrivacyPolicyActivity"[^>]*>\s*<intent-filter>\s*'
        r'<action android:name="androidx\.health\.ACTION_SHOW_PERMISSIONS_RATIONALE" />',
      );
      expect(manifest, matches(rationale));
      expect(
        manifest,
        matches(RegExp(r'<activity-alias[^>]*android:targetActivity="\.PrivacyPolicyActivity"')),
      );
      expect(
        File('android/app/src/main/kotlin/app/eatzify/PrivacyPolicyActivity.kt').existsSync(),
        isTrue,
      );
    });

    test('should host the permission flow in a fragment activity', () {
      final activity = File(
        'android/app/src/main/kotlin/app/eatzify/MainActivity.kt',
      ).readAsStringSync();
      expect(activity, contains('class MainActivity : FlutterFragmentActivity()'));
    });
  });

  test('should hold the HealthKit entitlement on iOS', () {
    final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, contains('<key>com.apple.developer.healthkit</key>'));
  });

  group('a diary window', () {
    final window = DiaryWindow(
      diaryDate: '2026-09-17',
      start: DateTime.utc(2026, 9, 16, 22, 30),
      end: DateTime.utc(2026, 9, 17, 22, 30),
    );

    test('should include its first instant', () {
      expect(window.contains(window.start), isTrue);
    });

    test('should exclude its end, which is the next day', () {
      expect(window.contains(window.end), isFalse);
      expect(window.contains(window.end.subtract(const Duration(milliseconds: 1))), isTrue);
    });

    test('should parse the shape the server sends', () {
      final parsed = DiaryWindow.fromJson(const {
        'diary_date': '2026-09-17',
        'start': '2026-09-16T22:30:00.000Z',
        'end': '2026-09-17T22:30:00.000Z',
      });
      expect(parsed.diaryDate, window.diaryDate);
      expect(parsed.start, window.start);
      expect(parsed.end, window.end);
    });
  });
}
