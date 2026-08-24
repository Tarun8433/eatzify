import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/client_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

/// The app now opens on onboarding (docs/14 §6), so shell tests mount the shell directly.
Finder navTab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Widget shellUnderTest() {
  Get
    ..reset()
    ..put(NavController(), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ClientShell(),
  );
}

void main() {
  testWidgets('the client shell shows exactly the four docs/14 §1 tabs', (tester) async {
    await tester.pumpWidget(shellUnderTest());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, ClientTab.values.length);

    for (final label in ['Home', 'Plan', 'Progress', 'You']) {
      expect(navTab(label), findsOneWidget, reason: '$label tab must exist');
    }
  });

  testWidgets('there is no hamburger menu — docs/14 §1 deletes it', (tester) async {
    await tester.pumpWidget(shellUnderTest());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('tapping a destination switches the tab', (tester) async {
    await tester.pumpWidget(shellUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('Today at a glance'), findsOneWidget);
    await tester.tap(navTab('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Weight, adherence and macros'), findsOneWidget);
  });

  testWidgets('the centre + opens the log sheet with four tabs and nothing else', (tester) async {
    await tester.pumpWidget(shellUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    for (final label in ['Food', 'Water', 'Weight', 'Steps']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('every tab renders one of the four ViewStates, never a bare spinner', (tester) async {
    await tester.pumpWidget(shellUnderTest());
    await tester.pumpAndSettle();

    for (final tab in ['Home', 'Plan', 'Progress', 'You']) {
      await tester.tap(navTab(tab));
      await tester.pumpAndSettle();
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: '$tab must not sit on an infinite spinner (CLAUDE.md rule 6)',
      );
    }
  });
}
