import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';

/// The help screen (docs/14 §6): every conversation this person has had with support.
class TicketsController extends GetxController {
  TicketsController({required this.tickets});

  final TicketsRepository tickets;

  final state = Rx<ViewState<List<SupportTicket>>>(const Loading());

  /// A send is in flight. The button waits rather than opening two conversations.
  final sending = false.obs;

  /// The server's `user_message` from the last refusal (rule 7) — the "you already have several
  /// open" one, in particular, which has to be readable or the screen looks broken.
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await tickets.list();
    state.value = result.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));
  }

  /// Returns the new conversation, or null when the server refused it — [error] says why.
  Future<SupportTicket?> open({
    required String subject,
    required String body,
    String? requestId,
  }) async {
    if (sending.value) return null;

    sending.value = true;
    error.value = null;
    final result = await tickets.open(subject: subject, body: body, requestId: requestId);
    sending.value = false;

    return result.fold(
      (f) {
        error.value = f.userMessage;
        return null;
      },
      (ticket) {
        final current = state.value;
        final rows = current is Ready<List<SupportTicket>> ? current.data : const <SupportTicket>[];
        state.value = Ready([ticket, ...rows]);
        return ticket;
      },
    );
  }
}

/// One conversation, both sides of it.
class TicketThreadController extends GetxController {
  TicketThreadController({required this.tickets, required this.ticketId});

  final TicketsRepository tickets;
  final String ticketId;

  final state = Rx<ViewState<SupportThread>>(const Loading());
  final sending = false.obs;
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await tickets.thread(ticketId);
    // Never Empty: a conversation always has the message that started it.
    state.value = result.fold(Failed.new, Ready.new);
  }

  Future<bool> reply(String body) async {
    final text = body.trim();
    if (text.isEmpty || sending.value) return false;

    sending.value = true;
    error.value = null;
    final result = await tickets.reply(ticketId, text);
    sending.value = false;

    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      error.value = failure.userMessage;
      return false;
    }

    // The server decides the state the reply left it in — reopened, or still waiting on us — so
    // the screen re-reads rather than guessing.
    await load(quiet: true);
    return true;
  }
}
