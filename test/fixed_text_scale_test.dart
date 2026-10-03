import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/widgets/fixed_text_scale.dart';

/// D-247: the phone's font-size setting must not reach the app's text.
void main() {
  testWidgets('should draw text at the design size even when the phone asks for 200 %', (
    tester,
  ) async {
    TextScaler? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: FixedTextScale(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(seen, TextScaler.noScaling);
    expect(seen!.scale(16), 16);
  });

  testWidgets('should keep everything else the phone reports', (tester) async {
    MediaQueryData? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(1.5),
          size: Size(393, 852),
          padding: EdgeInsets.only(top: 59),
        ),
        child: FixedTextScale(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    // Only the text scale is overridden: screen size and the notch inset still come through.
    expect(seen!.size, const Size(393, 852));
    expect(seen!.padding.top, 59);
  });

  /// D-259: a phone with Android's "Display size" turned up reports a narrower screen.
  Future<MediaQueryData> inside(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MediaQueryData? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: screen, padding: const EdgeInsets.only(top: 36)),
        child: FixedTextScale(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return seen!;
  }

  testWidgets('should lay a narrow phone out at the design width, scaled to fit', (tester) async {
    final seen = await inside(tester, const Size(320, 693));

    expect(seen.size.width, FixedTextScale.designWidth);
    expect(seen.size.height, closeTo(693 * 393 / 320, 0.01), reason: 'same shape as the screen');
    expect(seen.padding.top, closeTo(36 * 393 / 320, 0.01), reason: 'the status bar scales too');
    expect(tester.takeException(), isNull);
  });

  testWidgets('should leave a tablet at its real width', (tester) async {
    final seen = await inside(tester, const Size(820, 1180));
    expect(seen.size, const Size(820, 1180));
  });

  testWidgets('should still deliver taps to the right place when scaled', (tester) async {
    tester.view.physicalSize = const Size(320, 693);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 693)),
        child: FixedTextScale(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 48, height: 48, key: Key('target')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('target')));
    expect(taps, 1);
  });
}
