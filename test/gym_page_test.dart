import 'dart:async';

import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';
import 'package:health_pro/presentation/features/gym/exercise_browser.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_routines_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_settings_page.dart';
import 'package:health_pro/presentation/features/gym/gym_stats_controller.dart';
import 'package:health_pro/presentation/features/gym/gym_stats_tab.dart';
import 'package:health_pro/presentation/features/gym/gym_today_card.dart';
import 'package:health_pro/presentation/features/gym/gym_today_tab.dart';
import 'package:health_pro/presentation/features/gym/workout_controller.dart';
import 'package:health_pro/presentation/features/gym/workout_page.dart';

import 'gym_fakes.dart';
import 'pumping.dart';

late FakeGymRepository repo;

GymController putGym({FakeGymRepository? fake}) {
  repo = fake ?? FakeGymRepository();
  Get
    ..reset()
    ..put<GymRepository>(repo, permanent: true);
  return Get.put(GymController(gym: repo), permanent: true);
}

void main() {
  group('Gym Today tab: the four states', () {
    testWidgets('should show a skeleton while the plan loads', (tester) async {
      final gate = Completer<void>();
      putGym(fake: FakeGymRepository()..overviewGate = gate);
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await tester.pump();
      expect(find.byType(LoadingView), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.byType(LoadingView), findsNothing);
    });

    testWidgets("should show the server's message and retry when the plan fails", (tester) async {
      putGym(
        fake: FakeGymRepository(
          overviewResult: const Left(ApiFailure('Could not load your plan.', code: 'X')),
        ),
      );
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);
      expect(find.text('Could not load your plan.'), findsOneWidget);
      final before = repo.overviewCalls;
      await tester.tap(find.byType(FilledButton).first);
      await settle(tester);
      expect(repo.overviewCalls, greaterThan(before));
    });

    testWidgets("should show today's routine with Start and the workout energy", (tester) async {
      putGym();
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);
      expect(find.text('Push Day'), findsWidgets);
      expect(find.text('Start Workout'), findsOneWidget);
      expect(find.text('~240 kcal'), findsOneWidget);
      expect(find.text('~610 kcal'), findsOneWidget);
    });

    testWidgets("should draw the card artwork at the card's size, clear of the text", (
      tester,
    ) async {
      // Phone width: the card is narrowest here, and this is where artwork crowds the text.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      putGym();
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);

      final art = tester.getRect(find.byKey(const Key('gymTodayArt')));
      final start = tester.getRect(find.widgetWithText(FilledButton, 'Start Workout'));
      final screen = tester.getRect(find.byType(GymTodayTab));

      // Both failure modes seen on the device: an Image with no box of its own measures zero one
      // build and takes the bitmap's own 1536 px the next.
      expect(art.height, greaterThan(screen.height * 0.15), reason: 'artwork collapsed');
      expect(art.width, inInclusiveRange(screen.width * 0.3, screen.width * 0.45));
      expect(start.right, lessThanOrEqualTo(art.left), reason: 'action runs under the artwork');
    });

    testWidgets('should offer the starter plan when there is no plan yet', (tester) async {
      putGym(fake: FakeGymRepository(overviewResult: Right(sampleOverview(withPlan: false))));
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);
      expect(find.text('Build your training week'), findsOneWidget);
      await tester.tap(find.text('Load a starter plan'));
      await settle(tester);
      expect(repo.starterCalls, 1);
    });

    testWidgets('should offer any routine on a day with nothing planned', (tester) async {
      putGym(fake: FakeGymRepository(overviewResult: Right(sampleOverview(restToday: true))));
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);
      expect(find.text('Start Workout'), findsNothing);
      await tester.tap(find.text('Start a workout'));
      await settle(tester);
      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Push Day')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Freestyle workout')), findsOneWidget);
    });

    testWidgets('should say an estimate is not known rather than show a zero', (tester) async {
      putGym(
        fake: FakeGymRepository(overviewResult: Right(sampleOverview(totals: const GymTotals()))),
      );
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayTab())));
      await settle(tester);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('~0 kcal'), findsNothing);
    });

    testWidgets('should survive 200 % text in dark mode', (tester) async {
      putGym();
      await tester.pumpWidget(
        gymApp(const Scaffold(body: GymTodayTab()), scaler: const TextScaler.linear(2), dark: true),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('the exercise library', () {
    Future<void> pumpBrowser(WidgetTester tester) async {
      putGym();
      await tester.pumpWidget(gymApp(Scaffold(body: ExerciseBrowser(onTap: (_) {}))));
      await settle(tester);
    }

    testWidgets('should narrow by body part', (tester) async {
      await pumpBrowser(tester);
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      final legs = find.widgetWithText(ChoiceChip, 'Upper legs');
      await tester.ensureVisible(legs);
      await settle(tester);
      await tester.tap(legs);
      await settle(tester);
      expect(find.text('Barbell Full Squat'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsNothing);
    });

    testWidgets('should search names and say when nothing matches', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'push');
      await settle(tester);
      expect(find.text('Push-up'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await settle(tester);
      expect(find.text('No exercise matches'), findsOneWidget);
    });
  });

  group('the workout screen', () {
    Future<WorkoutController> pumpWorkout(
      WidgetTester tester, {
      TextScaler scaler = TextScaler.noScaling,
    }) async {
      final gym = putGym();
      await gym.load();
      final controller = Get.put(
        WorkoutController(
          gym: repo,
          feedback: SilentFeedback(),
          session: WorkoutSession.start(
            name: 'Push Day',
            plan: [benchEntry()],
            now: DateTime.now(),
            id: 'w-1',
          ),
          settings: const GymSettings(),
          restAlert: (title: 'Rest over', body: 'Next set'),
        ),
      );
      await tester.pumpWidget(gymApp(const WorkoutPage(), scaler: scaler));
      await tester.pump();
      return controller;
    }

    Future<void> close(WidgetTester tester) async {
      // Stops the controller's clock, so no timer outlives the test.
      await Get.delete<WorkoutController>(force: true);
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('should show the exercise, why today is heavier, and every set', (tester) async {
      await pumpWorkout(tester);
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Every rep last time — 2.5 kg more.'), findsOneWidget);
      expect(find.byTooltip('Mark set 1 done'), findsOneWidget);
      expect(find.byTooltip('Mark set 2 done'), findsOneWidget);
      await close(tester);
    });

    testWidgets(
      'should start the rest timer when a set is ticked and keep the phone copy current',
      (tester) async {
        final c = await pumpWorkout(tester);
        await tester.tap(find.byTooltip('Mark set 1 done'));
        await tester.pump();
        expect(c.session.value.doneSets, 1);
        expect(find.text('Skip'), findsOneWidget);
        expect(repo.active?.doneSets, 1);
        await tester.tap(find.text('Skip'));
        await tester.pump();
        expect(find.text('Skip'), findsNothing);
        await close(tester);
      },
    );

    testWidgets('should save the workout with the id it started with', (tester) async {
      final c = await pumpWorkout(tester);
      c.toggle(0, 0);
      final result = await c.finish();
      expect(result.detail?.summary.energyKcal, 120);
      expect(repo.saved.single.id, 'w-1');
      expect(repo.active, isNull);
      await close(tester);
    });

    testWidgets('should survive 200 % text', (tester) async {
      await pumpWorkout(tester, scaler: const TextScaler.linear(2));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  });

  group('Gym stats', () {
    testWidgets('should invite a first workout when there is no history', (tester) async {
      putGym();
      Get.put(GymStatsController(gym: repo));
      await tester.pumpWidget(gymApp(const Scaffold(body: GymStatsTab())));
      await settle(tester);
      expect(find.text('No workouts yet'), findsOneWidget);
    });

    testWidgets('should show the server message when stats fail', (tester) async {
      putGym(
        fake: FakeGymRepository(
          statsResult: const Left(ApiFailure('Stats are unavailable.', code: 'X')),
        ),
      );
      Get.put(GymStatsController(gym: repo));
      await tester.pumpWidget(gymApp(const Scaffold(body: GymStatsTab())));
      await settle(tester);
      expect(find.text('Stats are unavailable.'), findsOneWidget);
    });
  });

  group('the plan and settings screens', () {
    testWidgets('should render the weekly schedule and routines with no framework complaint', (
      tester,
    ) async {
      await putGym().load();
      await tester.pumpWidget(gymApp(const Scaffold(body: GymRoutinesTab())));
      await settle(tester);
      expect(find.text('Weekly schedule'), findsOneWidget);
      expect(find.text('Push Day'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should render gym settings with no framework complaint', (tester) async {
      await putGym().load();
      await tester.pumpWidget(gymApp(const GymSettingsPage()));
      await settle(tester);
      expect(find.text('Rest timer'), findsOneWidget);
      expect(find.text('Effort per set'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('reloading from a build (the bug reported from the simulator)', () {
    testWidgets(
      'should not mark the mounted Home card dirty mid-build when a page reloads a failed plan',
      (tester) async {
        final c = putGym(
          fake: FakeGymRepository(overviewResult: const Left(OfflineFailure('No connection.'))),
        );
        // The card is mounted and listening; a DIFFERENT subtree then rebuilds and inflates a page
        // that reloads in initState — exactly a route push over Home.
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await tester.pumpWidget(
          gymApp(
            Scaffold(
              body: Column(
                children: [
                  const GymTodayCard(),
                  ValueListenableBuilder<bool>(
                    valueListenable: open,
                    builder: (_, on, _) => on ? const _ReloadsInInitState() : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        );
        await settle(tester);
        expect(c.ready, isNull);

        open.value = true;
        await settle(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group("Home's workout card", () {
    testWidgets("should offer Start on today's routine", (tester) async {
      await putGym().load();
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayCard())));
      await settle(tester);
      expect(find.text("Today's workout"), findsOneWidget);
      expect(find.text('Push Day'), findsOneWidget);
      expect(find.text('Start Workout'), findsOneWidget);
    });

    testWidgets('should survive 200 % text in dark mode (rule 12)', (tester) async {
      await putGym().load();
      await tester.pumpWidget(
        gymApp(
          const Scaffold(body: GymTodayCard()),
          scaler: const TextScaler.linear(2),
          dark: true,
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Start Workout'), findsOneWidget);
    });

    testWidgets('should draw nothing where no Gym is registered', (tester) async {
      Get.reset();
      await tester.pumpWidget(gymApp(const Scaffold(body: GymTodayCard())));
      expect(find.text("Today's workout"), findsNothing);
    });
  });
}

class _ReloadsInInitState extends StatefulWidget {
  const _ReloadsInInitState();

  @override
  State<_ReloadsInInitState> createState() => _ReloadsInInitStateState();
}

class _ReloadsInInitStateState extends State<_ReloadsInInitState> {
  @override
  void initState() {
    super.initState();
    Get.find<GymController>().load(quietly: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
