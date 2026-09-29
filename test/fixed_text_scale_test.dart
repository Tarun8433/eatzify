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
}
