import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/chat.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';

/// Who the caller can talk to (docs/02 FR-5.5). Empty is a real answer: a client with no coach,
/// or a coach whose clients have not granted `chat`, has nobody to message.
class ThreadsController extends GetxController {
  ThreadsController({required this.chat});

  final ChatRepository chat;

  final state = Rx<ViewState<List<ChatThread>>>(const Loading());

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await chat.threads();
    state.value = result.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));
  }
}

/// One conversation.
///
/// The list is the SERVER's rows, newest first. The socket only adds what arrives while the screen
/// is open; if it never connects, the screen still works — that is why the send goes over REST and
/// the answer it returns is what gets kept.
class ChatController extends GetxController {
  ChatController({required this.chat, required this.otherUserId});

  final ChatRepository chat;
  final int otherUserId;

  final state = Rx<ViewState<List<ChatMessage>>>(const Loading());

  /// A send is in flight. The button waits rather than sending twice.
  final sending = false.obs;

  /// The server's `user_message` from the last refusal (rule 7) — including the one that says the
  /// conversation has been closed.
  final error = RxnString();

  StreamSubscription<ChatMessage>? _live;

  @override
  void onInit() {
    super.onInit();
    load();
    unawaited(chat.watch(otherUserId));
    _live = chat.live(otherUserId).listen(_arrive);
  }

  @override
  void onClose() {
    _live?.cancel();
    unawaited(chat.unwatch());
    super.onClose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await chat.messages(otherUserId);

    state.value = result.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));
    if (result.isRight()) unawaited(chat.markRead(otherUserId));
  }

  Future<bool> send(String body) async {
    final text = body.trim();
    if (text.isEmpty || sending.value) return false;

    sending.value = true;
    error.value = null;
    final result = await chat.send(otherUserId, text);
    sending.value = false;

    return result.fold(
      (f) {
        error.value = f.userMessage;
        return false;
      },
      (message) {
        _arrive(message);
        return true;
      },
    );
  }

  /// A message, from the socket or from a send. Keyed by id, because the socket echoes back what
  /// was just posted and a conversation that showed everything twice would be unreadable.
  void _arrive(ChatMessage message) {
    final current = state.value;
    final rows = current is Ready<List<ChatMessage>> ? current.data : const <ChatMessage>[];
    if (rows.any((m) => m.id == message.id)) return;

    state.value = Ready([message, ...rows]);
  }
}
