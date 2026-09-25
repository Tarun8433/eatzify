import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/app_notification.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/entities/plan.dart';
import 'package:health_pro/domain/entities/privacy.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';

/// Stands in for the profile endpoints so widgets can be driven without a dio.
///
/// Defaults to a completed profile, because that is the state most screens are built for. Pass
/// `profileResult` to exercise Empty (`Right(null)`) or Failed (`Left(...)`).
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.result,
    this.failure,
    this.profileResult,
    this.patchFailure,
    this.roleNames = const [],
    this.rolesFailure,
  });

  /// What `GET /auth/me` reports for this account. Empty means a plain client, which is what
  /// every test that is not about the coach shell wants. Mutable, so a test can do what an admin
  /// does — grant the role while the app is already open — and check the app notices.
  List<String> roleNames;

  /// When set, `GET /auth/me` refuses — the shell has to fall back to the client tabs.
  final Failure? rolesFailure;

  @override
  Future<Either<Failure, List<String>>> roles() async {
    final failure = rolesFailure;
    return failure != null ? Left(failure) : Right(roleNames);
  }

  final OnboardingResult? result;
  final Failure? failure;
  final Either<Failure, ProfileView?>? profileResult;
  final Failure? patchFailure;

  OnboardingSubmission? lastSubmission;
  Map<String, dynamic>? lastProfilePatch;
  Map<String, dynamic>? lastHealthPatch;
  String? uploadedPhotoName;
  bool photoRemoved = false;

  @override
  Future<Either<Failure, OnboardingResult>> submitOnboarding(OnboardingSubmission body) async {
    lastSubmission = body;
    if (failure != null) return Left(failure!);
    return Right(result ?? const OnboardingResult(userId: '1', healthProfileVersion: 1, gates: []));
  }

  /// How many times the screen asked for the profile. Pull-to-refresh is only a refresh if it
  /// actually re-fetches.
  int profileCalls = 0;

  @override
  Future<Either<Failure, ProfileView?>> profile() async {
    profileCalls++;
    return profileResult ?? const Right(defaultProfile);
  }

  @override
  Future<Either<Failure, Unit>> updateProfile(Map<String, dynamic> changed) async {
    lastProfilePatch = changed;
    if (patchFailure != null) return Left(patchFailure!);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateHealth(Map<String, dynamic> changed) async {
    lastHealthPatch = changed;
    if (patchFailure != null) return Left(patchFailure!);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, String>> uploadPhoto(String filePath, String fileName) async {
    uploadedPhotoName = fileName;
    if (patchFailure != null) return Left(patchFailure!);
    return const Right('http://example.test/photo.jpg');
  }

  @override
  Future<Either<Failure, Unit>> removePhoto() async {
    photoRemoved = true;
    if (patchFailure != null) return Left(patchFailure!);
    return const Right(unit);
  }
}

const defaultProfile = ProfileView(
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
);

/// Stands in for the measurement endpoints. Defaults to a short, unremarkable weight history.
class FakeMeasurementsRepository implements MeasurementsRepository {
  FakeMeasurementsRepository({this.historyResult, this.isSuspect = false, this.failure});

  final Either<Failure, MeasurementHistory>? historyResult;
  final bool isSuspect;
  final Failure? failure;

  double? lastRecorded;
  String? lastKind;

  /// What the last call claimed as its origin. Recorded so a test can prove a hand-entry screen
  /// sends `manual` — the server's conflict rule (D-97) turns on this value, so a screen that
  /// mislabels itself would quietly stop being able to correct a synced figure.
  MeasurementSource? lastSource;

  /// When the caller said the reading was taken, or null for "now".
  DateTime? lastAt;

  @override
  Future<Either<Failure, ({Measurement measurement, bool isSuspect})>> record({
    required String kind,
    required double value,
    required String unit,
    MeasurementSource source = MeasurementSource.manual,
    DateTime? at,
  }) async {
    lastRecorded = value;
    lastKind = kind;
    lastSource = source;
    lastAt = at;
    if (failure != null) return Left(failure!);
    return Right((
      measurement: Measurement(
        id: '1',
        kind: kind,
        value: value,
        unit: unit,
        diaryDate: '2026-08-25',
        isSuspect: isSuspect,
        source: source,
      ),
      isSuspect: isSuspect,
    ));
  }

  /// Every bulk write, in order. A sync test reads what was sent from here.
  final batches = <List<NewMeasurement>>[];

  @override
  Future<Either<Failure, Unit>> recordMany(List<NewMeasurement> readings) async {
    batches.add(readings);
    if (failure != null) return Left(failure!);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, MeasurementHistory>> history(String kind) async =>
      historyResult ?? Right(defaultHistory);
}

final defaultHistory = MeasurementHistory(
  kind: 'weight',
  change: -0.4,
  points: [
    for (var i = 0; i < 4; i++)
      Measurement(
        id: '$i',
        kind: 'weight',
        value: 75 - i * 0.2,
        unit: 'kg',
        diaryDate: '2026-08-2${i + 1}',
        isSuspect: false,
      ),
  ],
);

/// Stands in for the diary endpoints.
class FakeDiaryRepository implements DiaryRepository {
  FakeDiaryRepository({this.dayResult, this.foods = const [], this.failure, this.delay});

  /// Holds the day open so a test can see the LOADING state. Without it the future completes on
  /// the first microtask and the skeleton is gone before any frame can be inspected.

  final Either<Failure, DiaryDay>? dayResult;
  final List<Food> foods;
  final Failure? failure;
  final Duration? delay;

  String? lastLoggedFoodId;

  /// Every `logFood` call, so a test can assert the portion the sheet sent — not just that
  /// something was logged.
  final loggedCalls =
      <
        ({
          String slot,
          String foodId,
          String? measure,
          double? measureCount,
          double? quantityG,
          String? source,
        })
      >[];

  /// Every `previewFood` call. A portion change must re-ask the server rather than scale locally.
  final previewCalls =
      <({String foodId, String? measure, double? measureCount, double? quantityG})>[];

  /// What the preview answers. The fixed figures make the micronutrient rows assertable.
  Either<Failure, NutritionPreview> previewResult = const Right(
    NutritionPreview(
      grams: 160,
      kcal: 483.2,
      proteinG: 10.2,
      carbG: 64.2,
      fatG: 20.5,
      fibreG: 6.2,
      sodiumMg: 656,
      addedSugarG: 0,
      saturatedFatG: 6.7,
    ),
  );

  @override
  Future<Either<Failure, NutritionPreview>> previewFood({
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
  }) async {
    previewCalls.add((
      foodId: foodId,
      measure: measure,
      measureCount: measureCount,
      quantityG: quantityG,
    ));
    return previewResult;
  }

  /// Ids `remove` was called with — the snackbar's Undo.
  final removedIds = <String>[];

  /// Every request this fake was asked for, so a paging test can assert the offsets rather than
  /// only the rows that came back.
  final searchCalls =
      <({String query, int limit, int offset, String? suitableFor, List<String>? groups})>[];

  @override
  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit = 20,
    int offset = 0,
    String? suitableFor,
    List<String>? groups,
  }) async {
    searchCalls.add((
      query: query,
      limit: limit,
      offset: offset,
      suitableFor: suitableFor,
      groups: groups,
    ));
    if (failure != null) return Left(failure!);
    // Pages the fixture the way the server does, so "a short page is the last page" is exercised
    // here rather than only against a real database.
    final matched = query.isEmpty
        ? foods
        : foods.where((f) => f.name.toLowerCase().contains(query.toLowerCase())).toList();
    if (offset >= matched.length) return const Right([]);
    return Right(matched.skip(offset).take(limit).toList());
  }

  @override
  Future<Either<Failure, LogEntry>> logFood({
    required String slot,
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
    String? source,
  }) async {
    lastLoggedFoodId = foodId;
    loggedCalls.add((
      slot: slot,
      foodId: foodId,
      measure: measure,
      measureCount: measureCount,
      quantityG: quantityG,
      source: source,
    ));
    if (failure != null) return Left(failure!);
    return Right(
      LogEntry(
        id: '1',
        slot: slot,
        name: 'Logged',
        quantityG: quantityG ?? 150,
        kcal: 116,
        locked: false,
        measureLabel: measure,
      ),
    );
  }

  /// Every `date` argument `day()` was called with, in order. Null is today.
  final dayDatesAsked = <String?>[];

  @override
  Future<Either<Failure, DiaryDay>> day({String? date}) async {
    // Which day was asked for, so a test can assert the app browses rather than re-reads today.
    dayDatesAsked.add(date);
    final held = delay;
    if (held != null) await Future<void>.delayed(held);
    return dayResult ?? const Right(emptyDay);
  }

  /// What `GET /logs/windows` answers. Null is a server that could not be reached.
  List<DiaryWindow>? windowsResult;

  @override
  Future<Either<Failure, List<DiaryWindow>>> windows(int days) async {
    final result = windowsResult;
    return result == null ? const Left(OfflineFailure('offline')) : Right(result);
  }

  @override
  Future<Either<Failure, Unit>> remove(String id) async {
    removedIds.add(id);
    return const Right(unit);
  }
}

const emptyDay = DiaryDay(
  diaryDate: '2026-08-25',
  entries: [],
  totals: Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
  targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
);

/// Counts searches so the debounce can be asserted.
class CountingDiaryRepository extends FakeDiaryRepository {
  CountingDiaryRepository({super.foods});

  int searches = 0;

  @override
  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit = 20,
    int offset = 0,
    String? suitableFor,
    List<String>? groups,
  }) {
    searches++;
    return super.searchFoods(
      query,
      limit: limit,
      offset: offset,
      suitableFor: suitableFor,
      groups: groups,
    );
  }
}

/// Stands in for the two billing endpoints that exist (D-136). The tier is the whole point:
/// premium surfaces render only when the server says FREE.
class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository({
    this.tier = 'FREE',
    this.priceRows,
    this.priceFailure,
    this.paymentsMode = 'stub',
    this.checkoutFailure,
  });

  final String tier;

  /// `stub` by default, matching a build with no Cashfree credentials — the paywall then draws its
  /// "opening soon" note rather than a live pay button.
  final String paymentsMode;

  /// When set, `POST /billing/checkout` refuses.
  final Failure? checkoutFailure;

  /// What the fake was asked to buy, so a test can tell "the sheet sent it" from "the sheet
  /// redrew itself".
  final List<({String tier, int months})> bought = [];

  /// Order ids the stub payment was completed for.
  final List<String> completed = [];

  /// The matrix the paywall renders. Null keeps the two-row default; pass [fullPriceMatrix] for a
  /// test that cares about the ladder, or an empty list for the empty state.
  final List<TierPrice>? priceRows;

  /// When set, `GET /billing/prices` refuses — the failed state and its retry.
  final Failure? priceFailure;

  /// What `GET /billing/subscription` answers. Null is a FREE account with the week still on offer.
  Either<Failure, SubscriptionState>? subscriptionResult;

  /// What the trial, the cancel and the upgrade leave the plan as. Null keeps what is there.
  Either<Failure, SubscriptionState>? afterTrial;
  Either<Failure, SubscriptionState>? afterCancel;
  Either<Failure, SubscriptionState>? afterUpgrade;

  /// docs/11 §7's quote. Null refuses, as the server does when there is nothing to upgrade.
  Either<Failure, UpgradeQuote>? quoteResult;

  /// Holds the read open so a test can see the loading state.
  Completer<void>? hold;

  final List<String> trialTiers = [];
  final List<({String tier, int months})> upgrades = [];
  int cancels = 0;

  @override
  Future<Either<Failure, Entitlements>> entitlements() async =>
      Right(Entitlements(tier: tier, status: 'active', paymentsMode: paymentsMode));

  @override
  Future<Either<Failure, SubscriptionState>> subscription() async {
    await hold?.future;
    return subscriptionResult ??
        const Right(SubscriptionState(tier: 'FREE', status: 'active', trialAvailable: true));
  }

  @override
  Future<Either<Failure, SubscriptionState>> startTrial(String tier) async {
    trialTiers.add(tier);
    final next = afterTrial;
    if (next != null) subscriptionResult = next.isRight() ? next : subscriptionResult;
    return next ?? await subscription();
  }

  @override
  Future<Either<Failure, SubscriptionState>> cancelRenewal({String? reason}) async {
    cancels++;
    final next = afterCancel;
    if (next != null) subscriptionResult = next;
    return next ?? await subscription();
  }

  @override
  Future<Either<Failure, UpgradeQuote>> upgradeQuote({
    required String tier,
    required int months,
  }) async =>
      quoteResult ??
      const Left(ApiFailure('You do not have an active plan right now.', code: 'NO_ACTIVE_PLAN'));

  @override
  Future<Either<Failure, CheckoutSession>> upgrade({
    required String tier,
    required int months,
    required String idempotencyKey,
  }) async {
    upgrades.add((tier: tier, months: months));
    final next = afterUpgrade;
    if (next != null) subscriptionResult = next;
    // Nothing left to pay: the server settled it, which is what an amount of zero says.
    return Right(
      CheckoutSession(orderId: 'eatzify_upgrade_1', amountPaise: 0, tier: tier, mode: paymentsMode),
    );
  }

  @override
  Future<Either<Failure, CheckoutSession>> checkout({
    required String tier,
    required int months,
    required String idempotencyKey,
    String? couponCode,
  }) async {
    final failure = checkoutFailure;
    if (failure != null) return Left(failure);

    bought.add((tier: tier, months: months));
    return Right(
      CheckoutSession(
        orderId: 'eatzify_test_1',
        amountPaise: 179900,
        tier: tier,
        mode: paymentsMode,
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> completeStubPayment(String orderId) async {
    completed.add(orderId);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<TierPrice>>> prices() async {
    final failure = priceFailure;
    if (failure != null) return Left(failure);
    return Right(
      priceRows ??
          const [
            TierPrice(tier: 'BASIC', months: 3, pricePaise: 69900),
            TierPrice(tier: 'PRO', months: 12, pricePaise: 549900),
          ],
    );
  }
}

/// `api/src/billing/tiers.ts` PRICES, in the order the data source sorts them (tier, then months).
/// The real ladder, so a test that checks a per-month figure is checking the number a user sees.
const fullPriceMatrix = <TierPrice>[
  TierPrice(tier: 'BASIC', months: 1, pricePaise: 24900),
  TierPrice(tier: 'BASIC', months: 3, pricePaise: 69900),
  TierPrice(tier: 'BASIC', months: 6, pricePaise: 119900),
  TierPrice(tier: 'BASIC', months: 9, pricePaise: 159900),
  TierPrice(tier: 'BASIC', months: 12, pricePaise: 209900),
  TierPrice(tier: 'PRO', months: 1, pricePaise: 64900),
  TierPrice(tier: 'PRO', months: 3, pricePaise: 179900),
  TierPrice(tier: 'PRO', months: 6, pricePaise: 279900),
  TierPrice(tier: 'PRO', months: 9, pricePaise: 379900),
  TierPrice(tier: 'PRO', months: 12, pricePaise: 499900),
];

/// Stands in for `POST /plans/generate`.
class FakePlanRepository implements PlanRepository {
  FakePlanRepository({this.failure, this.plan, this.currentResult, this.optionsResult});

  final Failure? failure;
  final Plan? plan;
  final Either<Failure, Plan?>? currentResult;
  final Either<Failure, Map<String, List<FoodOption>>>? optionsResult;
  int generated = 0;

  @override
  Future<Either<Failure, Unit>> generate() async {
    generated++;
    if (failure != null) return Left(failure!);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Plan?>> current() async => currentResult ?? Right(plan);

  @override
  Future<Either<Failure, Map<String, List<FoodOption>>>> options() async =>
      optionsResult ?? const Right(foodOptionsBySlot);
}

/// A short, unremarkable set of choices per slot (D-82, D-85).
const foodOptionsBySlot = <String, List<FoodOption>>{
  'breakfast': foodOptions,
  'lunch': foodOptions,
  'snack': foodOptions,
  'dinner': foodOptions,
};

const foodOptions = [
  FoodOption(
    id: 'f1',
    name: 'Dal tadka',
    kcalPer100g: 120,
    measureLabel: 'katori',
    measureGrams: 150,
    kcalPerMeasure: 180,
  ),
  FoodOption(
    id: 'f2',
    name: 'Roti',
    kcalPer100g: 297,
    measureLabel: 'piece',
    measureGrams: 40,
    kcalPerMeasure: 119,
  ),
];

const samplePlan = Plan(
  id: 'p1',
  validFrom: '2026-08-25',
  targets: Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
  rulePackVersion: '1.0.0',
  warnings: [],
  mealTargets: [
    MealTarget(slot: 'breakfast', pct: 0.3, kcal: 558, proteinG: 38, carbG: 67, fatG: 16),
    MealTarget(slot: 'lunch', pct: 0.4, kcal: 744, proteinG: 50, carbG: 89, fatG: 21),
    MealTarget(slot: 'dinner', pct: 0.3, kcal: 558, proteinG: 38, carbG: 67, fatG: 16),
  ],
);

/// A phone's health store, answering whatever a test sets.
class FakeHealthRepository implements HealthRepository {
  HealthAvailability available = HealthAvailability.ready;
  HealthPermission permitted = HealthPermission.denied;

  /// What a tap on Connect leaves things at.
  HealthPermission afterRequest = HealthPermission.granted;
  Map<String, Map<HealthMetric, num>> recorded = const {};

  /// Holds [availability] open so a test can see the loading state.
  Completer<void>? hold;

  int prompts = 0;
  int installs = 0;

  /// Whether the one-time connect sheet has already been shown to this account.
  bool offered = false;

  @override
  Future<HealthAvailability> availability() async {
    await hold?.future;
    return available;
  }

  @override
  Future<HealthPermission> permission() async => permitted;

  @override
  Future<HealthPermission> requestPermission() async {
    prompts++;
    return permitted = afterRequest;
  }

  @override
  Future<Either<Failure, Map<String, Map<HealthMetric, num>>>> readDaily(
    List<DiaryWindow> windows,
  ) async => Right(recorded);

  @override
  Future<void> openInstall() async => installs++;

  @override
  Future<bool> wasOffered() async => offered;

  @override
  Future<void> markOffered() async => offered = true;
}

/// The server's messages, in memory.
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository({this.feedResult, this.failure});

  final Either<Failure, NotificationFeed>? feedResult;
  final Failure? failure;

  /// Holds the list open so a test can see the loading state.
  Completer<void>? hold;

  final readIds = <String>[];
  int readAllCalls = 0;

  @override
  Future<Either<Failure, NotificationFeed>> list({DateTime? before}) async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return Left(failed);
    return feedResult ?? const Right((items: <AppNotification>[], unreadCount: 0));
  }

  @override
  Future<Either<Failure, Unit>> markRead(String id) async {
    readIds.add(id);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> markAllRead() async {
    readAllCalls++;
    return const Right(unit);
  }
}

/// docs/13 §3 and §9, in memory (D-233).
class FakePrivacyRepository implements PrivacyRepository {
  FakePrivacyRepository({
    List<ConsentItem>? consents,
    this.requests = const [],
    this.failure,
    this.actionFailure,
  }) : consents =
           consents ??
           const [
             ConsentItem(type: 'health_data_storage', granted: true),
             ConsentItem(type: 'plan_generation', granted: true),
             ConsentItem(type: 'marketing', granted: false),
           ];

  List<ConsentItem> consents;
  List<PrivacyRequest> requests;

  /// Fails the initial read.
  final Failure? failure;

  /// Fails whatever the person presses — the refusal the screen has to show verbatim.
  final Failure? actionFailure;

  /// Holds the read open so a test can see the loading state.
  Completer<void>? hold;

  final setCalls = <({String type, bool granted})>[];
  int exports = 0;
  int deletions = 0;
  int cancellations = 0;

  @override
  Future<Either<Failure, PrivacyState>> load() async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return Left(failed);
    return Right((consents: consents, requests: requests));
  }

  @override
  Future<Either<Failure, List<ConsentItem>>> setConsent(
    String type, {
    required bool granted,
  }) async {
    final failed = actionFailure;
    if (failed != null) return Left(failed);

    setCalls.add((type: type, granted: granted));
    consents = [
      for (final c in consents)
        if (c.type == type) c.copyWith(granted: granted) else c,
    ];
    return Right(consents);
  }

  @override
  Future<Either<Failure, PrivacyRequest>> requestExport() async {
    final failed = actionFailure;
    if (failed != null) return Left(failed);

    exports++;
    return const Right(PrivacyRequest(id: 'x1', kind: 'export', status: 'done'));
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> exportBundle(String requestId) async {
    return const Right({
      'account': {'user_id': 7},
      'food_logs': [1, 2, 3],
    });
  }

  @override
  Future<Either<Failure, PrivacyRequest>> requestDeletion() async {
    final failed = actionFailure;
    if (failed != null) return Left(failed);

    deletions++;
    requests = [
      PrivacyRequest(
        id: 'd1',
        kind: 'delete',
        status: 'pending',
        executeAfter: DateTime(2026, 9, 25),
      ),
    ];
    return Right(requests.first);
  }

  @override
  Future<Either<Failure, Unit>> cancelDeletion() async {
    final failed = actionFailure;
    if (failed != null) return Left(failed);

    cancellations++;
    requests = const [];
    return const Right(unit);
  }
}

/// Support conversations, in memory (D-228).
class FakeTicketsRepository implements TicketsRepository {
  FakeTicketsRepository({
    this.tickets = const [],
    this.threadResult,
    this.failure,
    this.openFailure,
  });

  final List<SupportTicket> tickets;
  final SupportThread? threadResult;
  final Failure? failure;

  /// What `open` refuses with — the "you already have several open" answer, in the test that
  /// checks the server's own words reach the sheet.
  final Failure? openFailure;

  /// Holds a read open so a test can see the loading state.
  Completer<void>? hold;

  final replies = <String>[];
  final opened = <String>[];

  @override
  Future<Either<Failure, List<SupportTicket>>> list() async {
    await hold?.future;
    final failed = failure;
    return failed != null ? Left(failed) : Right(tickets);
  }

  @override
  Future<Either<Failure, SupportTicket>> open({
    required String subject,
    required String body,
    String? requestId,
  }) async {
    final failed = openFailure;
    if (failed != null) return Left(failed);
    opened.add(subject);
    return Right(
      SupportTicket(id: 't-new', subject: subject, status: 'new', createdAt: DateTime(2026, 9, 18)),
    );
  }

  @override
  Future<Either<Failure, SupportThread>> thread(String id) async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return Left(failed);
    final only =
        threadResult ??
        (
          ticket: tickets.isEmpty
              ? SupportTicket(id: id, subject: 'Support', status: 'new')
              : tickets.first,
          messages: const <SupportMessage>[],
        );
    return Right(only);
  }

  @override
  Future<Either<Failure, Unit>> reply(String id, String body) async {
    final failed = openFailure;
    if (failed != null) return Left(failed);
    replies.add(body);
    return const Right(unit);
  }
}

/// The phone's reminders, in memory: what was stored, and what was last scheduled.
class FakeReminderRepository implements ReminderRepository {
  FakeReminderRepository({this.permitted = ReminderPermission.denied});

  ReminderPermission permitted;

  /// What the system's question is answered with.
  ReminderPermission afterRequest = ReminderPermission.granted;

  ReminderState state = const ReminderState();

  /// Null until something is scheduled or cancelled; empty after a cancel.
  List<PlannedReminder>? scheduled;
  int prompts = 0;
  int cancels = 0;

  /// Holds [permission] open so a test can see the loading state.
  Completer<void>? hold;

  @override
  Future<ReminderState> readState() async => state;

  @override
  Future<void> writeState(ReminderState state) async => this.state = state;

  @override
  Future<ReminderPermission> permission() async {
    await hold?.future;
    return permitted;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    prompts++;
    return permitted = afterRequest;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async => scheduled = reminders;

  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled = const [];
  }
}

/// In-memory keychain, so a test never touches the real one.
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => value == null ? data.remove(key) : data[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.clear();
}

/// Enough of the auth contract for a `SessionController` to exist in a widget test.
class FakeAuthRepository implements AuthRepository {
  @override
  Future<Either<Failure, Session>> refresh(Session current) async =>
      const Left(ApiFailure('x', code: 'X'));

  @override
  Future<Either<Failure, Unit>> logout(Session current) async => const Right(unit);

  @override
  Future<Either<Failure, Unit>> requestOtp(String phoneE164) async => const Right(unit);

  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async => const Left(ApiFailure('x', code: 'X'));

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async => const Left(ApiFailure('x', code: 'X'));
}

/// A registered `SessionController` holding a real stored session, mid-onboarding.
///
/// The storage is seeded rather than the status being set by hand: `markOnboardingComplete` is a
/// no-op without a stored session, so a controller with only a status looks signed in and then
/// silently refuses to move on.
SessionController putFakeSession() {
  final storage = FakeSecureStorage()
    ..data['auth.access'] = 'a1'
    ..data['auth.refresh'] = 'r1'
    ..data['auth.user_id'] = 'u-1'
    ..data['auth.roles'] = 'client'
    ..data['auth.onboarding_required'] = 'true';

  return Get.put(
    SessionController(
      store: SecureStore(storage: storage),
      auth: FakeAuthRepository(),
      // Agrees with the seeded `onboarding_required`: `Right(null)` is "the server has no profile
      // either". The default fake returns a completed profile, which would reconcile the flag away
      // and leave every caller of this helper signed in.
      profile: FakeProfileRepository(profileResult: const Right(null)),
      // No splash floor. `restore` schedules it on construction, so any test that mounts a
      // session and pumps less than 1.2 s fails on a pending timer for a screen it never shows.
      // The floor is tested where it belongs, in launch_flow_test.
      splashFloor: Duration.zero,
    ),
    permanent: true,
  );
}
