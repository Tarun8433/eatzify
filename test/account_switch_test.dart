import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:health_pro/main.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/plan/plan_controller.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';

import 'fakes.dart';

/// In-memory keychain, so a test never touches the real one.
class _FakeStorage extends FlutterSecureStorage {
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

class _FakeAuth implements AuthRepository {
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

Session _session(String userId) => Session(
  accessToken: 'a-$userId',
  refreshToken: 'r-$userId',
  userId: userId,
  roles: const ['client'],
  onboardingRequired: false,
);

/// Serves whichever account is signed in, so "did it reload?" is answerable by reading the age.
class _SwitchableProfiles extends FakeProfileRepository {
  _SwitchableProfiles();

  /// Flipped between the two sign-ins, the way a different account on the server would be.
  int age = 29;
  int calls = 0;

  @override
  Future<Either<Failure, ProfileView?>> profile() async {
    calls++;
    return Right(
      ProfileView(
        ageYears: age,
        heightCm: 170,
        weightKg: 70,
        sexAtBirth: 'male',
        goal: 'fat_loss',
        activity: 'light',
        foodPreference: 'veg',
        conditions: const [],
        allergies: const [],
        healthProfileVersion: 1,
      ),
    );
  }
}

void main() {
  late _SwitchableProfiles profiles;
  late SessionController session;

  setUp(() {
    Get.reset();
    profiles = _SwitchableProfiles();
    Get
      ..put<ProfileRepository>(profiles, permanent: true)
      ..put<PlanRepository>(FakePlanRepository(plan: samplePlan), permanent: true)
      ..put(NavController(), permanent: true);
    session = SessionController(
      store: SecureStore(storage: _FakeStorage()),
      auth: _FakeAuth(),
      profile: profiles,
    );
  });

  tearDown(Get.reset);

  /// The reported bug: sign out, sign in as somebody else, and every tab still showed the previous
  /// account until the app was restarted. Each tab controller is `permanent: true`, and `Get.put`
  /// returns the existing instance without re-running `onInit` — so nothing ever reloaded.
  group('signing out drops the previous user', () {
    test('every controller holding user data is gone', () {
      Get
        ..put(
          HomeController(diary: FakeDiaryRepository(), plans: Get.find<PlanRepository>()),
          permanent: true,
        )
        ..put(PlanController(plans: Get.find<PlanRepository>()), permanent: true)
        ..put(ProgressController(measurements: FakeMeasurementsRepository()), permanent: true)
        ..put(
          AccountController(
            profiles: Get.find<ProfileRepository>(),
            plans: Get.find<PlanRepository>(),
          ),
          permanent: true,
        );

      EatzifyApp.clearUserScopedState();

      expect(Get.isRegistered<HomeController>(), isFalse, reason: "the diary is one user's");
      expect(Get.isRegistered<PlanController>(), isFalse);
      expect(Get.isRegistered<ProgressController>(), isFalse, reason: 'so are the measurements');
      expect(Get.isRegistered<AccountController>(), isFalse);
    });

    test('a fresh controller reloads, so the next user sees their own profile', () async {
      AccountController put() => Get.put(
        AccountController(profiles: profiles, plans: Get.find<PlanRepository>()),
        permanent: true,
      );

      final first = put();
      await first.load();
      expect((first.state.value as Ready<ProfileView>).data.ageYears, 29);

      // Somebody else signs in.
      EatzifyApp.clearUserScopedState();
      profiles.age = 62;

      // What the shell does on the next sign-in: `Get.put` again. Before the fix this handed back
      // the SAME instance, still holding 29, and never re-ran onInit — so nothing reloaded.
      final second = put();
      await second.load();

      expect(identical(first, second), isFalse, reason: 'it must be a new controller');
      expect((second.state.value as Ready<ProfileView>).data.ageYears, 62);
    });

    test('the next sign-in opens on Home, not the last tab the previous user left', () {
      Get.find<NavController>().current = ClientTab.progress;

      EatzifyApp.clearUserScopedState();

      expect(Get.find<NavController>().current, ClientTab.home);
      expect(Get.isRegistered<NavController>(), isTrue, reason: 'chrome, not user data');
    });

    /// D-222. The last person's water reminders must not ring for whoever signs in next.
    test("the previous person's reminders are cancelled", () async {
      final reminders = FakeReminderRepository();
      Get.put<ReminderRepository>(reminders, permanent: true);

      EatzifyApp.clearUserScopedState();
      await Future<void>.delayed(Duration.zero);

      expect(reminders.cancels, 1);
    });

    test('clearing twice is harmless — nothing is registered the second time', () {
      EatzifyApp.clearUserScopedState();
      expect(EatzifyApp.clearUserScopedState, returnsNormally);
    });
  });

  /// The wiring, not just the clearing: a correct `clearUserScopedState` attached to nothing would
  /// leave the bug exactly as reported.
  test('signing out actually triggers it, end to end', () async {
    EatzifyApp.attachSessionCleanup(session);
    await session.adopt(_session('user-a'));

    Get.put(
      AccountController(profiles: profiles, plans: Get.find<PlanRepository>()),
      permanent: true,
    );
    expect(Get.isRegistered<AccountController>(), isTrue);

    await session.signOut(revokeOnServer: false);

    expect(session.status.value, AuthStatus.signedOut);
    expect(
      Get.isRegistered<AccountController>(),
      isFalse,
      reason: "the previous user's profile must not outlive their session",
    );
  });
}
