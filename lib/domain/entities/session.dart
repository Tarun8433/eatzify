/// An authenticated session. docs/09 §3.
///
/// The refresh token is the sensitive half — it is the only thing that can mint new access tokens,
/// and docs/09 says reuse of a rotated refresh token revokes the whole family. It never leaves
/// secure storage and is never logged.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.roles,
    required this.onboardingRequired,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final List<String> roles;

  /// From `/auth/otp/verify`. The server decides whether onboarding is still needed — the app must
  /// not infer it from whether a profile happens to be cached.
  final bool onboardingRequired;

  bool get isCoach => roles.contains('coach');

  Session copyWith({String? accessToken, String? refreshToken, bool? onboardingRequired}) =>
      Session(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        userId: userId,
        roles: roles,
        onboardingRequired: onboardingRequired ?? this.onboardingRequired,
      );

  /// Deliberately omits both tokens. docs/13: no credential or PII in a log line, ever.
  @override
  String toString() => 'Session(userId: $userId, roles: $roles)';
}
