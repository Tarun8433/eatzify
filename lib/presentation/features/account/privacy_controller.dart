import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/privacy.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';

/// "Privacy & data" (docs/13 §3 and §9): what this person has agreed to, and the two rights that
/// change their account rather than a setting.
class PrivacyController extends GetxController {
  PrivacyController({required this.privacy});

  final PrivacyRepository privacy;

  final state = Rx<ViewState<PrivacyState>>(const Loading());

  /// Which consent is mid-flight, so one row can wait without freezing the screen.
  final saving = RxnString();

  /// A right is being exercised — an export built, a deletion asked for or called off.
  final working = false.obs;

  /// The server's `user_message` from the last refusal (rule 7).
  final error = RxnString();

  /// The last export the screen built, held so it can be shown without another round trip.
  final bundle = Rxn<Map<String, dynamic>>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await privacy.load();
    // Never Empty: everybody has consents, even if every one of them is off.
    state.value = result.fold(Failed.new, Ready.new);
  }

  /// The deletion that is running its seven days, if there is one.
  PrivacyRequest? get pendingDeletion {
    final current = state.value;
    if (current is! Ready<PrivacyState>) return null;
    for (final request in current.data.requests) {
      if (request.isDeletionPending) return request;
    }
    return null;
  }

  Future<void> setConsent(String type, {required bool granted}) async {
    if (saving.value != null) return;

    saving.value = type;
    error.value = null;
    final result = await privacy.setConsent(type, granted: granted);
    saving.value = null;

    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      error.value = failure.userMessage;
      return;
    }

    final rows = result.getOrElse(() => const []);
    final current = state.value;
    if (current is Ready<PrivacyState>) {
      state.value = Ready((consents: rows, requests: current.data.requests));
    }
  }

  /// Builds the copy and keeps it on screen. The link the server hands back is good for 24 hours,
  /// which is why the bundle is fetched immediately rather than saved for later.
  Future<bool> export() async {
    if (working.value) return false;

    working.value = true;
    error.value = null;
    final asked = await privacy.requestExport();
    final failure = asked.fold<Failure?>((f) => f, (_) => null);

    if (failure != null) {
      working.value = false;
      error.value = failure.userMessage;
      return false;
    }

    final request = asked.getOrElse(() => const PrivacyRequest(id: '', kind: 'export', status: ''));
    final fetched = await privacy.exportBundle(request.id);
    working.value = false;

    return fetched.fold(
      (f) {
        error.value = f.userMessage;
        return false;
      },
      (data) {
        bundle.value = data;
        unawaitedReload();
        return true;
      },
    );
  }

  Future<bool> requestDeletion() async {
    if (working.value) return false;

    working.value = true;
    error.value = null;
    final result = await privacy.requestDeletion();
    working.value = false;

    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      error.value = failure.userMessage;
      return false;
    }

    await load(quiet: true);
    return true;
  }

  Future<bool> cancelDeletion() async {
    if (working.value) return false;

    working.value = true;
    error.value = null;
    final result = await privacy.cancelDeletion();
    working.value = false;

    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      error.value = failure.userMessage;
      return false;
    }

    await load(quiet: true);
    return true;
  }

  /// Refreshes the request list after an export without making the caller wait for it — the bundle
  /// is already on screen and the list is only the history beside it.
  void unawaitedReload() {
    load(quiet: true).ignore();
  }
}
