import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/entities/plan.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';

/// Stands in for the profile endpoints so widgets can be driven without a dio.
///
/// Defaults to a completed profile, because that is the state most screens are built for. Pass
/// `profileResult` to exercise Empty (`Right(null)`) or Failed (`Left(...)`).
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.result, this.failure, this.profileResult, this.patchFailure});

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

  @override
  Future<Either<Failure, ProfileView?>> profile() async =>
      profileResult ?? const Right(defaultProfile);

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
  FakeDiaryRepository({this.dayResult, this.foods = const [], this.failure});

  final Either<Failure, DiaryDay>? dayResult;
  final List<Food> foods;
  final Failure? failure;

  String? lastLoggedFoodId;

  /// Every request this fake was asked for, so a paging test can assert the offsets rather than
  /// only the rows that came back.
  final searchCalls = <({String query, int limit, int offset, String? suitableFor})>[];

  @override
  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit = 20,
    int offset = 0,
    String? suitableFor,
  }) async {
    searchCalls.add((query: query, limit: limit, offset: offset, suitableFor: suitableFor));
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
  }) async {
    lastLoggedFoodId = foodId;
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
    return dayResult ?? const Right(emptyDay);
  }

  @override
  Future<Either<Failure, Unit>> remove(String id) async => const Right(unit);
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
  }) {
    searches++;
    return super.searchFoods(query, limit: limit, offset: offset, suitableFor: suitableFor);
  }
}

/// Stands in for the two billing endpoints that exist (D-136). The tier is the whole point:
/// premium surfaces render only when the server says FREE.
class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository({this.tier = 'FREE'});

  final String tier;

  @override
  Future<Either<Failure, Entitlements>> entitlements() async =>
      Right(Entitlements(tier: tier, status: 'active'));

  @override
  Future<Either<Failure, List<TierPrice>>> prices() async => const Right([
    TierPrice(tier: 'BASIC', months: 3, pricePaise: 69900),
    TierPrice(tier: 'PRO', months: 12, pricePaise: 549900),
  ]);
}

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
