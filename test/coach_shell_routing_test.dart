import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
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
}
