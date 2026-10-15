import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/widgets/app_sheet.dart';

/// Every sheet's last button once sat under the phone's back / home / recents bar.
void main() {
  const navBar = 48.0;

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.padding = const FakeViewPadding(bottom: navBar * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context: context,
              builder: (_) => FilledButton(onPressed: () {}, child: const Text('Done')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('should keep a sheet’s last button above the navigation bar', (tester) async {
    await openSheet(tester);

    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(find.text('Done')).bottom, lessThanOrEqualTo(screen - navBar));
  });

  test('should be the only way the app opens a bottom sheet', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            !file.path.endsWith('app_sheet.dart') &&
            RegExp(r'showModalBottomSheet\s*<').hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty, reason: 'use showAppSheet, which keeps sheets off the nav bar');
  });
}
