import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';

/// D-265: `eatzify://offer/<code>` links, from cold start and while running.
///
/// The link carries an opaque code and nothing else, so the only thing this decides is WHEN to
/// open it: straight away for somebody signed in and past onboarding, otherwise once they are. A
/// code waiting for sign-in is kept in [SecureStore] (rule 11) so it survives the app being closed
/// in between. Whether the offer exists, and whose it is, is the server's answer when it opens.
class OfferLinkController extends GetxController {
  OfferLinkController({
    required this.links,
    required this.session,
    required this.store,
    required this.open,
  });

  /// Every link the app is opened with — `app_links`' stream carries the cold-start one too.
  final Stream<Uri> links;
  final SessionController session;
  final SecureStore store;

  /// Shows the offer sheet. The UI's business; this only says when.
  final void Function(String code) open;

  /// `base64url`, 16–64 long: the server's codes are 22+, and anything else is not one of ours.
  static final _codePattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  StreamSubscription<Uri>? _links;
  Worker? _status;

  /// The code waiting for sign-in, in memory as well as on disk: a link that arrives while the
  /// session is still restoring must not depend on a keychain write finishing first.
  String? _pending;

  /// The code in `eatzify://offer/<code>`, or null for any other link — another scheme, another
  /// host, extra path segments, or a code of the wrong shape.
  static String? offerCode(Uri uri) {
    if (uri.scheme != 'eatzify' || uri.host != 'offer') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    return _codePattern.hasMatch(segments.single) ? segments.single : null;
  }

  @override
  void onInit() {
    super.onInit();
    _links = links.listen(_onLink, onError: (_) {});
    _status = ever(session.status, _onStatus);
  }

  @override
  void onClose() {
    unawaited(_links?.cancel());
    _status?.dispose();
    super.onClose();
  }

  Future<void> _onLink(Uri uri) async {
    final code = offerCode(uri);
    if (code == null) return;
    if (session.status.value == AuthStatus.signedIn) {
      open(code);
      return;
    }
    _pending = code;
    await store.writePendingOfferCode(code);
  }

  Future<void> _onStatus(AuthStatus status) async {
    if (status != AuthStatus.signedIn) return;
    final code = _pending ?? await store.readPendingOfferCode();
    if (code == null) return;
    // Cleared before it opens, so a refused offer is shown once rather than on every sign-in.
    _pending = null;
    await store.clearPendingOfferCode();
    open(code);
  }
}
