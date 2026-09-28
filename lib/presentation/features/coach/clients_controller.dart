import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// The two halves of a coach's Clients tab, kept apart on purpose.
///
/// An invite is a question and a client is an answered one. The tab shows both because a coach
/// needs to know what is outstanding, and it never merges them: three open invites and no
/// acceptances is nobody, and a combined count would read as three clients.
class CoachDesk {
  const CoachDesk({required this.clients, required this.invites});

  final List<CoachClient> clients;
  final List<SentInvite> invites;

  bool get isEmpty => clients.isEmpty && invites.isEmpty;
}

/// The coach's Clients tab.
///
/// Two reads, one state. The roster comes from `GET /coach/clients`, which is driven by consent
/// grants rather than by a role (D-195) — so a coach whose clients have all revoked sees an empty
/// list, and that is correct rather than broken.
///
/// `Empty` means nothing asked AND nobody accepted, which for a new coach is the ordinary state.
class ClientsController extends GetxController {
  ClientsController({required this.coach});

  final CoachRepository coach;

  final state = Rx<ViewState<CoachDesk>>(const Loading());

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// [quiet] keeps the list on screen while it reloads, for pull-to-refresh: the indicator hangs
  /// from the list, so flipping to `Loading` would blank the widget being held.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();

    // Together, because the tab renders both and two sequential round trips would show the roster
    // arriving after the invites on every open.
    final (roster, sent) = await (coach.clients(), coach.sentInvites()).wait;

    // A failure in EITHER read fails the screen. Rendering half of it would quietly tell a coach
    // they have no clients when the roster call is the one that broke.
    final failure =
        roster.fold<Failure?>((f) => f, (_) => null) ?? sent.fold<Failure?>((f) => f, (_) => null);

    if (failure != null) {
      state.value = Failed(failure);
      return;
    }

    final desk = CoachDesk(
      clients: roster.getOrElse(() => const []),
      invites: sent.getOrElse(() => const []),
    );
    state.value = desk.isEmpty ? const Empty() : Ready(desk);
  }
}
