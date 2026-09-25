import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/app_card.dart';
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

/// Opens the Explore sheet (D-237): everything that sat between the daily goals and the quick
/// actions lives there now.
Future<void> openProfileSheet(WidgetTester tester) async {
  final explore = find.text('Explore your profile');
  // The quick-actions card builds whole, so the row may exist but sit scrolled past, above; a
  // downward `scrollTo` would never reach it.
  if (explore.evaluate().isEmpty) await scrollTo(tester, explore);
  await tester.ensureVisible(explore);
  await settle(tester);
  await tester.tap(explore);
  await settle(tester);
}

/// The sheet's own list. `find.byType(Scrollable).first` is the page underneath it.
Finder get sheetScrollable =>
    find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;

void main() {
  /// A profile edited on another device, or a plan regenerated elsewhere, only reaches this screen
  /// if something asks again. Pulling is that something.
  testWidgets('should re-fetch the profile when the list is pulled down', (tester) async {
    final repo = FakeProfileRepository();
    await tester.pumpWidget(accountUnderTest(repo));
    await settle(tester);
    expect(repo.profileCalls, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await settle(tester);

    expect(repo.profileCalls, 2);
    // The profile stays on screen under the indicator instead of collapsing to the skeleton.
    expect(find.byType(ProfileFrame), findsOneWidget);
  });

  /// docs/10 §1: `coach_l2` IS "Verified Partner". The app fetched roles at boot and never again,
  /// so an account verified while the app was open kept the client pills until it was killed —
  /// and the gesture a user actually tries, pulling the profile, did not ask either.
  testWidgets('should show My clients when the account is verified and the profile is pulled', (
    tester,
  ) async {
    final repo = FakeProfileRepository();
    final widget = accountUnderTest(repo);
    Get.put(
      SessionController(
        store: SecureStore(storage: FakeSecureStorage()),
        auth: FakeAuthRepository(),
        profile: repo,
        splashFloor: Duration.zero,
      ),
      permanent: true,
    );

    await tester.pumpWidget(widget);
    await settle(tester);
    // To the pill row itself, not its header: the pills sit below the fold, and a `findsNothing`
    // that only proves "not yet built" would pass no matter what the role said.
    await scrollTo(tester, find.text('Become a partner'));
    expect(find.text('My clients'), findsNothing);

    // What an admin does at `POST /admin/coaches/{id}/verify`, while the app is already open.
    repo.roleNames = const ['coach_l2'];

    // Back to the top first. A pull only overscrolls — and only overscroll arms the indicator —
    // when the list is already at its start, and the check above left it scrolled down.
    await tester.fling(find.byType(ListView), const Offset(0, 2000), 2000);
    await settle(tester);
    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await settle(tester);

    await scrollTo(tester, find.text('Become a partner'));
    expect(find.text('My clients'), findsOneWidget);
  });

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
          .any(
            (c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).color == color,
          );

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

    await scrollTo(tester, find.text('29 years'));
    expect(find.text('29 years'), findsOneWidget);
    expect(find.text('170 cm'), findsOneWidget);

    // The goal, activity and diet rows are in the Explore sheet since D-237.
    await openProfileSheet(tester);
    expect(find.text('Your details'), findsOneWidget);
    // CLAUDE.md rule 4 / docs/15's first audit finding: the old build printed these verbatim.
    expect(find.textContaining('fat_loss'), findsNothing);
    expect(find.textContaining('light'), findsNothing);
    expect(find.textContaining('veg'), findsNothing);
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
    await openProfileSheet(tester);

    expect(find.text('Health'), findsOneWidget);
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

  /// Everything onboarding asks for has to be readable afterwards (D-176). The screen showed ten
  /// of the twenty-odd answers, so a user could not check what their plan was actually built from
  /// — and could not tell a wrong answer from one they never gave.
  testWidgets('reads back the answers onboarding collected', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 32,
              heightCm: 165,
              weightKg: 72,
              sexAtBirth: 'female',
              goal: 'fat_loss',
              activity: 'moderate',
              foodPreference: 'veg',
              conditions: [],
              allergies: [],
              healthProfileVersion: 1,
              goalWeightKg: 64,
              mealCount: '4',
              lifestyle: 'office',
              wakeTime: '07:00',
              sleepTime: '23:00',
              breakfastTime: '08:00',
              lunchTime: '13:00',
              dinnerTime: '20:30',
              budgetMonthlyInr: 6000,
              foodDislikes: 'karela',
              medications: 'metformin',
              digestiveSymptoms: ['acidity'],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await openProfileSheet(tester);

    // In SCREEN order. A ListView disposes what scrolls past, so a finder above the current
    // position can never be reached by scrolling further down.
    for (final finder in [
      find.textContaining('metformin'),
      find.text('Your day'),
      find.text('Your routine'),
      find.textContaining('6,000'),
      find.textContaining('karela'),
    ]) {
      await tester.scrollUntilVisible(finder, 160, scrollable: sheetScrollable);
      expect(finder, findsOneWidget);
    }
  });

  /// docs/04 §7: a four-meal pattern has no mid-morning or bedtime occasion. Those rows are
  /// ABSENT rather than reading "Not set" — printing a meal somebody never eats as missing invites
  /// them to fill it in.
  testWidgets('omits meal slots the chosen pattern does not have', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 32,
              heightCm: 165,
              weightKg: 72,
              sexAtBirth: 'female',
              goal: 'fat_loss',
              activity: 'moderate',
              foodPreference: 'veg',
              conditions: [],
              allergies: [],
              healthProfileVersion: 1,
              mealCount: '4',
              breakfastTime: '08:00',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await openProfileSheet(tester);

    await tester.scrollUntilVisible(find.text('Your day'), 160, scrollable: sheetScrollable);

    expect(find.text('Mid-morning'), findsNothing);
    expect(find.text('Bedtime (optional)'), findsNothing);
  });

  /// D-190. Which row is last on a card is a runtime fact: skip the mid-morning slot and Dinner
  /// becomes the bottom row. Marking it at the call site left the card ending on a line that
  /// separated it from nothing.
  testWidgets('a card ends on its last ANSWERED row, not a divider', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 32,
              heightCm: 165,
              weightKg: 72,
              sexAtBirth: 'female',
              goal: 'fat_loss',
              activity: 'moderate',
              foodPreference: 'veg',
              conditions: [],
              allergies: [],
              healthProfileVersion: 1,
              mealCount: '3',
              wakeTime: '07:00',
              breakfastTime: '08:00',
              dinnerTime: '20:30',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await openProfileSheet(tester);

    await tester.scrollUntilVisible(find.text('Dinner'), 160, scrollable: sheetScrollable);

    final card = find.ancestor(of: find.text('Dinner'), matching: find.byType(AppCard));
    // Three answered slots, so two lines between them and none under the last.
    expect(find.descendant(of: card, matching: find.byType(Divider)), findsNWidgets(2));
  });

  /// D-193. The number the account signs in with was the one thing onboarding collected that the
  /// profile never showed — the user could not tell which number they were signed in as.
  testWidgets('shows the number the account signs in with', (tester) async {
    await tester.pumpWidget(
      accountUnderTest(
        FakeProfileRepository(
          profileResult: const Right(
            ProfileView(
              ageYears: 32,
              heightCm: 165,
              weightKg: 72,
              sexAtBirth: 'female',
              goal: 'fat_loss',
              activity: 'moderate',
              foodPreference: 'veg',
              conditions: [],
              allergies: [],
              healthProfileVersion: 1,
              phone: '+919000000001',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await openProfileSheet(tester);
    await tester.scrollUntilVisible(find.text('Account'), 160, scrollable: sheetScrollable);

    // Unmasked. Every admin-facing view of this column is masked so one person cannot casually
    // read another's; this is the account holder reading their own.
    expect(find.text('+919000000001'), findsOneWidget);
  });

  /// An email or social signup never filled the column. The section is absent rather than reading
  /// "Not set", which would invite the user to set something no screen here can change.
  testWidgets('says nothing about a phone when the account has none', (tester) async {
    await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
    await settle(tester);
    await openProfileSheet(tester);

    expect(find.text('Account'), findsNothing);
    expect(find.text('Phone number'), findsNothing);
  });

  /// D-237. The page stops at the daily goals; the rest of the profile is one tap away rather than
  /// a long scroll the quick actions sat at the bottom of.
  group('the Explore sheet (D-237)', () {
    testWidgets('holds the profile sections, which are off the page until it opens', (
      tester,
    ) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);
      await scrollTo(tester, find.text('Sign out'));

      expect(find.text('Your details'), findsNothing);
      expect(find.text('Your routine'), findsNothing);

      await openProfileSheet(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Your details'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Your routine'), 160, scrollable: sheetScrollable);
      expect(find.text('Your routine'), findsOneWidget);
    });

    testWidgets('the rows and the sheet survive 200 % font scale (rule 12)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);
      await scrollTo(tester, find.text('Sign out'));

      await openProfileSheet(tester);
      await tester.scrollUntilVisible(find.text('Your routine'), 160, scrollable: sheetScrollable);

      // A RenderFlex overflow is reported as an exception, which is what this is waiting for.
      expect(tester.takeException(), isNull);
    });

    testWidgets('each quick action says in one line what is behind it', (tester) async {
      await tester.pumpWidget(accountUnderTest(FakeProfileRepository()));
      await settle(tester);
      await scrollTo(tester, find.text('Reports'));

      expect(find.text('Body stats, your details, health, your day and routine.'), findsOneWidget);
      expect(find.text('Your trends and progress over time.'), findsOneWidget);
      // A row with a chevron, not a pill: every action is a ListTile.
      expect(
        find.ancestor(of: find.text('Reports'), matching: find.byType(ListTile)),
        findsOneWidget,
      );
    });
  });
}
