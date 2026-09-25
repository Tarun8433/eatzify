import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// What a tap on the widget means.
///
/// The widget sends a URI; this turns it into an intention. Parsed in one place so the native
/// layouts and the Dart handler cannot drift apart on a spelling.
enum HomeWidgetAction {
  /// Add a glass to today's water — the "+" button. On Android it writes without opening the app;
  /// an iOS widget can only open the app, which then adds the glass (D-219).
  addWater,

  /// Open the app on Home. The water tile: showing the day is not the same as adding to it.
  openToday,

  /// Open the app on the food tab. Choosing a food needs a search, a portion and a meal slot,
  /// which is a screen, not a button.
  logMeal,

  /// Open the app on Progress. Steps come from Health Connect or HealthKit read-only (rule 10);
  /// there is nothing here to write.
  openSteps,

  /// Anything else, including a scheme a future widget adds that this build does not know.
  unknown;

  static const scheme = 'eatzify';

  static HomeWidgetAction from(Uri? uri) => switch (uri?.host) {
    'water' => HomeWidgetAction.addWater,
    'today' => HomeWidgetAction.openToday,
    'meal' => HomeWidgetAction.logMeal,
    'steps' => HomeWidgetAction.openSteps,
    _ => HomeWidgetAction.unknown,
  };

  /// What the native side puts on its button.
  String get uri =>
      'eatzify://${switch (this) {
        HomeWidgetAction.addWater => 'water',
        HomeWidgetAction.openToday => 'today',
        HomeWidgetAction.logMeal => 'meal',
        HomeWidgetAction.openSteps => 'steps',
        HomeWidgetAction.unknown => '',
      }}';
}

/// Wires the widget's taps to the app.
///
/// **Two paths, and the difference is deliberate.** A tap that arrives while the app is running
/// goes through the normal controllers and repositories. A tap on a cold home screen wakes a
/// BACKGROUND ISOLATE, where none of the app's dependency injection exists — no controllers, no
/// registered repositories, no session. Which is why only `addWater` writes from there: it is one
/// integer with one meaning, and everything else needs a screen.
abstract final class HomeWidgetActions {
  /// Taps arriving while the app is alive.
  static Stream<HomeWidgetAction> get taps => HomeWidget.widgetClicked.map(HomeWidgetAction.from);

  /// What launched the app, when a tap started it cold.
  static Future<HomeWidgetAction> launchAction() async {
    if (!_supported) return HomeWidgetAction.unknown;
    return HomeWidgetAction.from(await HomeWidget.initiallyLaunchedFromHomeWidget());
  }

  /// Register what a BACKGROUND tap runs — the glass button.
  ///
  /// [onBackgroundTap] must be a top-level function annotated `@pragma('vm:entry-point')`. It runs
  /// in a fresh isolate that has none of this isolate's state, so it cannot be a closure, and it
  /// cannot be a static method either unless its class is annotated too — which is how the glass
  /// button did nothing at all until D-219: the VM refused to find the callback, and anything this
  /// isolate had stored for it would have been empty over there anyway.
  static Future<void> register(Future<void> Function(Uri?) onBackgroundTap) async {
    if (!_supported) return;
    await HomeWidget.registerInteractivityCallback(onBackgroundTap);
  }

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
