import 'dart:async';

import 'package:health_pro/domain/entities/chat.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// The live half of the chat (docs/02 FR-5.5).
///
/// **Nothing depends on it.** The screen reads and sends over REST; this only makes the other
/// side's message appear without a refresh. A socket that never connects — a captive wifi, a proxy
/// that blocks upgrades — costs the conversation nothing.
///
/// The token travels in the handshake, never in the URL: a query string ends up in proxy logs, and
/// this one would carry a session.
class ChatSocket {
  ChatSocket({required this.baseUrl, required this.token});

  /// The API's own base, minus its `/api/v1` path — a socket namespace is not a REST route.
  final String baseUrl;

  /// How to get the current access token. Read on every connect, so a refreshed token is used.
  final String? Function() token;

  io.Socket? _socket;
  int? _thread;

  final _messages = StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage> get messages => _messages.stream;

  /// Opens (or re-points) the connection at one conversation. [me] decides which bubbles are the
  /// reader's own, because the broadcast says who WROTE a message rather than whose it is.
  Future<void> watch(int otherUserId, {int? me}) async {
    final access = token();
    if (access == null) return;

    _thread = otherUserId;

    final socket =
        _socket ??
        io.io(
          '${_origin(baseUrl)}/chat',
          io.OptionBuilder()
              .setTransports(['websocket'])
              .setAuth({'token': access})
              .enableReconnection()
              .build(),
        );

    socket
      ..off('message')
      ..on('message', (data) {
        if (data is! Map) return;
        _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(data), me: me));
      })
      ..onConnect((_) => socket.emit('join', {'other_user_id': _thread}))
      ..connect();

    _socket = socket;
    if (socket.connected) socket.emit('join', {'other_user_id': otherUserId});
  }

  /// Send over the socket when one is up. Returns false when it is not — the caller then posts it,
  /// which is the path that always works.
  bool send(int otherUserId, String body) {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;

    socket.emit('send', {'other_user_id': otherUserId, 'body': body});
    return true;
  }

  Future<void> close() async {
    _socket?.dispose();
    _socket = null;
    _thread = null;
  }

  /// `http://host:3001/api/v1` → `http://host:3001`.
  static String _origin(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null).toString();
  }
}
