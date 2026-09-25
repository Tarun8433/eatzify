import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/entities/session_role.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';

/// Where the app is, authentication-wise. Drives routing; never inferred from a null check.
enum AuthStatus {
  /// Reading secure storage on boot. Splash is shown; no decision has been made yet.
  restoring,
  signedOut,

  /// Signed in, but the SERVER says onboarding is incomplete (docs/09 `onboarding_required`).
  /// The app never decides this from cached data.
  onboardingRequired,
  signedIn,
}

/// Owns the session for the whole app: restore on boot, rotate on 401, clear on logout.
///
/// Permanent in GetX — everything else asks this rather than keeping its own copy of a token.
class SessionController extends GetxController {
  SessionController({
    required this.store,
    required this.auth,
    required this.profile,
    this.splashFloor = splashMinimum,
  });

  final SecureStore store;
  final AuthRepository auth;

  /// Only ever read on boot, to check a cached `onboarding_required` against the server before it
  /// is allowed to keep somebody out of their own account. See [_onboardingDoneOnServer].
  final ProfileRepository profile;

  /// Overridden to [Duration.zero] in tests. A real 1.2 s sleep in every boot test is 1.2 s per
  /// test of nothing, and the floor is a presentation decision, not a session one.
  final Duration splashFloor;

  final status = AuthStatus.restoring.obs;

  /// Which shell to draw (CLAUDE.md rule 1). Defaults to CLIENT and only ever moves off it when
  /// the SERVER says so — a failed or slow `/auth/me` leaves somebody on their own data, which is
  /// the safe way to be wrong. docs/10 §1: this decides navigation and nothing else.
  final role = SessionRole.client.obs;
  final _session = Rxn<Session>();

  /// Whether the intro carousel has already been shown, on this install, to anyone. Read once on
  /// boot so routing never has to await storage. Signing out does not reset it (see
  /// [SecureStore.clear]).
  final introSeen = false.obs;

  /// How long the splash stays up at minimum (D-92).
  ///
  /// Restoring a session is a keychain read — a few milliseconds — so without a floor the splash
  /// is a single frame of flicker between the launch image and the first screen, which reads as a
  /// glitch rather than as the app opening. Short enough that it is never a wait.
  static const splashMinimum = Duration(milliseconds: 1200);

  /// How long the splash may hold while the onboarding flag is reconciled (see
  /// [_onboardingDoneOnServer]). dio's own 20 s is a fair ceiling for a screen with a spinner and
  /// far too long for a launch; past this the cached flag stands and the form is shown.
  static const verifyBudget = Duration(seconds: 3);

  /// The one in-flight refresh. Every concurrent 401 awaits this instead of starting its own —
  /// see [refreshAccessToken].
  Future<String?>? _refreshing;

  Session? get session => _session.value;
  String? get accessToken => _session.value?.accessToken;

  /// The signed-in account's own id, as the server spells it. Used where the app has to tell this
  /// person's rows from somebody else's — a chat bubble, for one (docs/02 FR-5.5).
  String? get userId => _session.value?.userId;
  bool get isCoach => _session.value?.isCoach ?? false;

  @override
  void onInit() {
    super.onInit();
    unawaited(restore());
  }

  /// Boot path. A stored session is trusted enough to route on; the first authenticated call
  /// refreshes or fails, and [refreshAccessToken] cleans up. A signed-in boot deliberately makes NO
  /// network call — a user on a dead connection should still reach a cached plan. The one exception
  /// is a session cached as still needing onboarding, which is checked before it can lock the user
  /// out of an account they already have; see [_onboardingDoneOnServer].
  Future<void> restore() async {
    // A keychain read can throw — a restored Android backup leaves EncryptedSharedPreferences
    // holding entries this install's key cannot decrypt. Without this the future dies unhandled
    // and the app sits on the splash forever, which is worse than asking for a fresh sign-in.
    // Runs alongside the read rather than after it: the floor is the splash's minimum, not an
    // extra delay added to whatever the keychain took.
    final floor = Future<void>.delayed(splashFloor);

    Session? stored;
    try {
      introSeen.value = await store.readIntroSeen();
      stored = await store.read();
    } on Object {
      await store.clear();
      await floor;
      status.value = AuthStatus.signedOut;
      return;
    }
    await floor;
    if (stored == null) {
      status.value = AuthStatus.signedOut;
      return;
    }
    _session.value = stored;
    if (stored.onboardingRequired && await _onboardingDoneOnServer()) {
      // Persists the corrected flag as well, so the next boot needs no round-trip.
      await markOnboardingComplete();
      return;
    }
    status.value = stored.onboardingRequired ? AuthStatus.onboardingRequired : AuthStatus.signedIn;
    if (status.value == AuthStatus.signedIn) unawaited(loadRole());
  }

  /// Whether the SERVER thinks onboarding is done, for a session cached as needing it.
  ///
  /// The cached flag may let a user IN, but it must never be the only thing keeping them OUT.
  /// `onboarding_required` is written once, at `/auth/otp/verify`, and every refresh copies it
  /// forward — nothing has ever re-read it. So anything that completes onboarding away from this
  /// copy of the app (killed between the successful POST and the local write, a second device, a
  /// support agent) leaves the flag true here for good, and a person with a perfectly real account
  /// boots into "About you" every single time with no way back to it.
  ///
  /// `GET /profile` returns exactly what the server used to compute the flag — `profile != null`
  /// is `hasCompletedOnboarding` — so one read settles it. It is asked only on the branch that
  /// would otherwise lock the user out; a signed-in boot still reaches a cached plan with the
  /// radio off.
  ///
  /// A failure is not an answer. Offline, 5xx or slower than [verifyBudget] all return false: the
  /// cached flag stands, the form is shown, and its header carries the sign-out as the way out.
  Future<bool> _onboardingDoneOnServer() async {
    // ponytail: this is the first authenticated call of the process, and it works because
    // `restore` awaits the splash floor first, by which time `main` has run `attachAuth` on the
    // same dio. Drop the floor and this needs the token wired before `Get.put`.
    final result = await profile.profile().timeout(
      verifyBudget,
      onTimeout: () => const Left(UnexpectedFailure('onboarding check timed out')),
    );
    return result.fold((_) => false, (view) => view != null);
  }

  /// Called when the carousel is finished or skipped. Persisted before the flag flips so a crash
  /// between the two shows it once more rather than never again.
  Future<void> markIntroSeen() async {
    await store.markIntroSeen();
    introSeen.value = true;
  }

  Future<void> adopt(Session session) async {
    _session.value = session;
    await store.save(session);
    status.value = session.onboardingRequired ? AuthStatus.onboardingRequired : AuthStatus.signedIn;
    if (status.value == AuthStatus.signedIn) unawaited(loadRole());
  }

  /// Called once onboarding completes, and by [restore] when the server contradicts a stale cached
  /// flag. The server is the authority, so this is an optimistic local update that
  /// [_onboardingDoneOnServer] confirms or corrects on the next boot.
  Future<void> markOnboardingComplete() async {
    final current = _session.value;
    if (current == null) return;
    final updated = current.copyWith(onboardingRequired: false);
    _session.value = updated;
    await store.save(updated);
    status.value = AuthStatus.signedIn;
    await loadRole();
  }

  /// Asks the server which shell this account gets.
  ///
  /// Never throws and never blocks sign-in: the client shell is a correct answer for a client and
  /// a merely incomplete one for a coach, so a network failure costs a coach their tabs until the
  /// next launch rather than costing anyone their account.
  Future<void> loadRole() async {
    final result = await profile.roles();
    result.fold(
      (_) => role.value = SessionRole.client,
      (wire) => role.value = SessionRole.fromWire(wire),
    );
  }

  /// Wired into the dio interceptor. Returns a fresh access token, or null when the refresh failed.
  ///
  /// Single-flight. The tabs all load at once, so an expired access token produces several 401s in
  /// the same instant; letting each start its own refresh sends the SAME refresh token more than
  /// once, and docs/09 says reuse revokes the family — the app signs itself out seconds after boot.
  /// The first caller does the work, the rest await it and get the same new token.
  Future<String?> refreshAccessToken() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh() async {
    final current = _session.value;
    if (current == null) return null;

    final result = await auth.refresh(current);
    return result.fold(
      (failure) async {
        // Only a refusal from the server proves the refresh token is dead. A timeout, a dropped
        // connection or a 5xx says nothing about the credential, and signing out on one logs a user
        // out for riding a lift. Their request just fails; the next one refreshes again.
        if (_isCredentialRejected(failure)) await signOut(revokeOnServer: false);
        return null;
      },
      (fresh) async {
        _session.value = fresh;
        await store.save(fresh);
        return fresh.accessToken;
      },
    );
  }

  /// 400/401/403 from `/auth/refresh` — the server looked at the token and said no.
  static bool _isCredentialRejected(Failure failure) =>
      failure is ApiFailure && const {400, 401, 403}.contains(failure.status);

  /// Local state is cleared even if the server call fails. A user who taps "log out" on a plane
  /// must not stay logged in.
  Future<void> signOut({bool revokeOnServer = true}) async {
    final current = _session.value;
    if (revokeOnServer && current != null) await auth.logout(current);
    _session.value = null;
    _refreshing = null;
    await store.clear();
    status.value = AuthStatus.signedOut;
  }
}
