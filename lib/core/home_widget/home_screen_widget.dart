import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Today, on the home screen — and a glass of water logged without opening the app.
///
/// **The app publishes, the widget renders.** Nothing is computed on the native side: it reads the
/// numbers this class wrote and draws them. A widget that did its own arithmetic would be a second
/// place the diary day is decided, and the 04:00 IST boundary already has exactly one
/// (`CLAUDE.md` rule 8).
abstract final class HomeScreenWidget {
  /// Shared between the app and the iOS widget extension. Must match the App Group in BOTH
  /// `Runner.entitlements` and `HomeScreenWidgetExtension.entitlements`, or the extension opens an
  /// empty container and the widget shows placeholders forever.
  ///
  /// The name carries another product's, because that is the group already provisioned on this
  /// account and the two entitlements files already point at it. Renaming it is not a code change:
  /// it means creating a new group in the Apple Developer portal and regenerating every
  /// provisioning profile. Worth doing before release, pointless to do mid-build.
  static const appGroupId = 'group.com.tarun.Influnexa.liveactivities';

  /// The names the platforms know the widget by, and both must match their native side exactly.
  ///
  /// A mismatch is silent and looks like "the widget does not update": `updateWidget` asks the
  /// system to reload a widget of that name, the system finds none, and nothing happens. This was
  /// `EatzifyWidget` against a Swift `kind` of `HomeScreenWidget` — the reload went nowhere every
  /// time (D-213).
  ///
  /// The iOS name follows the Swift rather than the other way round: a placed widget is bound to
  /// its `kind`, so renaming it would orphan every widget already on somebody's home screen.
  static const androidProvider = 'EatzifyWidgetProvider';
  static const androidQualified = 'app.eatzify.widget.EatzifyWidgetProvider';

  /// Every Android widget class — one per size in the picker (D-219). Each has to be told to
  /// redraw: an update names one provider, and the others would sit on yesterday's figures.
  /// [androidProvider] is the medium one and keeps its name so already-placed widgets stay bound.
  static const androidProviders = ['EatzifyWidgetSmall', androidProvider, 'EatzifyWidgetLarge'];
  static const _androidPackage = 'app.eatzify.widget';

  /// Must equal `StaticConfiguration(kind:)` in `ios/HomeScreenWidget/HomeScreenWidget.swift`.
  static const iOSWidgetKind = 'HomeScreenWidget';

  /// What a single tap on the water button adds. The middle pour from the log sheet — a glass, the
  /// amount somebody actually reaches for.
  static const glassMl = 200;

  static const _keys = (
    waterMl: 'water_ml',
    waterTargetMl: 'water_target_ml',
    steps: 'steps',
    kcal: 'kcal',
    kcalTarget: 'kcal_target',
    burnedKcal: 'burned_kcal',
    updatedAt: 'updated_at',
  );

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Push today's figures out to the home screen.
  ///
  /// Nulls are written as nulls, not zeroes. "Nobody measured" and "they did none" are different
  /// sentences (D-80), and the widget renders a dash for the first — the same rule every screen in
  /// the app follows.
  static Future<void> publish({
    required int? waterMl,
    required int? waterTargetMl,
    required int? steps,
    required int? kcal,
    required int? kcalTarget,
    required int? burnedKcal,
  }) async {
    if (!_supported) return;

    await Future.wait([
      HomeWidget.saveWidgetData<int?>(_keys.waterMl, waterMl),
      HomeWidget.saveWidgetData<int?>(_keys.waterTargetMl, waterTargetMl),
      HomeWidget.saveWidgetData<int?>(_keys.steps, steps),
      HomeWidget.saveWidgetData<int?>(_keys.kcal, kcal),
      HomeWidget.saveWidgetData<int?>(_keys.kcalTarget, kcalTarget),
      HomeWidget.saveWidgetData<int?>(_keys.burnedKcal, burnedKcal),
      // So the widget can say how fresh it is rather than implying a stale figure is live.
      HomeWidget.saveWidgetData<String>(_keys.updatedAt, DateTime.now().toIso8601String()),
    ]);

    await _refresh();
  }

  /// What the water button should write, given what is already logged.
  ///
  /// Water is stored as the day's TOTAL, not as a running sum (D-86) — two taps racing would
  /// otherwise each add a glass to a stale figure and one would be lost. So the widget adds to
  /// what it was last told, and the app re-publishes the server's answer straight after.
  static int nextWaterTotal(int? currentMl) => (currentMl ?? 0) + glassMl;

  static Future<void> _refresh() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // One kind on iOS; its three sizes are families of the same widget.
      await HomeWidget.updateWidget(iOSName: iOSWidgetKind);
      return;
    }
    await Future.wait([
      for (final provider in androidProviders)
        HomeWidget.updateWidget(
          androidName: provider,
          qualifiedAndroidName: '$_androidPackage.$provider',
        ),
    ]);
  }

  /// Home-screen widgets exist on phones only. On anything else every call here is a no-op rather
  /// than a platform exception a caller has to remember to catch.
  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
