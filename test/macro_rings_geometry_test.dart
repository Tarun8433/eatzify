import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/macro_rings.dart';

void main() {
  group('the rings are circles (D-66)', () {
    testWidgets('the widget occupies a square, not a squashed box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: MacroRings(size: 190, progress: [0.5, 0.5, 0.5])),
          ),
        ),
      );

      final box = tester.getRect(find.byType(MacroRings));
      expect(box.width, box.height, reason: 'an ellipse is what made the rings look overlapped');
    });

    test('every ring is a circle — equal radius in both axes', () {
      const size = Size(190, 190);
      for (var i = 0; i < 3; i++) {
        final rect = MacroRingPainter.ringRect(size, i);
        expect(rect.width, rect.height, reason: 'ring $i');
        expect(rect.center, size.center(Offset.zero), reason: 'ring $i is concentric');
      }
    });

    test('consecutive rings never touch, so none can read as overlapping', () {
      const size = Size(190, 190);
      const stroke = AppSizes.ringStroke;

      var previousInnerEdge = double.infinity;
      for (var i = 0; i < 3; i++) {
        final radius = MacroRingPainter.ringRect(size, i).width / 2;
        final outerEdge = radius + stroke / 2;
        final innerEdge = radius - stroke / 2;

        expect(
          outerEdge,
          lessThan(previousInnerEdge),
          reason: "ring $i's stroke runs into the one outside it",
        );
        previousInnerEdge = innerEdge;
      }
    });

    test('the innermost ring still has a positive radius at the painted size', () {
      final inner = MacroRingPainter.ringRect(
        const Size(AppSizes.heroRings, AppSizes.heroRings),
        2,
      );
      expect(inner.width / 2, greaterThan(AppSizes.ringStroke));
    });

    /// The three rings must read as one band, not as hoops around a hole. At stroke 13 / gap 7 the
    /// innermost came in at 0.55 of the outer and the group fell apart (D-67).
    test('the inner ring stays close to the outer, as the reference has it', () {
      const size = Size(AppSizes.heroRings, AppSizes.heroRings);
      final outer = MacroRingPainter.ringRect(size, 0).width / 2;
      final inner = MacroRingPainter.ringRect(size, 2).width / 2;

      expect(inner / outer, greaterThan(0.65), reason: 'the centre hole swallowed the band');
    });

    test('the floor look comes from a tilt, never from squashing the circles', () {
      // A rotation compresses strokes and gaps together; unequal axis insets do not, which is what
      // made the rings meet at the near and far edges.
      expect(AppSizes.ringTilt, lessThan(0), reason: 'tilted away from the viewer');
      expect(AppSizes.ringPerspective, greaterThan(0));
    });
  });
}
