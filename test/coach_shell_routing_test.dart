import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/entities/session_role.dart';

import 'fakes.dart';

/// CLAUDE.md rule 1: two shells, and which one is a SERVER answer. The routing itself is one line
/// in `RootGate`; what needs a test is the decision behind it, because the failure mode is showing
/// somebody the wrong person's navigation.
///
/// docs/10 §1 is the thing to keep in mind while reading this: a role decides NAVIGATION, never
/// access. A coach reaching the coach shell still sees nothing about anyone without a consent
/// grant, and the server enforces that whatever the app believes.
SessionController controllerFor(List<String> roleNames) {
  return SessionController(
    store: SecureStore(storage: FakeSecureStorage()),
    auth: FakeAuthRepository(),
    profile: FakeProfileRepository(profileResult: const Right(null), roleNames: roleNames),
    splashFloor: Duration.zero,
  );
}

void main() {
  test('offers no coach surface before the server has answered', () {
    expect(controllerFor(const []).role.value, SessionRole.client);
  });

  test('offers the coach surface when the server says the account coaches', () async {
    final session = controllerFor(const ['coach_l3']);

    await session.loadRole();

    expect(session.role.value, SessionRole.coach);
  });

  test('offers a plain user no coach surface', () async {
    final session = controllerFor(const ['user']);

    await session.loadRole();

    expect(session.role.value, SessionRole.client);
  });

  /// doc 20 §3 puts admin in a separate web panel and rule 1 lists only two shells, so an admin
  /// signing into the phone app is a person looking at their own data.
  test('offers an admin no coach surface, because the app has no admin panel', () async {
    final session = controllerFor(const ['admin']);

    await session.loadRole();

    expect(session.role.value, SessionRole.other);
  });

  /// The safe way to be wrong. A coach losing the door until the next launch costs them a tap;
  /// a client being offered a client list because a request timed out is a different kind of
  /// mistake.
  test('offers nothing when the roles call fails', () async {
    final session = SessionController(
      store: SecureStore(storage: FakeSecureStorage()),
      auth: FakeAuthRepository(),
      profile: FakeProfileRepository(
        profileResult: const Right(null),
        rolesFailure: const OfflineFailure('offline'),
      ),
      splashFloor: Duration.zero,
    );

    await session.loadRole();

    expect(session.role.value, SessionRole.client);
  });

  group('the dashboard switch (D-269)', () {
    const signedIn = Session(
      accessToken: 'a',
      refreshToken: 'r',
      userId: '42',
      roles: ['coach_l2'],
      onboardingRequired: false,
    );

    ({SessionController session, FakeProfileRepository repo, SecureStore store}) partner({
      bool allowed = true,
    }) {
      final store = SecureStore(storage: FakeSecureStorage());
      final repo = FakeProfileRepository(
        profileResult: const Right(null),
        roleNames: const ['coach_l2'],
        canSwitchDashboard: allowed,
      );
      final session = SessionController(
        store: store,
        auth: FakeAuthRepository(),
        profile: repo,
        splashFloor: Duration.zero,
      );
      return (session: session, repo: repo, store: store);
    }

    test('should follow the server, not the role, on who may switch', () async {
      final verified = partner(allowed: false);
      await verified.session.adopt(signedIn);
      await verified.session.loadRole();

      expect(verified.session.role.value, SessionRole.coach);
      expect(verified.session.canSwitchDashboard.value, isFalse);
      verified.session.switchDashboard(DashboardMode.clients);
      expect(verified.session.dashboard.value, DashboardMode.mine);
    });

    test('should open on the dashboard this account chose', () async {
      final p = partner();
      await p.store.writeDashboardDefault('42', DashboardMode.clients);

      await p.session.adopt(signedIn);
      await p.session.loadRole(openDefault: true);

      expect(p.session.dashboard.value, DashboardMode.clients);
    });

    test('should not move anyone when the You tab re-reads the account', () async {
      final p = partner();
      await p.session.adopt(signedIn);
      await p.session.loadRole(openDefault: true);
      await p.session.setDefaultDashboard(DashboardMode.clients);

      await p.session.loadRole();

      expect(p.session.dashboard.value, DashboardMode.mine);
    });

    test('should fall back to My tracking when an admin takes the switch away', () async {
      final p = partner();
      await p.session.adopt(signedIn);
      await p.session.loadRole();
      p.session.switchDashboard(DashboardMode.clients);

      p.repo.canSwitchDashboard = false;
      await p.session.loadRole();

      expect(p.session.dashboard.value, DashboardMode.mine);
    });

    test('should keep the chosen default on this phone across sign-out', () async {
      final p = partner();
      await p.session.adopt(signedIn);
      await p.session.setDefaultDashboard(DashboardMode.clients);

      await p.session.signOut(revokeOnServer: false);

      expect(await p.store.readDashboardDefault('42'), DashboardMode.clients);
      expect(p.session.dashboard.value, DashboardMode.mine);
      expect(await p.store.readIntroSeen(), isFalse);
    });
  });
}
