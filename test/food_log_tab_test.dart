import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log_tab.dart';

import 'fakes.dart';

const paneer = Food(
  id: 'f1',
  name: 'Paneer',
  nameHi: 'पनीर',
  kcalPer100g: 293,
  measures: [HouseholdMeasure(label: 'katori', grams: 100, isDefault: true)],
);

Widget tabUnderTest(DiaryRepository repo) {
  Get
    ..reset()
    ..put<DiaryRepository>(repo, permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: FoodLogTab()),
  );
}

void main() {
  testWidgets('typing searches and shows results the user can tap', (tester) async {
    await tester.pumpWidget(tabUnderTest(FakeDiaryRepository(foods: const [paneer])));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pan');
    // The search is debounced so a five-letter word is one request, not five.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Paneer'), findsOneWidget);
    expect(find.text('293 kcal / 100 g'), findsOneWidget);
  });

  /// D-121: the tab opens on the table, pages as you scroll, and filters on the server.
  List<Food> fixture(int count) => [
    for (var i = 0; i < count; i++)
      Food(
        id: 'f$i',
        name: 'Food ${i.toString().padLeft(2, '0')}',
        kcalPer100g: 100 + i.toDouble(),
        measures: const [],
      ),
  ];

  testWidgets('opens on a first page rather than an empty box', (tester) async {
    final repo = FakeDiaryRepository(foods: fixture(50));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    // Someone who opened "add food" has already decided to add food. Twenty rows, unasked.
    expect(repo.searchCalls.single, (
      query: '',
      limit: 20,
      offset: 0,
      suitableFor: null,
      groups: null,
    ));
    expect(find.text('Food 00'), findsOneWidget);
    expect(find.text('Food 19'), findsNothing, reason: 'below the fold, but built');
  });

  testWidgets('the quick-add shelf is the head of the page, not a second copy of it', (
    tester,
  ) async {
    await tester.pumpWidget(tabUnderTest(FakeDiaryRepository(foods: fixture(50))));
    await tester.pumpAndSettle();

    expect(find.text('Quick adds'), findsOneWidget);
    // The first four are the tiles; the list under them starts at the fifth, so no food is drawn
    // twice and the shelf costs no extra request.
    expect(find.text('Food 00'), findsOneWidget);
    expect(find.text('Food 03'), findsOneWidget);
  });

  testWidgets('a search replaces the shelf with its answers', (tester) async {
    await tester.pumpWidget(tabUnderTest(FakeDiaryRepository(foods: fixture(50))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Food 07');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // A shelf of unrelated foods above the answer is in the way of the answer.
    expect(find.text('Quick adds'), findsNothing);
    expect(find.text('107 kcal / 100 g'), findsOneWidget);
  });

  testWidgets('a category filters on the server, from the first page again', (tester) async {
    final repo = FakeDiaryRepository(foods: fixture(50));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetarian').last);
    await tester.pumpAndSettle();

    // The wire value, not the label — and from offset zero, because a different category is a
    // different list rather than more of this one.
    expect(repo.searchCalls.last, (
      query: '',
      limit: 20,
      offset: 0,
      suitableFor: 'veg',
      groups: null,
    ));
    // And the pill says what is showing, so the user can tell a filtered list from the table.
    expect(find.text('Vegetarian'), findsOneWidget);
  });

  testWidgets('paging keeps the category, so page two matches page one', (tester) async {
    final repo = FakeDiaryRepository(foods: fixture(50));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegan').last);
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();

    // However far the fling paged, every request after the pill was set carries the category —
    // a page two of the whole table under a filtered page one is the bug this guards.
    final paged = repo.searchCalls.where((c) => c.offset > 0);
    expect(paged, isNotEmpty);
    expect(paged.every((c) => c.suitableFor == 'vegan'), isTrue);
  });

  testWidgets('scrolling to the end asks for the next page, once', (tester) async {
    final repo = FakeDiaryRepository(foods: fixture(50));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();

    // The offset is where the rows already held END — not a page number, which drifts the moment
    // a response is short.
    expect(repo.searchCalls.map((c) => c.offset), containsAllInOrder([0, 20]));
    // Asserted through the repository rather than by hunting for a row: which of page two is on
    // screen depends on where the fling stopped, and that is the test's business, not the app's.
    expect(repo.searchCalls.last.limit, 20);
  });

  testWidgets('a short page is the last page, so scrolling stops asking', (tester) async {
    // 25 rows: a full page, then five. The five say "no more" without a third request.
    final repo = FakeDiaryRepository(foods: fixture(25));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
      await tester.pumpAndSettle();
    }

    expect(repo.searchCalls.length, 2, reason: 'two pages, and no polling at the bottom');
  });

  testWidgets('searching filters on the server, from the first page again', (tester) async {
    final repo = FakeDiaryRepository(foods: fixture(50));
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Food 07');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The query goes to the server — the app does not filter rows it happens to be holding, which
    // would only ever search the pages already fetched.
    expect(repo.searchCalls.last, (
      query: 'Food 07',
      limit: 20,
      offset: 0,
      suitableFor: null,
      groups: null,
    ));
    // The row, by its energy line — the name itself also appears in the search box the user just
    // typed it into.
    expect(find.text('107 kcal / 100 g'), findsOneWidget);
    expect(find.text('Food 00'), findsNothing, reason: 'and the old rows are replaced, not added');
  });

  testWidgets('debounce collapses fast typing into one search', (tester) async {
    final repo = CountingDiaryRepository(foods: const [paneer]);
    await tester.pumpWidget(tabUnderTest(repo));
    await tester.pumpAndSettle();

    // The tab now fetches a first page on open (D-121), so the assertion is on the DELTA. Counting
    // absolute requests would have to be rewritten every time the opening behaviour changes, and
    // what this test is about is typing, not opening.
    final onOpen = repo.searches;

    for (final text in ['p', 'pa', 'pan', 'pane', 'paneer']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // docs/18 treats bandwidth as a real cost — five keystrokes must not be five requests.
    expect(repo.searches - onOpen, 1);
  });

  testWidgets('an empty result set says so rather than showing a blank list', (tester) async {
    await tester.pumpWidget(tabUnderTest(FakeDiaryRepository()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No foods found.'), findsOneWidget);
  });

  testWidgets('a search failure shows the server message', (tester) async {
    await tester.pumpWidget(
      tabUnderTest(
        FakeDiaryRepository(
          failure: const ApiFailure('Search is unavailable right now.', code: 'X', status: 500),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dal');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Search is unavailable right now.'), findsOneWidget);
  });

  /// D-238. The add sheet shows what the portion gives — the server's figures — and sends exactly
  /// the portion the user picked.
  group('the add sheet (D-238)', () {
    const dal = Food(
      id: 'dal',
      name: 'Dal tadka',
      kcalPer100g: 116,
      proteinPer100g: 6.8,
      carbPer100g: 16.2,
      fatPer100g: 2.9,
      measures: [HouseholdMeasure(label: 'katori', grams: 150, isDefault: true)],
    );
    const salt = Food(id: 'salt', name: 'Rock salt', kcalPer100g: 0, measures: []);

    /// The food is opened from the quick-add shelf: with one food it is the only tile there is.
    Future<FakeDiaryRepository> openSheetFor(WidgetTester tester, Food food) async {
      final repo = FakeDiaryRepository(foods: [food]);
      await tester.pumpWidget(tabUnderTest(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(food.name));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets(
      "should show each row's carbs, protein and fat per 100 g when the server sent them",
      (tester) async {
        await tester.pumpWidget(tabUnderTest(FakeDiaryRepository(foods: [...fixture(4), dal])));
        await tester.pumpAndSettle();

        expect(find.text('C 16g'), findsOneWidget);
        expect(find.text('P 7g'), findsOneWidget);
        expect(find.text('F 3g'), findsOneWidget);
      },
    );

    testWidgets('should filter by food group on the server when a chip is tapped', (tester) async {
      final repo = FakeDiaryRepository(foods: fixture(50));
      await tester.pumpWidget(tabUnderTest(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Protein'));
      await tester.pumpAndSettle();

      expect(repo.searchCalls.last.groups, ['pulse', 'meat', 'fish', 'egg']);
      expect(repo.searchCalls.last.offset, 0);
      // A filtered list is a list of answers; the shelf of unrelated foods goes.
      expect(find.text('Quick adds'), findsNothing);
    });

    testWidgets("should show the server's nutrients for the portion when the sheet opens", (
      tester,
    ) async {
      final repo = await openSheetFor(tester, dal);

      expect(repo.previewCalls.single, (
        foodId: 'dal',
        measure: 'katori',
        measureCount: 1.0,
        quantityG: null,
      ));
      expect(find.text('483'), findsOneWidget, reason: 'kcal, rounded to a whole number');
      expect(find.text('Fibre'), findsOneWidget);
      expect(find.text('6.2 g'), findsOneWidget);
      expect(find.text('Sodium'), findsOneWidget);
      expect(find.text('656 mg'), findsOneWidget);
      expect(find.text('Saturated fat'), findsOneWidget);
    });

    testWidgets('should ask the server again when the portion changes', (tester) async {
      final repo = await openSheetFor(tester, dal);

      await tester.tap(find.byTooltip('More'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Never scaled on the phone (rule 2): one more half-katori is a new question to the server.
      expect(repo.previewCalls.last.measureCount, 1.5);
      expect(find.text('1.5 × katori'), findsOneWidget);
    });

    testWidgets('should log the meal and portion the user picked', (tester) async {
      final repo = await openSheetFor(tester, dal);

      await tester.tap(find.text('Dinner'));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, 'Add to Dinner');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(repo.loggedCalls.single, (
        slot: 'dinner',
        foodId: 'dal',
        measure: 'katori',
        measureCount: 1.5,
        quantityG: null,
        source: null,
      ));
      expect(find.text('Added to Dinner'), findsOneWidget);
    });

    testWidgets('should undo the entry it just logged', (tester) async {
      final repo = await openSheetFor(tester, dal);

      // The meal is picked, not left to the clock-based default, so the test runs the same at noon
      // and at midnight.
      await tester.tap(find.text('Dinner'));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, 'Add to Dinner');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(repo.removedIds, ['1']);
    });

    testWidgets('should start a food with no household measure at 100 g, not 1 g', (tester) async {
      final repo = await openSheetFor(tester, salt);

      expect(find.text('100 g'), findsOneWidget);
      expect(repo.previewCalls.single.quantityG, 100);
      expect(repo.previewCalls.single.measure, isNull);
    });

    testWidgets('should survive 200 % font scale (rule 12)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openSheetFor(tester, dal);

      expect(tester.takeException(), isNull);
    });
  });
}
