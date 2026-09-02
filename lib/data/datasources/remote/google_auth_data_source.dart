import 'package:google_sign_in/google_sign_in.dart';

/// Google's SDK, kept behind the data layer.
///
/// It lives here and not in `LoginController` for the reason the controller rules give: a
/// controller has no Flutter imports, and `google_sign_in` is a platform plugin. What crosses the
/// boundary is one function returning one string.
///
/// This produces the ID TOKEN only. The app never decides who the user is from it — the token goes
/// to `POST /auth/google`, and the server verifies it against Google's keys.
class GoogleAuthDataSource {
  /// Supplied at build time, because these are per-project OAuth credentials rather than secrets
  /// the app can guess:
  ///
  /// ```sh
  /// --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
  /// ```
  ///
  /// The server one is what makes the token's audience match the backend that has to verify it, so
  /// it gates the whole feature ([isConfigured]): with no value, the button is never drawn. A
  /// sign-in option that is certain to fail is worse than one that is absent.
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get isConfigured => _serverClientId.isNotEmpty;

  /// `initialize` is idempotent per process but not free, so it runs once.
  static var _initialised = false;

  /// The signed-in user's ID token, or null if they backed out.
  ///
  /// Cancelling is NOT an error: closing the Google sheet is a decision, and answering it with red
  /// text reads as a fault the user has to fix. Everything else throws, and the caller reports it.
  Future<String?> idToken() async {
    final google = GoogleSignIn.instance;
    if (!_initialised) {
      await google.initialize(
        // Android reads its client id from `google-services.json`; iOS has no such file here, so
        // the id is passed in. Null rather than empty — the plugin treats an empty string as a
        // configured-but-broken id and fails with a less useful message.
        clientId: _iosClientId.isEmpty ? null : _iosClientId,
        serverClientId: _serverClientId,
      );
      _initialised = true;
    }

    try {
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
