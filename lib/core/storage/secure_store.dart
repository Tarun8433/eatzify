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

  /// Called on logout and on refresh-token rejection. Clears every key, not just the access token —
  /// a half-cleared session is how a revoked refresh token gets retried forever.
  Future<void> clear() => _storage.deleteAll();
}
