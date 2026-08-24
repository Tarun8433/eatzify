import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

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
  SessionController({required this.store, required this.auth});

  final SecureStore store;
  final AuthRepository auth;

  final status = AuthStatus.restoring.obs;
  final _session = Rxn<Session>();

  Session? get session => _session.value;
  String? get accessToken => _session.value?.accessToken;
  bool get isCoach => _session.value?.isCoach ?? false;

  @override
  void onInit() {
    super.onInit();
    unawaited(restore());
  }

  /// Boot path. A stored session is trusted enough to route on; the first authenticated call
  /// refreshes or fails, and [refreshAccessToken] cleans up. We deliberately do NOT block the
  /// splash on a network round-trip — a user on a dead connection should still reach a cached plan.
  Future<void> restore() async {
    final stored = await store.read();
    if (stored == null) {
      status.value = AuthStatus.signedOut;
      return;
    }
    _session.value = stored;
    status.value = stored.onboardingRequired ? AuthStatus.onboardingRequired : AuthStatus.signedIn;
  }

  Future<void> adopt(Session session) async {
    _session.value = session;
    await store.save(session);
    status.value = session.onboardingRequired ? AuthStatus.onboardingRequired : AuthStatus.signedIn;
  }

  /// Called once onboarding completes. The server is the authority on this flag, so this is an
  /// optimistic local update that the next `GET /auth/me` confirms or corrects.
  Future<void> markOnboardingComplete() async {
    final current = _session.value;
    if (current == null) return;
    final updated = current.copyWith(onboardingRequired: false);
    _session.value = updated;
    await store.save(updated);
    status.value = AuthStatus.signedIn;
  }

  /// Wired into the dio interceptor. Returns a fresh access token, or null when the refresh token
  /// is dead — docs/09: reuse of a rotated token revokes the family, so there is no second chance.
  Future<String?> refreshAccessToken() async {
    final current = _session.value;
    if (current == null) return null;

    final result = await auth.refresh(current);
    return result.fold(
      (failure) async {
        await signOut(revokeOnServer: false);
        return null;
      },
      (fresh) async {
        _session.value = fresh;
        await store.save(fresh);
        return fresh.accessToken;
      },
    );
  }

  /// Local state is cleared even if the server call fails. A user who taps "log out" on a plane
  /// must not stay logged in.
  Future<void> signOut({bool revokeOnServer = true}) async {
    final current = _session.value;
    if (revokeOnServer && current != null) await auth.logout(current);
    _session.value = null;
    await store.clear();
    status.value = AuthStatus.signedOut;
  }
}
