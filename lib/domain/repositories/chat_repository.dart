import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/chat.dart';

/// Coach ⇄ client chat (docs/02 FR-5.5, docs/09 §6).
///
/// The server re-checks the client's `chat` grant on every call, so any of these may come back
/// refused — a conversation can close in the middle of itself, and the app says so rather than
/// pretending the thread is still open.
abstract class ChatRepository {
  /// Who the caller can talk to right now, newest conversation first.
  Future<Either<Failure, List<ChatThread>>> threads();

  /// One thread, newest first. [before] pages backwards from a message's timestamp.
  Future<Either<Failure, List<ChatMessage>>> messages(int otherUserId, {DateTime? before});

  Future<Either<Failure, ChatMessage>> send(int otherUserId, String body);

  /// Everything the other side wrote in this thread has been seen.
  Future<Either<Failure, Unit>> markRead(int otherUserId);

  /// Messages arriving while the thread is open. Emits nothing when there is no live connection —
  /// the screen still works from [messages], which is why this is a stream and not a requirement.
  Stream<ChatMessage> live(int otherUserId);

  /// Opens the live connection for this thread, and closes the previous one.
  Future<void> watch(int otherUserId);

  /// Drops the live connection. Called when the screen goes away.
  Future<void> unwatch();
}
