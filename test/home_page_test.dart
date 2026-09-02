import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

Widget homeUnderTest(DiaryRepository repo, {PlanRepository? plans}) {
  Get
    ..reset()
    ..put<DiaryRepository>(repo, permanent: true)
    ..put<PlanRepository>(plans ?? FakePlanRepository(), permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: HomePage()),
  );
}

/// Every ring on screen, by the value it was ASKED to show (D-138). The nutrient tiles each
/// carry one, and the calorie card carries the burned ring.
List<double?> ringsOf(WidgetTester tester) =>
    tester.widgetList<ProgressRing>(find.byType(ProgressRing)).map((r) => r.progress).toList();

/// The stage the walker stands on — decoration, but decoration the layout is built around.
Finder stageFinder() => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.contains('dashboard_stage'),
);

DiaryDay dayWith({
  Macros? totals,
  Macros? targets,
  List<LogEntry> entries = const [],
  int? steps,
  MeasurementSource stepsSource = MeasurementSource.manual,
  int? energyBurnedKcal,
  int? waterLoggedMl,
  int? waterTargetMl,
}) => DiaryDay(
  diaryDate: '2026-08-25',
  entries: entries,
  totals: totals ?? const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
  targets: targets,
  steps: steps,
  stepsSource: stepsSource,
  energyBurnedKcal: energyBurnedKcal,
  waterLoggedMl: waterLoggedMl,
  waterTargetMl: waterTargetMl,
);

void main() {
  testWidgets('shows eaten against target when a plan exists', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(
              totals: const Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
              targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // The calorie card carries the day's sum; each nutrient tile carries eaten-against-target.
    // The card sets the figure large and the unit small beside it, so they are two Texts.
    expect(find.text('348'), findsOneWidget);
    // The tiles sit under the hero, which on a 600 pt test surface is below the fold.
    await scrollTo(tester, find.text('20 / 125 g'));
    expect(find.text('20 / 125 g'), findsOneWidget);
    expect(find.text('48 / 223 g'), findsOneWidget);
  });

  testWidgets('no plan means no comparison, not a comparison against zero', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(totals: const Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8)),
          ),
        ),
      ),
    );
    await settle(tester);

    // "348 of 0 kcal" would be a fabricated target. With no plan there is nothing to compare
    // against, so the nutrient section is simply not there, and the way forward is the button.
    expect(find.text('348'), findsOneWidget);
    expect(find.textContaining('of 0'), findsNothing);
    expect(find.text('Macronutrients'), findsNothing);
    expect(find.text('20 / '), findsNothing);
    expect(find.text('Create my plan'), findsOneWidget);
  });

  testWidgets('an empty day still shows the targets it is working towards', (tester) async {
    await tester.pumpWidget(homeUnderTest(FakeDiaryRepository()));
    await settle(tester);

    // Empty state would hide the plan; a day with no entries is Ready, not Empty.
    // Below the fold on a 600 pt surface now that the stat grid heads the day (D-100) — the same
    // reason the You tab's tests scroll (D-59). The content exists; the viewport is short.
    await scrollTo(tester, find.text('Nothing logged yet today.'));
    expect(find.text('Nothing logged yet today.'), findsOneWidget);
    // The tiles still state the goal a nought is measured against.
    expect(find.text('0 / 125 g'), findsOneWidget);
  });

  testWidgets('Failed shows the server message with a retry', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: const Left(ApiFailure('We could not load today.', code: 'X', status: 500)),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('We could not load today.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('going over target is stated, never scored (docs/05 §6)', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(
              totals: const Macros(kcal: 2400, proteinG: 160, carbG: 300, fatG: 90),
              targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // Home states the sum and the tiles state their ratios; nothing on this tab judges the day.
    expect(find.text('2400'), findsOneWidget);
    for (final banned in ['Over', 'Exceeded', 'Failed', 'Missed', 'Too much']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
  });

  testWidgets('an entry shows the household measure, not only grams', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(
              totals: const Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
              targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
              entries: [
                const LogEntry(
                  id: '1',
                  slot: 'lunch',
                  name: 'Dal (arhar cooked)',
                  quantityG: 300,
                  measureLabel: 'katori',
                  kcal: 348,
                  locked: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // docs/03 §units: users think in katoris, so grams alone is the wrong primary.
    await scrollTo(tester, find.text('katori · 300 g'));
    expect(find.text('katori · 300 g'), findsOneWidget);
    // Twice, the same truth: the slot's own sum and the entry row. (The calorie card states it
    // too, but the scroll above has let the lazy ListView release it; the dashboard group pins
    // the card's figure.)
    expect(find.text('348 kcal'), findsNWidgets(2));
    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('with no plan, Home offers to create one', (tester) async {
    final plans = FakePlanRepository();
    await tester.pumpWidget(
      homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith())), plans: plans),
    );
    await settle(tester);

    // Nothing else in the app calls POST /plans/generate, so without this the tab is permanently
    // empty and every ring stays blank.
    await scrollTo(tester, find.text('Create my plan'));
    await tester.tap(find.text('Create my plan'));
    await settle(tester);

    expect(plans.generated, 1);
  });

  testWidgets('a blocked plan shows the docs/05 §7 referral copy, verbatim', (tester) async {
    const referral =
        "Based on what you've told us, a plan generated by an app isn't the right tool here.";
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(dayResult: Right(dayWith())),
        plans: FakePlanRepository(
          failure: const ApiFailure(referral, code: 'PLAN_GATE_BLOCKED', status: 422),
        ),
      ),
    );
    await settle(tester);

    await scrollTo(tester, find.text('Create my plan'));
    await tester.tap(find.text('Create my plan'));
    await settle(tester);

    await scrollTo(tester, find.textContaining("isn't the right tool here"));
    expect(find.textContaining("isn't the right tool here"), findsOneWidget);
  });

  testWidgets('the create button is hidden once a plan exists', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52)),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Create my plan'), findsNothing);
  });

  testWidgets('with no target the ring is present but unfilled', (tester) async {
    await tester.pumpWidget(homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith()))));
    await settle(tester);

    // The ring stays — removing it left a hole where the screen's centrepiece belongs. What
    // stops an unfilled ring reading as failure is the copy beside it.
    expect(
      find.byType(CustomPaint).evaluate().where((e) {
        final w = e.widget as CustomPaint;
        return w.painter.runtimeType.toString().contains('RingPainter');
      }),
      isNotEmpty,
    );
    expect(find.text('Create my plan'), findsOneWidget);
  });

  testWidgets('with a target the gauge draws its ring', (tester) async {
    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(
              totals: const Macros(kcal: 900, proteinG: 40, carbG: 100, fatG: 30),
              targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(
      find.byType(CustomPaint).evaluate().where((e) {
        final w = e.widget as CustomPaint;
        return w.painter.runtimeType.toString().contains('RingPainter');
      }),
      isNotEmpty,
    );
  });

  testWidgets('entries group under their meal, in the order a day runs', (tester) async {
    LogEntry at(String slot, String name) =>
        LogEntry(id: name, slot: slot, name: name, quantityG: 100, kcal: 200, locked: false);

    // Tall surface so every heading lays out — the assertion is about order, not scrolling.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      homeUnderTest(
        FakeDiaryRepository(
          dayResult: Right(
            dayWith(
              totals: const Macros(kcal: 600, proteinG: 30, carbG: 60, fatG: 20),
              targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
              // Logged out of order on purpose.
              entries: [at('dinner', 'Dal'), at('breakfast', 'Poha'), at('lunch', 'Roti')],
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final headings = [
      'Breakfast',
      'Lunch',
      'Dinner',
    ].map((h) => tester.getTopLeft(find.text(h)).dy).toList();

    // A diary reads as "what did I have at lunch", not as a chronological stream.
    expect(headings, orderedEquals([...headings]..sort()));
    // Slots with nothing in them do not appear — an empty heading every day is noise, and
    // docs/05 §6 means it must never read as a gap the user failed to fill.
    expect(find.text('Bedtime'), findsNothing);
    expect(find.text('Snack'), findsNothing);
  });

  // The counts-down-then-states-the-excess headline moved to the Plan tab with the target card
  // (D-136); its tone rules are asserted there and in 'going over target is stated, never scored'.

  group('dashboard', () {
    Future<void> pumpWithPlan(WidgetTester tester) async {
      await tester.pumpWidget(
        homeUnderTest(
          FakeDiaryRepository(
            dayResult: Right(
              dayWith(
                totals: const Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
                targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('shows supplied alongside the gauge', (tester) async {
      await pumpWithPlan(tester);

      expect(find.text('supplied'), findsOneWidget);
      expect(find.text('348'), findsOneWidget);
    });

    testWidgets('burned shows an em dash, never a zero', (tester) async {
      await pumpWithPlan(tester);

      // Nothing reported. A 0 here would read as "you burned nothing today" rather than "you have
      // not told us", which is a fabricated fact.
      expect(find.text('burned'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('macro figures carry value and target; the rings fill to the same ratios', (
      tester,
    ) async {
      await pumpWithPlan(tester);

      await scrollTo(tester, find.text('20 / 125 g'));
      expect(find.text('20 / 125 g'), findsOneWidget);
      expect(find.text('48 / 223 g'), findsOneWidget);
      expect(find.text('8 / 52 g'), findsOneWidget);
      // Each tile's ring is asked for exactly its own ratio (D-138).
      final rings = ringsOf(tester).whereType<double>().toList();
      expect(
        rings,
        containsAll([closeTo(20 / 125, 0.001), closeTo(48 / 223, 0.001), closeTo(8 / 52, 0.001)]),
      );
    });

    testWidgets('the hero is the screen, not a card on it (D-57)', (tester) async {
      await pumpWithPlan(tester);

      // Entry rows keep their cards; the emphasised one around the walker is gone. A border round
      // him made him read as one widget among several instead of as the screen itself.
      expect(find.byWidgetPredicate((w) => w is AppCard && w.accent), findsNothing);
      // The stage he stands on is the SHELL's now, drawn from the same bounds as the walker
      // (D-139) — `shell_walker_test` pins the podium to his feet.
    });

    testWidgets('the hero draws the rings but not the figure (D-60)', (tester) async {
      await pumpWithPlan(tester);

      // One walker exists in the app and the shell owns it, so a tab change slides him instead of
      // cross-fading two of him. Home draws what he stands on; `shell_walker_test` covers the walk.
      expect(find.byType(FrameSequence), findsNothing);
      expect(stageFinder(), findsNothing, reason: 'the stage is the shell´s too (D-139)');
    });

    testWidgets('no plan keeps the layout, unfilled, with the state in words', (tester) async {
      await tester.pumpWidget(homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith()))));
      await settle(tester);

      // The structure stays so the screen does not look broken; the copy carries the meaning.
      expect(find.text('supplied'), findsOneWidget);
      expect(find.text('burned'), findsOneWidget);
      expect(find.text('Create my plan'), findsOneWidget);

      // Track only, no fill: null is "no target", never a target of zero (D-43).
      expect(ringsOf(tester), everyElement(isNull));
    });

    testWidgets('reduced motion still lands on the final values', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: homeUnderTest(
            FakeDiaryRepository(
              dayResult: Right(
                dayWith(
                  totals: const Macros(kcal: 348, proteinG: 20, carbG: 48, fatG: 8),
                  targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
                ),
              ),
            ),
          ),
        ),
      );
      // One pump only: with animations disabled the figures must already read final, not partway
      // through a count.
      await tester.pump();
      await tester.pump();

      expect(find.text('348'), findsOneWidget);
      expect(ringsOf(tester).whereType<double>(), contains(closeTo(20 / 125, 0.001)));
    });
  });

  group('manual activity (D-80)', () {
    testWidgets('the "not set up" line goes once a figure exists', (tester) async {
      await tester.pumpWidget(
        homeUnderTest(
          FakeDiaryRepository(dayResult: Right(dayWith(energyBurnedKcal: 410, steps: 8432))),
        ),
      );
      await settle(tester);

      expect(find.text('410'), findsOneWidget, reason: 'the reported figure, not a dash');
      expect(find.text('8432'), findsOneWidget);
    });

    testWidgets('steps without a burned figure never claims tracking is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith(steps: 10000)))),
      );
      await settle(tester);

      expect(find.text('10000'), findsOneWidget);
      // The bug: "Activity tracking isn't set up yet" beside a step count the user had just
      // entered through it (D-80). The em dash on "burned" states the absence without a lecture.
      expect(find.textContaining('set up yet'), findsNothing);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('with nothing reported it still says so, and shows no zero', (tester) async {
      await tester.pumpWidget(homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith()))));
      await settle(tester);

      // A zero would read as "you burned nothing today" rather than "you have not told us".
      expect(find.text('—'), findsWidgets);
    });
  });

  group('water (D-86)', () {
    testWidgets('shows progress against the goal the engine set', (tester) async {
      await tester.pumpWidget(
        homeUnderTest(
          FakeDiaryRepository(dayResult: Right(dayWith(waterLoggedMl: 1250, waterTargetMl: 2640))),
        ),
      );
      await settle(tester);

      // The card carries the figure and the drop icon; the word was dropped for compactness.
      expect(find.text('1250 / 2640 ml'), findsOneWidget);
    });

    testWidgets('nothing drunk yet reads as zero of the goal, not as a missing row', (
      tester,
    ) async {
      await tester.pumpWidget(
        homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith(waterTargetMl: 2640)))),
      );
      await settle(tester);

      // Zero IS the truth here, unlike "burned": the user has drunk nothing today and we know it,
      // because the goal exists and the count starts at nought.
      expect(find.text('0 / 2640 ml'), findsOneWidget);
    });

    testWidgets('with no plan there is no goal, so the row stays away', (tester) async {
      await tester.pumpWidget(homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith()))));
      await settle(tester);

      // "1200 ml" against nothing says nothing, and a target of zero would say "drink nothing".
      expect(find.text('Water'), findsNothing);
    });
  });

  /// D-97. Rule 10: the source travels with the number, so someone can tell a figure their phone
  /// reported from one they typed — only the second is theirs to argue with.
  group('a step count says where it came from', () {
    testWidgets('a synced count names the platform', (tester) async {
      await tester.pumpWidget(
        homeUnderTest(
          FakeDiaryRepository(
            dayResult: Right(dayWith(steps: 9500, stepsSource: MeasurementSource.appleHealth)),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('9500'), findsOneWidget);
      expect(find.textContaining('Apple Health'), findsOneWidget);
    });

    testWidgets('a typed count says so instead of implying a device', (tester) async {
      await tester.pumpWidget(
        homeUnderTest(FakeDiaryRepository(dayResult: Right(dayWith(steps: 8000)))),
      );
      await settle(tester);

      expect(find.textContaining('you entered'), findsOneWidget);
      expect(find.textContaining('Apple Health'), findsNothing);
    });
  });

  /// D-128. The diary was readable for the current day only, so everything logged before 04:00 this
  /// morning became unreachable the moment the boundary passed. Tracking needs yesterday.
  group('day by day (D-128)', () {
    testWidgets('opening the diary asks for today, and today is not a date the client spells out', (
      tester,
    ) async {
      final repo = FakeDiaryRepository();
      await tester.pumpWidget(homeUnderTest(repo));
      await tester.pumpAndSettle();

      // Null, not a formatted date: the SERVER resolves "today" against the 04:00 boundary, and a
      // client that spells it out has guessed where the day begins (rule 8).
      expect(repo.dayDatesAsked, [null]);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the back arrow asks the server for the day before', (tester) async {
      final repo = FakeDiaryRepository();
      await tester.pumpWidget(homeUnderTest(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Earlier day'));
      await tester.pumpAndSettle();

      expect(repo.dayDatesAsked.last, isNotNull);
      expect(find.text('Yesterday'), findsOneWidget);
      // The `+` still writes to today wherever the user is standing, so the page says so.
      expect(find.textContaining('past day'), findsOneWidget);
    });

    testWidgets('there is no diary for tomorrow, so the forward arrow is dead on today', (
      tester,
    ) async {
      await tester.pumpWidget(homeUnderTest(FakeDiaryRepository()));
      await tester.pumpAndSettle();

      final later = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip('Later day'), matching: find.byType(IconButton)),
      );
      expect(later.onPressed, isNull);
    });
  });
}
