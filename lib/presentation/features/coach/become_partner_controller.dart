import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// docs/12 §6 onboarding, one step at a time.
///
/// `Empty` is a real state here and not a failure: most accounts have never applied, and an empty
/// application is the screen that offers to start one.
class BecomePartnerController extends GetxController {
  BecomePartnerController({required this.coach});

  final CoachRepository coach;

  /// Which agreement the app showed. Sent with the acceptance, because "they agreed" is only
  /// evidence if it records to what (docs/12 §6).
  static const agreementVersion = 'v1';

  /// The coaching agreement's version (D-235). ⚠ Its text needs legal review before launch — the
  /// version is recorded now so every acceptance can later be matched to the words shown.
  static const coachingAgreementVersion = 'c1';

  final state = Rx<ViewState<CoachApplication>>(const Loading());
  final saving = false.obs;
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// [quiet] leaves the current application on screen while it reloads — see the account
  /// controller: pull-to-refresh must not blank the list the indicator hangs from.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await coach.application();
    result.fold(
      (f) => state.value = Failed(f),
      (a) => state.value = a == null ? const Empty() : Ready(a),
    );
  }

  Future<void> setDiscipline(CoachDiscipline discipline) =>
      _run(() => coach.setDiscipline(discipline));

  Future<void> acceptAgreement() => _run(() => coach.acceptAgreement(agreementVersion));

  /// docs/12 §6: level 3's partner half. The client's grant is the other half, and whichever lands
  /// second is what promotes — so this can return still at level 2, and that is correct.
  Future<void> acceptCoachingAgreement() =>
      _run(() => coach.acceptCoachingAgreement(coachingAgreementVersion));

  Future<void> attach({String? idFileId, String? qualificationFileId}) => _run(
    () => coach.attachDocuments(
      idDocumentFileId: idFileId,
      qualificationDocumentFileId: qualificationFileId,
    ),
  );

  Future<void> submit() => _run(coach.submit);

  /// Upload, then attach. Two steps because the bytes belong to the files module and only the id
  /// belongs to the application — a failed attach leaves an orphan file rather than a half-written
  /// application, which is the cheaper of the two to live with.
  Future<void> uploadDocument({
    required String filePath,
    required String fileName,
    required bool isIdDocument,
  }) async {
    saving.value = true;
    error.value = null;

    final uploaded = await coach.uploadDocument(filePath, fileName);
    final fileId = uploaded.fold<String?>((f) {
      error.value = f.userMessage;
      return null;
    }, (id) => id);

    if (fileId == null) {
      saving.value = false;
      return;
    }

    final attached = await coach.attachDocuments(
      idDocumentFileId: isIdDocument ? fileId : null,
      qualificationDocumentFileId: isIdDocument ? null : fileId,
    );
    attached.fold((f) => error.value = f.userMessage, (a) => state.value = Ready(a));

    saving.value = false;
  }

  /// One path for every write, so a refusal always lands in `error` and never leaves the screen
  /// showing a state the server rejected. Rule 7: the message is the server's, verbatim.
  Future<void> _run(Future<Either<Failure, CoachApplication>> Function() call) async {
    saving.value = true;
    error.value = null;

    final result = await call();
    result.fold((f) => error.value = f.userMessage, (a) => state.value = Ready(a));

    saving.value = false;
  }
}
