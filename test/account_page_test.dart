import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/core/widgets/macro_rings.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/account_page.dart';
import 'package:health_pro/presentation/features/account/profile_frame.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

Widget accountUnderTest(ProfileRepository repo, {PlanRepository? plans}) {
  Get
    ..reset()
    ..put<ProfileRepository>(repo, permanent: true)
    ..put<PlanRepository>(plans ?? FakePlanRepository(plan: samplePlan), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    // The page carries its own sheet again (D-70), so pumping it alone is enough — the shell only
    // decides that this one page is layered over the walker rather than under him.
    home: const Scaffold(body: AccountPage()),
  );
}

void main() {
  group('the profile frame (D-59)', () {
    testWidgets('leaves the hero open for the shell walker, like Home (D-152)', (tester) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);

      expect(find.byType(ProfileFrame), findsOneWidget);
      // The figure who stands beside it is the shell's one walker (D-60), so this page must not
      // draw a second one — and since D-152 it paints no full-bleed sheet over him either.
      expect(find.byType(FrameSequence), findsNothing);
    });

    testWidgets('the frame greets, and without a name it does not invent one (D-144)', (
      tester,
    ) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);

      // The fixture has no name, so the greeting stands alone rather than showing a placeholder.
      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text('PROFILE'), findsNothing);
    });

    testWidgets('the goal tiles carry the plan targets', (tester) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);
      await scrollTo(tester, find.text('Daily goals'));

      expect(find.text('1859'), findsOneWidget);
      expect(find.text('125 g'), findsOneWidget);
      expect(find.text('223 g'), findsOneWidget);
      expect(find.text('52 g'), findsOneWidget);
    });

    testWidgets('each goal wears its macro colour, the same one its ring wears (D-61)', (
      tester,
    ) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);
      await scrollTo(tester, find.text('Daily goals'));

      // D-144 moved the colour from the row's fill to its disc; the hue still has to be the
      // macro's own, so the check is "a disc of that colour exists on the page".
      bool hasDisc(Color color) => tester
          .widgetList<Container>(find.byType(Container))
          .any((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).color == color);

      expect(hasDisc(AppColors.macroProtein), isTrue);
      expect(hasDisc(AppColors.macroCarb), isTrue);
      expect(hasDisc(AppColors.macroFat), isTrue);
      // The rings on Home use the same three, outer to inner, so the two screens agree.
      expect(MacroRings.fills, [AppColors.macroProtein, AppColors.macroCarb, AppColors.macroFat]);
    });

    testWidgets('no plan is said in words, never as four zeroes (D-43)', (tester) async {
      await tester.pumpWidget(
        accountUnderTest(FakeProfileRepository(), plans: FakePlanRepository()),
      );
      await settle(tester);
      await scrollTo(tester, find.text('Daily goals'));

      expect(find.text('Your daily goals appear here once you have a plan.'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a plan that fails to load leaves the profile intact', (tester) async {
      await tester.pumpWidget(
        accountUnderTest(
          FakeProfileRepository(),
          plans: FakePlanRepository(currentResult: const Left(OfflineFailure('offline'))),
        ),
      );
      await settle(tester);

      // The subject of this screen is the profile. A plan outage must not blank it.
      expect(find.byType(ProfileFrame), findsOneWidget);
      await scrollTo(tester, find.text('29 years'));
      expect(find.text('29 years'), findsOneWidget);
    });
  });

  testWidgets('Ready renders the profile, and never a raw enum wire value', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);

    // CLAUDE.md rule 4 / docs/15's first audit finding: the old build printed these verbatim.
    expect(find.textContaining('fat_loss'), findsNothing);
    expect(find.textContaining('light'), findsNothing);
    expect(find.textContaining('veg'), findsNothing);

    await scrollTo(tester, find.text('29 years'));
    expect(find.text('29 years'), findsOneWidget);
    expect(find.text('170 cm'), findsOneWidget);
  });

  testWidgets('Empty is shown when onboarding was never completed', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(FakeProfileRepository(profileResult: const Right(null))),
    );
    await settle(tester);

    expect(find.text("Your details aren't set up yet"), findsOneWidget);
    // The old copy said "Not signed in" on a screen only reachable while signed in.
    expect(find.textContaining('Not signed in'), findsNothing);
  });

  testWidgets('Failed shows the server user_message verbatim, with a retry', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Left(
            ApiFailure('We could not load your profile.', code: 'X', status: 500),
          ),
        ),
      ),
    );
    await settle(tester);

    // CLAUDE.md rule 7: the server's string, unmodified.
    expect(find.text('We could not load your profile.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no state leaves an infinite spinner (rule 6)', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sign out is reachable and not covered by the FAB', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);

    // In the list since D-146, at its foot — the test travels there like a thumb would.
    await scrollTo(tester, find.text('Sign out'));
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNotNull);
  });

  testWidgets('a declared condition is rendered through l10n, not as a wire value', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 40,
              heightCm: 165,
              weightKg: 70,
              sexAtBirth: 'female',
              goal: 'maintenance',
              activity: 'moderate',
              foodPreference: 'veg',
              conditions: ['prediabetes'],
              allergies: ['peanut'],
              healthProfileVersion: 2,
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.textContaining('prediabetes'), findsNothing);
    expect(find.textContaining('peanut'), findsNothing);
  });

  testWidgets('shows a placeholder avatar when no photo is set', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    // D-145: the affordance is the camera badge on the avatar, not a caption under it.
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
  });

  testWidgets('offers remove only once a photo exists', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);
    await scrollTo(tester, find.byIcon(Icons.photo_camera_outlined));
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await settle(tester);

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    // Nothing to remove yet — offering it would be a dead action.
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('remove is offered when a photo is set', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 29,
              heightCm: 170,
              weightKg: 70,
              sexAtBirth: 'male',
              goal: 'fat_loss',
              activity: 'light',
              foodPreference: 'veg',
              conditions: [],
              allergies: [],
              healthProfileVersion: 1,
              photoUrl: 'http://example.test/photo.jpg',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await scrollTo(tester, find.byIcon(Icons.photo_camera_outlined));
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await settle(tester);

    expect(find.text('Remove photo'), findsOneWidget);
  });
}
