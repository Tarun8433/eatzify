import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/chat_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/chat_socket.dart';
import 'package:health_pro/domain/entities/chat.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';

/// REST for everything that must work, the socket for everything that makes it feel live.
///
/// A send goes over the socket when one is up and over REST otherwise — but the REST answer is
/// what the screen keeps, because that is the row the server actually stored.
class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._remote, this._socket, {this.me});

  final ChatRemoteDataSource _remote;
  final ChatSocket _socket;

  /// The reader's own user id, for deciding which live messages are theirs.
  final int Function()? me;

  @override
  Future<Either<Failure, List<ChatThread>>> threads() => _remote.threads();

  @override
  Future<Either<Failure, List<ChatMessage>>> messages(int otherUserId, {DateTime? before}) =>
      _remote.messages(otherUserId, before: before);

  @override
  Future<Either<Failure, ChatMessage>> send(int otherUserId, String body) =>
      _remote.send(otherUserId, body);

  @override
  Future<Either<Failure, Unit>> markRead(int otherUserId) => _remote.markRead(otherUserId);

  @override
  Stream<ChatMessage> live(int otherUserId) => _socket.messages.where(
    // The socket is joined to one thread at a time, but a reconnect can overlap two: only what
    // belongs to this conversation reaches the screen.
    (message) => message.senderUserId == otherUserId || message.mine,
  );

  @override
  Future<void> watch(int otherUserId) => _socket.watch(otherUserId, me: me?.call());

  @override
  Future<void> unwatch() => _socket.close();
}
