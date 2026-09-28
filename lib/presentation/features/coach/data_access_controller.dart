import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// docs/10 §3's "Who can see my data".
///
/// `Empty` is the common and healthy state: most people have never given anyone access.
class DataAccessController extends GetxController {
  DataAccessController({required this.coach});

  final CoachRepository coach;

  final state = Rx<ViewState<List<DataAccess>>>(const Loading());
  final error = RxnString();

  /// Which coach is mid-revoke, so only that row shows a spinner rather than the whole list.
  final revoking = RxnInt();

  /// Open requests, deliberately NOT part of [state]. A person with no granted access but one
  /// pending invite is still `Empty` as far as the access list is concerned, and folding the two
  /// together would either hide the request behind an empty state or claim access that nobody has
  /// agreed to yet.
  final invites = <CoachInvite>[].obs;

  /// Which invite is mid-answer, so one row spins instead of the screen.
  final answering = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await coach.dataAccess();
    result.fold(
      (f) => state.value = Failed(f),
      (rows) => state.value = rows.isEmpty ? const Empty() : Ready(rows),
    );
    await _loadInvites();
  }

  /// Never fails the screen. The access list is what this page is ABOUT; a request that could not
  /// be fetched must not replace an answer the user came here to read.
  Future<void> _loadInvites() async {
    final result = await coach.invites();
    result.fold((_) => invites.clear(), invites.assignAll);
  }

  /// Yes. This is the only call in the app that turns an ask into access, so it goes through the
  /// server and then re-reads BOTH lists — the invite leaves one and a grant joins the other.
  Future<void> accept(String inviteId) => _answer(inviteId, coach.acceptInvite);

  /// No. Same shape, and just as final: declining creates nothing.
  Future<void> decline(String inviteId) => _answer(inviteId, coach.declineInvite);

  Future<void> _answer(String inviteId, Future<Either<Failure, Unit>> Function(String) call) async {
    answering.value = inviteId;
    error.value = null;

    final result = await call(inviteId);
    await result.fold(
      (f) async => error.value = f.userMessage,
      // Reloaded rather than patched: the server decides what both lists say now.
      (_) async => load(),
    );

    answering.value = null;
  }

  /// One tap, no confirmation dialog. docs/10 §3 calls a retention dark pattern out by name, and
  /// "are you sure you want to stop sharing your health data" is the shape one takes.
  Future<void> revoke(int coachUserId) async {
    revoking.value = coachUserId;
    error.value = null;

    final result = await coach.revokeAccess(coachUserId);
    await result.fold(
      (f) async => error.value = f.userMessage,
      // Reloaded rather than patched in place: the server decides what the list says now, and a
      // locally-edited row would be the app's guess at an answer it can simply ask for.
      (_) async => load(),
    );

    revoking.value = null;
  }
}
