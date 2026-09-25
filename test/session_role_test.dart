import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/session_role.dart';

/// docs/10 §1. The mapping from the server's eight roles onto the two shells CLAUDE.md rule 1
/// allows. Getting it wrong hands somebody the wrong navigation, which is the visible half; the
/// invisible half is that a role is not permission to see a client, and the server enforces that
/// regardless of what this decides.
void main() {
  group('SessionRole.fromWire', () {
    test('gives the coach shell to every coach level', () {
      for (final wire in ['coach_l1', 'coach_l2', 'coach_l3']) {
        expect(SessionRole.fromWire([wire]), SessionRole.coach, reason: wire);
      }
    });

    /// The seed writes display names ("Verified Coach"), the enum writes keys ("coach_l2"), and
    /// `GET /auth/me` returns whichever the row holds. Both spellings have to land in the same
    /// place or a coach's tabs depend on how the seed was written.
    test('accepts the seeded display names as well as the enum keys', () {
      expect(SessionRole.fromWire(['Verified Coach']), SessionRole.coach);
      expect(SessionRole.fromWire(['Coaching Partner']), SessionRole.coach);
    });

    test('gives the client shell to a plain user', () {
      expect(SessionRole.fromWire(['user']), SessionRole.client);
    });

    /// doc 20 §3 puts admin in a separate web panel and rule 1 lists only two shells, so these
    /// roles have no Flutter surface of their own.
    test('sends admin, support and partner organisations to no shell of their own', () {
      for (final wire in ['admin', 'super_admin', 'support', 'partner_org']) {
        expect(SessionRole.fromWire([wire]), SessionRole.other, reason: wire);
      }
    });

    /// The failure that matters. A server that starts sending a role this build has never heard of
    /// must not be able to hand somebody the coach tabs, and the safe default is the shell that
    /// only ever shows a person their own data.
    test('treats an unknown role as a client rather than a coach', () {
      expect(SessionRole.fromWire(['dietitian_l7']), SessionRole.client);
      expect(SessionRole.fromWire([]), SessionRole.client);
    });

    test('takes the coach shell when an account holds several roles', () {
      expect(SessionRole.fromWire(['user', 'coach_l3']), SessionRole.coach);
    });

    test('reads a role whatever its casing', () {
      expect(SessionRole.fromWire(['COACH_L2']), SessionRole.coach);
    });
  });
}
