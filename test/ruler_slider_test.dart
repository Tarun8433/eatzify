import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/widgets/ruler_slider.dart';

Widget rulerUnderTest({required double value, required ValueChanged<double> onChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          // The real range, not a window: 20 to 300 kg is what the server accepts.
          child: RulerSlider(value: value, min: 20, max: 300, onChanged: onChanged),
        ),
      ),
    );

void main() {
  testWidgets('dragging the ruler reports the notch it lands on', (tester) async {
    final reported = <double>[];
    await tester.pumpWidget(rulerUnderTest(value: 70, onChanged: reported.add));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RulerSlider), const Offset(-90, 0));
    await tester.pumpAndSettle();

    expect(reported, isNotEmpty);
    // Dragged left, so the ruler moved forward: every reading is above where it started, on a
    // tenth, and inside the window.
    expect(reported.last, greaterThan(70));
    expect(reported.last, lessThanOrEqualTo(300));
    expect((reported.last * 10).roundToDouble(), closeTo(reported.last * 10, 0.0001));
  });

  testWidgets('the ruler reaches the whole range it is given, not a window around the value', (
    tester,
  ) async {
    final reported = <double>[];
    await tester.pumpWidget(rulerUnderTest(value: 34, onChanged: reported.add));
    await tester.pumpAndSettle();

    // Opening at 34 kg must not mean 34 is the top of it — the ruler that shipped first stopped
    // five kilograms either side of wherever it opened.
    for (var i = 0; i < 12; i++) {
      await tester.fling(find.byType(RulerSlider), const Offset(-600, 0), 3000);
      await tester.pumpAndSettle();
    }

    expect(reported.last, greaterThan(60));
  });

  /// The parent owns the value. A ruler that announced its own layout back would fire a change
  /// nobody asked for — and a save button that lights up because a widget was built.
  testWidgets('merely appearing reports nothing', (tester) async {
    final reported = <double>[];
    await tester.pumpWidget(rulerUnderTest(value: 70, onChanged: reported.add));
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
  });
}
