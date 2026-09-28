import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/home_widget/home_screen_widget.dart';
import 'package:health_pro/core/home_widget/home_widget_actions.dart';

/// D-213. The names Dart uses to reload the widget must equal the names the native sides register.
///
/// **A mismatch here is silent.** `updateWidget` asks the system to reload a widget of that name,
/// the system finds none, and nothing happens — which on a phone looks exactly like "the widget
/// does not update". It cost an afternoon, and nothing in the type system could have caught it,
/// so these tests read the native files and compare.

void main() {
  test('should use the kind the iOS widget actually registers', () {
    final swift = File('ios/HomeScreenWidget/HomeScreenWidget.swift').readAsStringSync();

    final kind = RegExp(r'StaticConfiguration\(\s*kind:\s*"([^"]+)"').firstMatch(swift)?.group(1);

    expect(
      kind,
      isNotNull,
      reason: 'the Swift widget declares no kind — the regex or the file moved',
    );
    expect(kind, HomeScreenWidget.iOSWidgetKind);
  });

  test('should name the Android provider class that exists', () {
    const path = 'android/app/src/main/kotlin/app/eatzify/widget/EatzifyWidgetProvider.kt';
    final kotlin = File(path).readAsStringSync();

    expect(
      kotlin,
      contains('class ${HomeScreenWidget.androidProvider}'),
      reason: 'the provider class was renamed without updating Dart',
    );
    // The qualified name is what the launcher looks up; package plus class, and both halves have
    // to be right or the reload silently reaches nothing.
    expect(HomeScreenWidget.androidQualified, endsWith(HomeScreenWidget.androidProvider));
    expect(kotlin, contains('package app.eatzify.widget'));
  });

  /// D-219. Three sizes in the picker means three receivers, and Dart has to redraw all three.
  test('should declare and refresh every Android widget size', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/app/eatzify/widget/EatzifyWidgetProvider.kt',
    ).readAsStringSync();

    final declared = RegExp(
      r'android:name="\.widget\.(\w+)"',
    ).allMatches(manifest).map((m) => m.group(1)).toSet();
    expect(declared, HomeScreenWidget.androidProviders.toSet());

    for (final provider in HomeScreenWidget.androidProviders) {
      expect(kotlin, contains('class $provider'), reason: '$provider has no Kotlin class');
    }
  });

  /// Each size's layout exists, and every view the renderer binds is in it — a missing id is not
  /// a compile error, it is "Problem loading widget" on the home screen.
  test('should give every Android layout the views its renderer binds', () {
    const shared = ['kcal_value', 'kcal_caption', 'kcal_progress', 'add_water'];
    const bound = {
      'small': [...shared, 'steps_value', 'burned_value'],
      'medium': [
        ...shared,
        'water_value',
        'steps_value',
        'burned_value',
        'water_tile',
        'steps_tile',
        'burned_tile',
        'meal_tile',
      ],
      'large': [
        ...shared,
        'water_value',
        'water_caption',
        'water_progress',
        'steps_value',
        'burned_value',
        'water_tile',
        'steps_tile',
        'burned_tile',
        'meal_tile',
      ],
    };
    for (final MapEntry(key: size, value: ids) in bound.entries) {
      final layout = File(
        'android/app/src/main/res/layout/eatzify_widget_$size.xml',
      ).readAsStringSync();
      for (final id in ids) {
        expect(layout, contains('@+id/$id"'), reason: '$size layout has no $id');
      }
    }
  });

  /// A launcher inflates a widget with a short allow-list of view classes. Anything else — even a
  /// plain `View` used as a spacer — is "Can't load widget", and nothing catches it at build time.
  test('should build Android widget layouts only from views a launcher allows', () {
    const allowed = {
      'FrameLayout',
      'LinearLayout',
      'RelativeLayout',
      'GridLayout',
      'TextView',
      'ImageView',
      'ImageButton',
      'Button',
      'ProgressBar',
      'ViewStub',
    };
    for (final size in const ['small', 'medium', 'large']) {
      final layout = File(
        'android/app/src/main/res/layout/eatzify_widget_$size.xml',
      ).readAsStringSync();
      final used = RegExp(r'<([A-Za-z.]+)[\s>]').allMatches(layout).map((m) => m.group(1)!).toSet()
        ..remove('?xml');
      expect(
        used.difference(allowed),
        isEmpty,
        reason: '$size layout uses a view no launcher inflates',
      );
    }
  });

  /// Both native sides send the URIs Dart parses — and on iOS with the query `home_widget` needs,
  /// without which a tap opens the app and routes nowhere.
  test('should send only taps Dart understands, marked as widget taps on iOS', () {
    final swift = File('ios/HomeScreenWidget/HomeScreenWidget.swift').readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/app/eatzify/widget/EatzifyWidgetProvider.kt',
    ).readAsStringSync();

    final iosLinks = RegExp(r'URL\(string: "([^"]+)"\)').allMatches(swift).map((m) => m.group(1)!);
    expect(iosLinks, isNotEmpty);
    for (final link in iosLinks) {
      final uri = Uri.parse(link);
      expect(uri.queryParameters.containsKey('homeWidget'), isTrue, reason: link);
      expect(HomeWidgetAction.from(uri), isNot(HomeWidgetAction.unknown), reason: link);
    }

    final androidLinks = RegExp(
      r'Uri\.parse\("([^"]+)"\)',
    ).allMatches(kotlin).map((m) => m.group(1)!);
    expect(androidLinks, isNotEmpty);
    for (final link in androidLinks) {
      expect(HomeWidgetAction.from(Uri.parse(link)), isNot(HomeWidgetAction.unknown), reason: link);
    }
  });

  test('should offer three sizes on iOS', () {
    final swift = File('ios/HomeScreenWidget/HomeScreenWidget.swift').readAsStringSync();
    for (final family in const ['.systemSmall', '.systemMedium', '.systemLarge']) {
      expect(swift, contains(family));
    }
  });

  test('should share one app group with both entitlements files', () {
    for (final path in const [
      'ios/Runner/Runner.entitlements',
      'ios/HomeScreenWidgetExtension.entitlements',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains(HomeScreenWidget.appGroupId),
        reason:
            '$path names a different app group — the extension would open an '
            'empty container and show placeholders forever',
      );
    }
  });

  /// The Swift side reads the same keys Dart writes. Another silent one: a renamed key shows a
  /// dash rather than an error.
  test('should write the keys the iOS widget reads', () {
    final swift = File('ios/HomeScreenWidget/HomeScreenWidget.swift').readAsStringSync();

    for (final key in const [
      'water_ml',
      'water_target_ml',
      'steps',
      'kcal',
      'kcal_target',
      'burned_kcal',
    ]) {
      expect(swift, contains('"$key"'), reason: '$key is never read on iOS');
    }
  });
}
