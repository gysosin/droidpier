import 'dart:async';
import 'dart:io';

import 'envelope.dart';
import 'session_token.dart';

class CompanionWebSocketServer {
  CompanionWebSocketServer({required this.sessionToken});

  final String sessionToken;
  final StreamController<ProtocolEnvelope> _messages =
      StreamController<ProtocolEnvelope>.broadcast(sync: true);
  final StreamController<ProtocolException> _errors =
      StreamController<ProtocolException>.broadcast(sync: true);
  HttpServer? _server;
  WebSocket? _client;
  StreamSubscription<HttpRequest>? _requests;
  StreamSubscription<dynamic>? _frames;
  bool _authenticated = false;

  Stream<ProtocolEnvelope> get messages => _messages.stream;

  Stream<ProtocolException> get errors => _errors.stream;

  int? get port => _server?.port;

  bool get isAuthenticated => _authenticated;

  Future<int> start({int port = 0}) async {
    if (_server != null) return _server!.port;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _requests = _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final candidate = request.headers.value('X-Open-Dex-Token');
    if (request.uri.path != '/companion' ||
        candidate == null ||
        !SessionToken.matches(sessionToken, candidate) ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(
      request,
      compression: CompressionOptions.compressionOff,
    );
    await _frames?.cancel();
    await _client?.close(WebSocketStatus.goingAway, 'replaced');
    _client = socket;
    _authenticated = true;
    _frames = socket.listen(
      (frame) {
        if (frame is! String) return;
        try {
          _messages.add(ProtocolEnvelope.decode(frame));
        } on ProtocolException catch (error) {
          _errors.add(error);
          socket.close(
            WebSocketStatus.unsupportedData,
            'invalid protocol envelope',
          );
        }
      },
      onDone: () => _authenticated = false,
      onError: (_) => _authenticated = false,
      cancelOnError: true,
    );
  }

  void send(ProtocolEnvelope envelope) {
    final client = _client;
    if (client == null || !_authenticated) {
      throw const ProtocolException(
        'The Android companion is not authenticated.',
      );
    }
    client.add(envelope.encode());
  }

  Future<void> close() async {
    await _frames?.cancel();
    await _requests?.cancel();
    await _client?.close(WebSocketStatus.normalClosure, 'server stopped');
    await _server?.close(force: true);
    _authenticated = false;
    _client = null;
    _server = null;
    await _messages.close();
    await _errors.close();
  }
}
