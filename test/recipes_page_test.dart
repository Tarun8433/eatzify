import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/data/datasources/remote/recipes_remote_data_source.dart';
import 'package:health_pro/domain/entities/recipe.dart';
import 'package:health_pro/domain/repositories/recipe_repository.dart';
import 'package:health_pro/presentation/features/recipes/recipes_controller.dart';
import 'package:health_pro/presentation/features/recipes/recipes_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// D-263: the Plan tab's recipes — list, detail, and logging a serving.

class FakeRecipeRepository implements RecipeRepository {
  FakeRecipeRepository({this.recipes = const [], this.failure, this.logFailure});

  final List<Recipe> recipes;
  final Failure? failure;
  final Failure? logFailure;

  /// Holds the list open so a test can see the loading state.
  Completer<void>? hold;
  final slotsAsked = <String?>[];
  final logged = <({String id, String slot, double servings})>[];

  @override
  Future<Either<Failure, List<Recipe>>> list({String? slot}) async {
    slotsAsked.add(slot);
    await hold?.future;
    final failed = failure;
    if (failed != null) return Left(failed);
    return Right(recipes.where((r) => slot == null || r.slots.contains(slot)).toList());
  }

  @override
  Future<Either<Failure, Unit>> log({
    required String id,
    required String slot,
    required double servings,
  }) async {
    final failed = logFailure;
    if (failed != null) return Left(failed);
    logged.add((id: id, slot: slot, servings: servings));
    return const Right(unit);
  }
}

Recipe chilla() => recipeFromJson({
  'id': 'r1',
  'name': 'Moong dal chilla',
  'name_hi': null,
  'description': 'A savoury pancake',
  'steps': ['Soak the dal', 'Cook on a tawa'],
  'slots': ['breakfast'],
  'servings': 2,
  'suitable_for': ['veg', 'vegan'],
  'allergens': ['milk'],
  'per_serving': {
    'grams': 55,
    'kcal': 95.4,
    'protein_g': 5,
    'carb_g': 9,
    'fat_g': 2.2,
    'fibre_g': 1,
  },
  'ingredients': [
    {'food_id': 'f1', 'name': 'Moong dal', 'name_hi': null, 'grams': 100},
    {'food_id': 'f2', 'name': 'Oil', 'name_hi': null, 'grams': 10},
  ],
});

void main() {
  late FakeRecipeRepository repo;

  setUp(() => repo = FakeRecipeRepository());
  tearDown(Get.reset);

  Widget page({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put(RecipesController(recipes: repo));
    return GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: const RecipesPage(),
      ),
    );
  }

  group('the four states', () {
    testWidgets('should wait behind a skeleton while the list loads', (tester) async {
      repo.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);
      repo.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should say there are no recipes rather than show an empty list', (tester) async {
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No recipes yet'), findsOneWidget);
    });

    testWidgets('should render a failure with the server words and a retry', (tester) async {
      repo = FakeRecipeRepository(failure: const OfflineFailure('You are offline.'));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });

    testWidgets('should list each recipe with its kcal per serving', (tester) async {
      repo = FakeRecipeRepository(recipes: [chilla()]);
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Moong dal chilla'), findsOneWidget);
      expect(find.text('Per serving: 95 kcal'), findsOneWidget);
    });
  });

  testWidgets(
    'should ask the server for one meal when a chip is chosen, and offer to widen again',
    (tester) async {
      repo = FakeRecipeRepository(recipes: [chilla()]);
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Dinner'));
      await settle(tester);

      expect(repo.slotsAsked.last, 'dinner');
      expect(find.text('Show all meals'), findsOneWidget);

      await tester.tap(find.text('Show all meals'));
      await settle(tester);
      expect(repo.slotsAsked.last, isNull);
      expect(find.text('Moong dal chilla'), findsOneWidget);
    },
  );

  testWidgets('should show a recipe’s ingredients, method and allergens', (tester) async {
    repo = FakeRecipeRepository(recipes: [chilla()]);
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.text('Moong dal chilla'));
    await settle(tester);

    expect(find.text('95 kcal'), findsOneWidget);
    expect(find.text('Moong dal'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('Soak the dal'), findsOneWidget);
    expect(find.textContaining('Contains:'), findsOneWidget);
  });

  testWidgets('should log the chosen meal and servings and confirm it', (tester) async {
    repo = FakeRecipeRepository(recipes: [chilla()]);
    await tester.pumpWidget(page());
    await settle(tester);
    await tester.tap(find.text('Moong dal chilla'));
    await settle(tester);

    await tester.tap(find.text('Log this'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Lunch'));
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Log this').last);
    await settle(tester);

    expect(repo.logged, [(id: 'r1', slot: 'lunch', servings: 2.0)]);
    expect(find.text('Added to your diary'), findsOneWidget);
  });

  testWidgets('should keep the sheet open with the server words when logging fails', (
    tester,
  ) async {
    repo = FakeRecipeRepository(
      recipes: [chilla()],
      logFailure: const ApiFailure(
        'That recipe cannot be logged right now.',
        code: 'RECIPE_UNAVAILABLE',
        status: 409,
      ),
    );
    await tester.pumpWidget(page());
    await settle(tester);
    await tester.tap(find.text('Moong dal chilla'));
    await settle(tester);

    await tester.tap(find.text('Log this'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Log this').last);
    await settle(tester);

    expect(find.text('That recipe cannot be logged right now.'), findsOneWidget);
    expect(find.text('Added to your diary'), findsNothing);
  });

  testWidgets('should survive a 200 % text scale on the list and the recipe', (tester) async {
    repo = FakeRecipeRepository(recipes: [chilla()]);
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Moong dal chilla'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
