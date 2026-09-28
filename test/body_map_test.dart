import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/widgets/body_map/body_map.dart';
import 'package:health_pro/core/widgets/body_map/body_outlines.dart';

/// The muscle map is a picture with no text in it: what a widget test can prove is that it has a
/// canvas to draw on and outlines to draw. It had neither on screen once — a CustomPaint with no
/// child is laid out at zero height — and nothing failed.
void main() {
  test('every figure carries its outlines', () {
    for (final outline in [maleFront, maleBack, femaleFront, femaleBack]) {
      expect(outline.muscles, isNotEmpty);
      expect(outline.muscles.values.expand((p) => p), isNotEmpty);
      expect(outline.silhouette, isNotEmpty);
      expect(outline.width, greaterThan(0));
      expect(outline.height, greaterThan(0));
    }
    // The 18 drawn muscles, front and back together.
    expect({...maleFront.muscles.keys, ...maleBack.muscles.keys}, hasLength(18));
    expect({...femaleFront.muscles.keys, ...femaleBack.muscles.keys}, hasLength(18));
  });

  testWidgets('should paint on a canvas with real height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BodyMap(levels: {'chest': 4, 'triceps': 2}, semanticsLabel: 'body'),
          ),
        ),
      ),
    );
    await tester.pump();

    final painted = tester.getSize(
      find.descendant(of: find.byType(BodyMap), matching: find.byType(CustomPaint)).first,
    );
    expect(painted.height, greaterThan(100));
    expect(painted.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
