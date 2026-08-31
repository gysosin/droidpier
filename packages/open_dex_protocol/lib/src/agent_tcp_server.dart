import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'envelope.dart';
import 'session_token.dart';

class AgentTcpServer {
  AgentTcpServer({required this.sessionToken});

  final String sessionToken;
  final StreamController<ProtocolEnvelope> _messages =
      StreamController<ProtocolEnvelope>.broadcast(sync: true);
  ServerSocket? _server;
  Socket? _client;
  StreamSubscription<Socket>? _connections;
  StreamSubscription<String>? _lines;
  bool _authenticated = false;

  Stream<ProtocolEnvelope> get messages => _messages.stream;

  int? get port => _server?.port;

  bool get isAuthenticated => _authenticated;

  Future<int> start({int port = 0}) async {
    if (_server != null) return _server!.port;
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _connections = _server!.listen(_accept);
    return _server!.port;
  }

  void _accept(Socket socket) {
    _client?.destroy();
    _lines?.cancel();
    _client = socket;
    _authenticated = false;
    _lines = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            ProtocolEnvelope envelope;
            try {
              envelope = ProtocolEnvelope.decode(line);
            } on ProtocolException {
              socket.destroy();
              return;
            }
            if (!_authenticated) {
              final token = envelope.data['sessionToken'];
              if (envelope.type != 'agent.hello' ||
                  token is! String ||
                  !SessionToken.matches(sessionToken, token)) {
                socket.destroy();
                return;
              }
              _authenticated = true;
            }
            _messages.add(envelope);
          },
          onDone: () => _authenticated = false,
          onError: (_) {
            _authenticated = false;
            socket.destroy();
          },
          cancelOnError: true,
        );
  }

  void send(ProtocolEnvelope envelope) {
    final client = _client;
    if (client == null || !_authenticated) {
      throw const ProtocolException('The Android agent is not authenticated.');
    }
    client.writeln(envelope.encode());
  }

  Future<void> close() async {
    await _lines?.cancel();
    await _connections?.cancel();
    _client?.destroy();
    await _server?.close();
    _authenticated = false;
    _client = null;
    _server = null;
    await _messages.close();
  }
}
