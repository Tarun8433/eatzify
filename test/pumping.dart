import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `pumpAndSettle` for a screen with the walker on it.
///
/// He walks for as long as he is on screen (D-58), so a frame is always scheduled and
/// `pumpAndSettle` can only time out. Pumping a fixed span settles everything that does end — a
/// route transition, a fade, the tab turn — and then stops asking. One second is four times the
/// longest finite animation in the app.
Future<void> settle(WidgetTester tester, [Duration span = const Duration(seconds: 1)]) async {
  await tester.pump();
  await tester.pump(span);
  await tester.pump(span);
}

/// Scrolls [finder] into view, then settles.
///
/// The You tab is taller than the 600 pt test surface now that the profile frame heads it (D-59),
/// and a `ListView` only builds what is near the viewport — so its lower sections have to be
/// scrolled to before they exist to be found.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}
