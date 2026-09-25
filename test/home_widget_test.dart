import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/home_widget/home_screen_widget.dart';
import 'package:health_pro/core/home_widget/home_widget_actions.dart';

/// D-210. The home-screen widget's two decisions, both of which are pure and both of which the
/// native layouts depend on being right.

void main() {
  group('what a tap means', () {
    /// The URIs are written twice — once in Dart, once in the Android layout — so the parsing and
    /// the spelling have to agree or a button silently does nothing.
    test('should read each action the native side can send', () {
      expect(HomeWidgetAction.from(Uri.parse('eatzify://water')), HomeWidgetAction.addWater);
      expect(HomeWidgetAction.from(Uri.parse('eatzify://meal')), HomeWidgetAction.logMeal);
      expect(HomeWidgetAction.from(Uri.parse('eatzify://steps')), HomeWidgetAction.openSteps);
      expect(HomeWidgetAction.from(Uri.parse('eatzify://today')), HomeWidgetAction.openToday);
    });

    /// iOS adds a query `home_widget` needs to recognise a widget tap; it must not change the
    /// meaning.
    test('should ignore the query an iOS widget adds', () {
      expect(
        HomeWidgetAction.from(Uri.parse('eatzify://water?homeWidget')),
        HomeWidgetAction.addWater,
      );
    });

    /// The same spelling, round-tripped. A rename that touched only one side would pass every
    /// other test in this file.
    test('should parse back the uri it publishes', () {
      for (final action in [
        HomeWidgetAction.addWater,
        HomeWidgetAction.openToday,
        HomeWidgetAction.logMeal,
        HomeWidgetAction.openSteps,
      ]) {
        expect(HomeWidgetAction.from(Uri.parse(action.uri)), action);
      }
    });

    /// A newer widget sending something this build has never heard of must do nothing, not crash
    /// a background isolate.
    test('should treat an unknown action as nothing to do', () {
      expect(HomeWidgetAction.from(Uri.parse('eatzify://weigh')), HomeWidgetAction.unknown);
      expect(HomeWidgetAction.from(null), HomeWidgetAction.unknown);
    });
  });

  group('adding a glass', () {
    /// Water is stored as the day's TOTAL (D-86), so the button has to add to what is already
    /// there rather than send 200 and overwrite the day.
    test('should add a glass to what is already logged', () {
      expect(HomeScreenWidget.nextWaterTotal(450), 650);
    });

    /// Nothing logged yet is the first glass, not an error and not a no-op.
    test('should treat nothing logged as the first glass', () {
      expect(HomeScreenWidget.nextWaterTotal(null), HomeScreenWidget.glassMl);
      expect(HomeScreenWidget.nextWaterTotal(0), HomeScreenWidget.glassMl);
    });

    /// The middle pour from the log sheet — a glass, not a bottle. A widget that added 500 ml a
    /// tap would overstate a day within three taps.
    test('should add the glass the log sheet calls a glass', () {
      expect(HomeScreenWidget.glassMl, 200);
    });
  });
}
