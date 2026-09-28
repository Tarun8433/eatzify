import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/cube_transition.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/features/account/profile_frame.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/client_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:health_pro/presentation/shell/walking_man.dart';

import 'fakes.dart';
import 'pumping.dart';

/// D-56. The shell's own walker — the one that travels between tabs. Home's hero walker (D-55) is
/// a different instance and is covered by `home_page_test.dart`.
Widget shellUnderTest({bool reducedMotion = false}) {
  Get
    ..reset()
    ..put(NavController(), permanent: true)
    ..put<ProfileRepository>(FakeProfileRepository(), permanent: true)
    ..put<MeasurementsRepository>(FakeMeasurementsRepository(), permanent: true)
    ..put<DiaryRepository>(FakeDiaryRepository(), permanent: true)
    ..put<PlanRepository>(FakePlanRepository(plan: samplePlan), permanent: true);
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ClientShell(),
    ),
  );
}

/// The slide that carries the You sheet, found by key — the Scaffold, the nav bar and the FAB all
/// contribute `FractionalTranslation`s of their own, every one of them sitting at zero.
FractionalTranslation _youSlide(WidgetTester tester) =>
    tester.widget<FractionalTranslation>(find.byKey(ClientShell.youSlideKey));

Finder navTab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder travellingWalker() =>
    find.descendant(of: find.byType(WalkingMan), matching: find.byType(FrameSequence));

/// Home's stage art (D-138) — the podium the walker stands on.
Finder homeStage() => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.contains('dashboard_stage'),
);

/// Which walker frame is on screen.
String walkerFrame(WidgetTester tester) =>
    (tester
                .widget<Image>(
                  find.descendant(of: find.byType(WalkingMan), matching: find.byType(Image)),
                )
                .image
            as AssetImage)
        .assetName;

/// Where the travelling walker is standing right now, in the shell body's own coordinates.
Rect walkerRect(WidgetTester tester) =>
    tester.getRect(travellingWalker()).shift(-tester.getTopLeft(find.byType(WalkingMan)));

/// Where he should be standing on [tab] — from `WalkingMan` itself, so the test checks that the
/// layout follows the anchor rather than re-deriving the anchor and checking it against itself.
Rect anchorRect(WidgetTester tester, ClientTab tab) =>
    WalkingMan.boundsAt(tester.getSize(find.byType(WalkingMan)), tab);

void main() {
  group('the walker travels with the tabs', () {
    testWidgets('the stage podium is under his feet, not his waist (D-63, D-138)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      // The bug this guards: the old rings laid out inside Home's list while he was positioned
      // against the body, so the two agreed on paper and were 160 pt apart on screen. The stage
      // replaced the rings (D-138); its podium SURFACE — 86 % of the way down the art, the
      // constant `_Stage` positions by — must sit exactly at his feet.
      final man = tester.getRect(travellingWalker());
      final stage = tester.getRect(homeStage());
      expect(stage.center.dx, moreOrLessEquals(man.center.dx, epsilon: 0.5));
      expect(stage.top + stage.height * 0.86, moreOrLessEquals(man.bottom, epsilon: 0.5));
    });

    testWidgets('the You frame is painted IN FRONT of the walker (D-68)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      await tester.tap(navTab('You'));
      await settle(tester);

      expect(find.byType(ProfileFrame), findsOneWidget);

      // Later siblings in a Stack paint on top, and the element tree is walked in child order — so
      // the frame coming after the walker is exactly what "in front of him" means. Behind him, the
      // hole was decoration he stood over with his whole body drawn on top of the card.
      final order = tester.allElements.toList();
      final walker = order.indexWhere((e) => e.widget is WalkingMan);
      final frame = order.indexWhere((e) => e.widget is ProfileFrame);

      expect(walker, isNonNegative);
      expect(frame, greaterThan(walker), reason: 'the panel must cover him, not sit under him');
    });

    testWidgets('the frame belongs to You alone, not to every tab', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      // A panel left hanging over Home would be worse than no frame at all.
      expect(find.byType(ProfileFrame), findsNothing);
    });

    testWidgets('there is exactly one walker, on every tab (D-60)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      // Two instances handed off at a tab boundary is what made Home→Plan and Progress→You
      // cross-fade between figures of different sizes. One cannot be handed off.
      for (final tab in ['Home', 'You']) {
        await tester.tap(navTab(tab));
        await settle(tester);
        expect(travellingWalker(), findsOneWidget, reason: '$tab must show the one walker');
        expect(find.byType(FrameSequence), findsOneWidget, reason: '$tab must show only that one');
      }
    });

    testWidgets('You draws the frame around him, not a second figure (D-59)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('You'));
      await settle(tester);

      expect(find.byType(ProfileFrame), findsOneWidget);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.you)));
    });

    testWidgets('he keeps walking — he never stops on a frame (D-58)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      final frames = <String>{};
      for (var i = 0; i < 8; i++) {
        frames.add(walkerFrame(tester));
        await tester.pump(const Duration(milliseconds: 160));
      }
      expect(frames.length, greaterThan(4), reason: 'a stride, not a still');

      // Well past where the old six-cycle walk ended (D-55): still moving.
      await tester.pump(const Duration(seconds: 12));
      final stillGoing = walkerFrame(tester);
      await tester.pump(const Duration(milliseconds: 160));
      expect(walkerFrame(tester), isNot(stillGoing));
    });

    testWidgets('reduced motion holds him on a single frame', (tester) async {
      await tester.pumpWidget(shellUnderTest(reducedMotion: true));
      await tester.pump();
      await tester.pump();

      expect(walkerFrame(tester), AppAssets.walkFrame(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(walkerFrame(tester), AppAssets.walkFrame(0));
    });

    testWidgets('changing tab does not restart his stride (D-60)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      final before = tester.state(find.byType(FrameSequence));
      // Home→You: the route he stays on screen for. Leaving for Plan unmounts him on purpose
      // (D-74), and a figure that is gone has no stride to keep.
      await tester.tap(navTab('You'));
      await settle(tester);

      // Same State object: the sequence was never rebuilt, so he did not break step on arrival.
      expect(tester.state(find.byType(FrameSequence)), same(before));
    });

    testWidgets('Plan and Progress walk him off the bottom, and he stops there (D-74)', (
      tester,
    ) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      for (final tab in ['Plan', 'Progress']) {
        await tester.tap(navTab(tab));
        await settle(tester);

        // Gone, not parked in a corner: those tabs are lists with nowhere for him to stand, and an
        // invisible figure that keeps ticking is a timer nobody can see.
        expect(travellingWalker(), findsNothing, reason: '$tab must not show him');
        expect(find.byType(FrameSequence), findsNothing, reason: 'and his stride must stop');
      }
    });

    testWidgets('leaving Home he descends — he does not fade or jump', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      final home = walkerRect(tester);

      await tester.tap(navTab('Plan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final midway = walkerRect(tester);
      expect(midway.top, greaterThan(home.top), reason: 'he must be on his way down');
      expect(midway.left, moreOrLessEquals(home.left, epsilon: 0.5), reason: 'straight down');
    });

    testWidgets('coming back from Plan he walks in from the TOP (D-74)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      await tester.tap(navTab('Plan'));
      await settle(tester);

      await tester.tap(navTab('Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final arriving = walkerRect(tester);
      final home = anchorRect(tester, ClientTab.home);
      expect(arriving.top, lessThan(home.top), reason: 'still above where he ends up');

      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(home));
    });

    testWidgets('Home to You keeps him on screen the whole way (D-74)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('You'));
      // Sampled across the change: going by way of Plan's and Progress's anchors would dive him off
      // the bottom and bring him back, which is not what a direct move should look like.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(travellingWalker(), findsOneWidget, reason: 'he must never leave on this route');
      }

      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.you)));
    });

    testWidgets('the two tabs that show him stand him somewhere else', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.home)));

      await tester.tap(navTab('You'));
      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.you)));

      expect(
        anchorRect(tester, ClientTab.home),
        isNot(anchorRect(tester, ClientTab.you)),
        reason: 'the rings and the profile circle are not in the same place',
      );
    });

    testWidgets('he walks there rather than appearing there', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('You'));
      await tester.pump(); // start the turn
      await tester.pump(const Duration(milliseconds: 210)); // halfway

      final midway = walkerRect(tester);
      expect(
        midway,
        isNot(anchorRect(tester, ClientTab.you)),
        reason: 'halfway through he must still be in transit',
      );
      expect(midway, isNot(anchorRect(tester, ClientTab.home)));

      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.you)));
    });

    testWidgets('he never takes a tap meant for the page behind him', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('Plan'));
      await settle(tester);

      expect(
        find.descendant(of: find.byType(WalkingMan), matching: find.byType(IgnorePointer)),
        findsOneWidget,
      );
    });

    testWidgets('a second tap mid-walk retargets instead of snapping back', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('You'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final interrupted = walkerRect(tester);

      await tester.tap(navTab('Home'));
      await tester.pump();
      // The very next frame continues from where he stood, it does not jump back to an anchor he
      // had already left.
      expect(walkerRect(tester), rectMoreOrLessEquals(interrupted));

      await settle(tester);
      expect(walkerRect(tester), rectMoreOrLessEquals(anchorRect(tester, ClientTab.home)));
    });
  });

  group('the page turns like a cube face', () {
    testWidgets('mid-change one face is turning; at rest neither is', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      expect(find.byType(CubeTransition), findsNothing);

      await tester.tap(navTab('Progress'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CubeTransition), findsOneWidget);

      await settle(tester);
      expect(find.byType(CubeTransition), findsNothing);
      expect(find.text('Track your health journey'), findsOneWidget);
    });

    testWidgets('a new tab arrives from the TOP, not up from the bottom (D-69)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('Progress'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // First half of the change: the page being LEFT swings out. Positive turn hinges it on the
      // bottom edge and drops it away through the bottom, which is what leaves the top edge free
      // for the incoming page to arrive through.
      final leaving = tester.widget<CubeTransition>(find.byType(CubeTransition));
      expect(leaving.turn, greaterThan(0), reason: 'the old page must exit downward');

      // Second half: the page being OPENED comes in through the opposite edge, from above.
      await tester.pump(const Duration(milliseconds: 250));
      final arriving = tester.widget<CubeTransition>(find.byType(CubeTransition));
      expect(arriving.turn, lessThan(0), reason: 'the new page must arrive from the top');
    });

    testWidgets('the You sheet hides the walker under it (D-70)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      await tester.tap(navTab('You'));
      await settle(tester);

      expect(find.byType(ProfileFrame), findsOneWidget);

      // Later siblings in a Stack paint on top, and the element tree is walked in child order. The
      // You page must come AFTER the walker: its sheet is what covers him, leaving only the hole.
      final order = tester.allElements.toList();
      final walker = order.indexWhere((e) => e.widget is WalkingMan);
      final sheet = order.indexWhere((e) => e.widget is ProfileFrame);

      expect(walker, isNonNegative);
      expect(sheet, greaterThan(walker), reason: 'he stands behind the screen, not on top of it');
    });

    testWidgets('You comes DOWN from the top, over him — it never turns (D-71)', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);
      // From the neighbouring tab, so the whole change is You's arrival rather than the tail of a
      // longer walk: the sheet only enters over the last leg of his travel.
      await tester.tap(navTab('Progress'));
      await settle(tester);

      await tester.tap(navTab('You'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Mid-arrival it is offset upward — still partly off the top of the screen — and it slides
      // rather than rotating: a cube face shrinks in perspective while the walker does not, which
      // left him standing outside the edges of the page meant to be covering him.
      final slide = _youSlide(tester);
      expect(slide.translation.dy, lessThan(0), reason: 'it must still be above the screen');
      expect(slide.translation.dy, greaterThan(-1));
      expect(slide.translation.dx, 0, reason: 'from the top, not the side');

      await settle(tester);
      final landed = _youSlide(tester);
      expect(landed.translation.dy, 0, reason: 'it lands in place');
    });

    testWidgets('nothing turns while You is coming or going', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      await tester.tap(navTab('You'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // One page sliding while another rotates behind it reads as neither.
      expect(find.byType(CubeTransition), findsNothing);
    });

    testWidgets('every other tab still sits behind him', (tester) async {
      await tester.pumpWidget(shellUnderTest());
      await settle(tester);

      // Home draws the stage UNDER his feet, so that page must stay behind him.
      final order = tester.allElements.toList();
      final walker = order.indexWhere((e) => e.widget is WalkingMan);
      final stage = order.indexWhere(
        (e) =>
            e.widget is Image &&
            (e.widget as Image).image is AssetImage &&
            ((e.widget as Image).image as AssetImage).assetName.contains('dashboard_stage'),
      );

      expect(stage, isNonNegative);
      expect(walker, greaterThan(stage), reason: 'he walks on the stage, not under it');
    });

    testWidgets('reduced motion changes the tab without turning or travelling', (tester) async {
      await tester.pumpWidget(shellUnderTest(reducedMotion: true));
      await settle(tester);

      await tester.tap(navTab('Progress'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CubeTransition), findsNothing);
      expect(travellingWalker(), findsNothing, reason: 'Progress does not show him');
    });
  });

  group('where each tab puts him', () {
    test('every tab has an anchor, and only two of them show him', () {
      expect(WalkingMan.anchors, hasLength(ClientTab.values.length));
      expect(ClientTab.values.where(WalkingMan.showsWalker), [
        ClientTab.home,
        ClientTab.you,
      ], reason: 'Home draws his rings and You his circle; the other two are lists');
    });

    test('a settled tab is its own anchor', () {
      const body = Size(400, 800);
      for (final tab in [ClientTab.home, ClientTab.you]) {
        expect(
          WalkingMan.boundsAt(body, tab),
          WalkingMan.boundsIn(body, WalkingMan.anchorFor(tab), tab, 1, fromVisible: true),
          reason: tab.name,
        );
      }
    });

    test('leaving for Plan ends with him fully below the bottom edge', () {
      const body = Size(400, 800);
      final gone = WalkingMan.boundsIn(
        body,
        WalkingMan.anchorFor(ClientTab.home),
        ClientTab.plan,
        1,
        fromVisible: true,
      );
      expect(gone.top, greaterThanOrEqualTo(body.height));
    });

    test('arriving from Plan starts with him fully above the top edge', () {
      const body = Size(400, 800);
      final entering = WalkingMan.boundsIn(
        body,
        WalkingMan.anchorFor(ClientTab.plan),
        ClientTab.home,
        0,
        fromVisible: false,
      );
      expect(entering.bottom, lessThanOrEqualTo(0));
    });

    test('Home to You never leaves the body — it is not routed via the other anchors', () {
      const body = Size(400, 800);
      for (var i = 0; i <= 10; i++) {
        final rect = WalkingMan.boundsIn(
          body,
          WalkingMan.anchorFor(ClientTab.home),
          ClientTab.you,
          i / 10,
          fromVisible: true,
        );
        expect(rect.top, lessThan(body.height), reason: 't=${i / 10}');
        expect(rect.bottom, greaterThan(0), reason: 't=${i / 10}');
      }
    });

    test('Plan to Progress keeps him parked off the bottom', () {
      const body = Size(400, 800);
      for (final t in [0.0, 0.5, 1.0]) {
        final rect = WalkingMan.boundsIn(
          body,
          WalkingMan.anchorFor(ClientTab.plan),
          ClientTab.progress,
          t,
          fromVisible: false,
        );
        expect(rect.top, greaterThanOrEqualTo(body.height), reason: 't=$t');
      }
    });
  });
}
