import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/profession.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

/// docs/12 §6. The about-you step asks what someone does, and the partner offer answers straight
/// back. The declaration is routing and nothing else: it grants no level, it never reaches the
/// server, and a human still reads the documents before "verified" means anything.

Widget app() {
  Get
    ..reset()
    ..put<ProfileRepository>(FakeProfileRepository(), permanent: true)
    ..put<PlanRepository>(FakePlanRepository(), permanent: true);
  putFakeSession();
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const OnboardingPage(),
  );
}

Future<void> tapProfession(WidgetTester tester, String label) async {
  await tester.pumpWidget(app());
  await tester.pumpAndSettle();
  // The page has more than one Scrollable once a sheet can open over it, so the step's own is
  // named rather than guessed at.
  await tester.scrollUntilVisible(find.text(label), 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  /// The reply has to arrive while the answer is still the thing on screen. Held back to a later
  /// step it reads as an unrelated advert.
  testWidgets('offers the partner route as soon as a trainer says so', (tester) async {
    await tapProfession(tester, 'Trainer');

    expect(find.text('Work with clients on Eatzify'), findsOneWidget);
  });

  testWidgets('offers it to a nutritionist too', (tester) async {
    await tapProfession(tester, 'Nutritionist');

    expect(find.text('Work with clients on Eatzify'), findsOneWidget);
  });

  /// The overwhelming majority. A sheet about partnering, in the middle of being asked about your
  /// own health, is a sheet about a thing you are not.
  testWidgets('says nothing to someone here for themselves', (tester) async {
    await tapProfession(tester, 'No, just for myself');

    expect(find.text('Work with clients on Eatzify'), findsNothing);
  });

  /// docs/12 §6 forbids implying accreditation. The sheet says what happens next — which is
  /// nothing yet — rather than what a badge would look like.
  testWidgets('promises nothing and names the real next step', (tester) async {
    await tapProfession(tester, 'Trainer');

    expect(find.textContaining('Nothing happens yet'), findsOneWidget);
    expect(find.textContaining('Become a partner'), findsOneWidget);
  });

  /// A self-declaration is not a credential, and the sheet must not behave like one: dismissing
  /// it leaves the user exactly where they were, still onboarding as a client.
  testWidgets('changes nothing when dismissed', (tester) async {
    await tapProfession(tester, 'Doctor (nutrition)');

    // The sheet is taller than a 600 pt test surface, so the button has to be scrolled to before
    // it can be tapped — the same thing a real phone does.
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('Work with clients on Eatzify'), findsNothing);
    expect(Profession.doctor.mayCoach, isTrue);
  });
}
