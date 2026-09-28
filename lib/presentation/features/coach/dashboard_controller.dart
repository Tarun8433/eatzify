import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// Everything the Clients tab draws, in one value.
///
/// Held together rather than as four independent states so the screen cannot render half-loaded —
/// a tile reading 48 clients above an empty list is worse than a moment of skeleton.
class CoachDesk {
  const CoachDesk({
    required this.summary,
    required this.clients,
    required this.invites,
    this.earnings,
    this.referral,
  });

  final CoachDashboard summary;
  final List<CoachClient> clients;

  /// An invite is a question and a client is an answered one. Kept apart on purpose: three open
  /// invites and no acceptances is nobody, and one merged count would read as three clients.
  final List<SentInvite> invites;

  /// Null when the earnings read failed. The rest of the screen is still worth showing — a partner
  /// whose ledger is briefly unreachable has not lost their client list.
  final CoachEarnings? earnings;
  final CoachReferral? referral;

  bool get isEmpty => summary.isEmpty && clients.isEmpty && invites.isEmpty;
}

/// The coach's Clients tab (D-200, D-201).
///
/// Five reads, one state. The roster and the counts come from endpoints that build both from the
/// same rows server-side, so a number can never disagree with the list under it.
class CoachDashboardController extends GetxController {
  CoachDashboardController({required this.coach});

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

    final (summary, roster, sent, money, code) = await (
      coach.dashboard(),
      coach.clients(),
      coach.sentInvites(),
      coach.earnings(),
      coach.referral(),
    ).wait;

    /// A failure in the three reads the screen is ABOUT fails the screen. Rendering half of it
    /// would quietly tell a coach they have no clients when the roster call is the one that broke.
    final failure =
        summary.fold<Failure?>((f) => f, (_) => null) ??
        roster.fold<Failure?>((f) => f, (_) => null) ??
        sent.fold<Failure?>((f) => f, (_) => null);

    if (failure != null) {
      state.value = Failed(failure);
      return;
    }

    // Earnings and the referral code are not. A partner whose ledger is briefly unreachable still
    // has a client list worth reading, and blanking the screen over it would be the wrong trade.
    final desk = CoachDesk(
      summary: summary.getOrElse(_noSummary),
      clients: roster.getOrElse(() => const []),
      invites: sent.getOrElse(() => const []),
      earnings: money.fold((_) => null, (e) => e),
      referral: code.fold((_) => null, (r) => r),
    );

    state.value = desk.isEmpty ? const Empty() : Ready(desk);
  }

  static CoachDashboard _noSummary() => const CoachDashboard(
    totalClients: 0,
    activeClients: 0,
    atRiskClients: 0,
    pendingInvites: 0,
    renewalsDue30d: 0,
    needsAttention: [],
  );
}
