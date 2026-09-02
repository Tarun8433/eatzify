import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health_pro/domain/entities/session.dart';

/// Token persistence. Keychain on iOS, EncryptedSharedPreferences on Android.
///
/// CLAUDE.md rule 11 forbids ad-hoc persistence; tokens in particular must never touch Hive or
/// SharedPreferences, which are readable on a rooted device.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
          );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _kUserId = 'auth.user_id';
  static const _kRoles = 'auth.roles';
  static const _kOnboarding = 'auth.onboarding_required';

  /// Whether the intro carousel has been shown. Not a token, but it lives here because this is the
  /// app's declared persistence (rule 11) and it is the one thing that must SURVIVE [clear] —
  /// signing out should not replay a marketing carousel at someone who already has an account.
  static const _kIntroSeen = 'intro.seen';

  Future<void> save(Session session) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: session.accessToken),
      _storage.write(key: _kRefresh, value: session.refreshToken),
      _storage.write(key: _kUserId, value: session.userId),
      _storage.write(key: _kRoles, value: session.roles.join(',')),
      _storage.write(key: _kOnboarding, value: session.onboardingRequired.toString()),
    ]);
  }

  Future<Session?> read() async {
    final access = await _storage.read(key: _kAccess);
    final refresh = await _storage.read(key: _kRefresh);
    final userId = await _storage.read(key: _kUserId);
    if (access == null || refresh == null || userId == null) return null;

    final roles = await _storage.read(key: _kRoles) ?? '';
    return Session(
      accessToken: access,
      refreshToken: refresh,
      userId: userId,
      roles: roles.isEmpty ? const [] : roles.split(','),
      onboardingRequired: await _storage.read(key: _kOnboarding) == 'true',
    );
  }

  /// False rather than throwing when the keychain is unreadable. [clear] is the recovery path for
  /// exactly that failure, so a read in it that can throw would strand the app on the splash — the
  /// bug the boot-resilience test exists to catch. Showing the intro once more is the harmless
  /// direction to be wrong in.
  Future<bool> readIntroSeen() async {
    try {
      return await _storage.read(key: _kIntroSeen) == 'true';
    } on Object {
      return false;
    }
  }

  Future<void> markIntroSeen() => _storage.write(key: _kIntroSeen, value: 'true');

  /// Called on logout and on refresh-token rejection. Clears every key, not just the access token —
  /// a half-cleared session is how a revoked refresh token gets retried forever. `deleteAll` rather
  /// than five named deletes so a key added by an older build cannot outlive the session it
  /// belonged to; [_kIntroSeen] is the one deliberate survivor and is written back.
  Future<void> clear() async {
    final introSeen = await readIntroSeen();
    await _storage.deleteAll();
    if (introSeen) await markIntroSeen();
  }
}
