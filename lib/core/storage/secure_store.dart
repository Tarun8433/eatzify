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
  static const _kHealthConnected = 'health.connected';
  static const _kHealthOffered = 'health.offered';
  static const _kReminders = 'reminders.state';
  static const _kGymBoxKey = 'gym.box_key';

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

  /// Showing the intro once more is the harmless direction to be wrong in.
  Future<bool> readIntroSeen() => _readFlag(_kIntroSeen);

  Future<void> markIntroSeen() => _storage.write(key: _kIntroSeen, value: 'true');

  /// Whether this account tapped Connect on the health screen (D-215).
  ///
  /// Only iOS needs it: HealthKit never says whether read access was granted, so "has this person
  /// connected" is something the app has to remember rather than ask. Cleared by [clear] with
  /// everything else — it belongs to the account, not to the phone.
  Future<bool> readHealthConnected() => _readFlag(_kHealthConnected);

  Future<void> markHealthConnected() => _storage.write(key: _kHealthConnected, value: 'true');

  /// Whether this account has already seen the one-time "connect your health app" sheet (D-218).
  /// Per account for the same reason as the flag above.
  Future<bool> readHealthOffered() => _readFlag(_kHealthOffered);

  Future<void> markHealthOffered() => _storage.write(key: _kHealthOffered, value: 'true');

  /// The phone's reminders (D-222), as JSON: what is switched on, and the day they were planned
  /// from. Per account like everything else — [clear] removes it, so the next person to sign in
  /// starts with nothing switched on.
  Future<String?> readReminders() async {
    try {
      return await _storage.read(key: _kReminders);
    } on Object {
      return null;
    }
  }

  Future<void> writeReminders(String json) => _storage.write(key: _kReminders, value: json);

  /// The key the Gym box is encrypted with on disk (ADR-013), base64. A workout in progress holds
  /// a body weight, so the box is ciphertext; [clear] takes the key with everything else, and the
  /// box is deleted at sign-out too, so nothing of the last person survives on the phone.
  Future<String?> readGymBoxKey() async {
    try {
      return await _storage.read(key: _kGymBoxKey);
    } on Object {
      return null;
    }
  }

  Future<void> writeGymBoxKey(String key) => _storage.write(key: _kGymBoxKey, value: key);

  /// False rather than throwing when the keychain is unreadable. [clear] is the recovery path for
  /// exactly that failure, so a read in it that can throw would strand the app on the splash — the
  /// bug the boot-resilience test exists to catch.
  Future<bool> _readFlag(String key) async {
    try {
      return await _storage.read(key: key) == 'true';
    } on Object {
      return false;
    }
  }

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
