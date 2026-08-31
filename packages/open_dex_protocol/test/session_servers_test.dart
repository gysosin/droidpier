import 'dart:io';

import 'package:open_dex_protocol/open_dex_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('session tokens are random and URL safe', () {
    final first = SessionToken.generate();
    final second = SessionToken.generate();

    expect(first, isNot(second));
    expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{32,}$')));
    expect(SessionToken.matches(first, first), isTrue);
    expect(SessionToken.matches(first, second), isFalse);
  });

  test(
    'agent server rejects a wrong token and accepts the expected token',
    () async {
      final server = AgentTcpServer(sessionToken: 'a' * 43);
      addTearDown(server.close);
      final port = await server.start();

      final rejected = await Socket.connect(InternetAddress.loopbackIPv4, port);
      rejected.writeln(_hello('wrong-token').encode());
      await rejected.flush();
      await rejected.drain<void>().timeout(const Duration(seconds: 2));
      expect(server.isAuthenticated, isFalse);

      final accepted = await Socket.connect(InternetAddress.loopbackIPv4, port);
      accepted.writeln(_hello('a' * 43).encode());
      await accepted.flush();
      final message = await server.messages.first.timeout(
        const Duration(seconds: 2),
      );

      expect(message.type, 'agent.hello');
      expect(server.isAuthenticated, isTrue);
      accepted.destroy();
    },
  );

  test('companion server authenticates the WebSocket header', () async {
    final server = CompanionWebSocketServer(sessionToken: 'b' * 43);
    addTearDown(server.close);
    final port = await server.start();

    await expectLater(
      WebSocket.connect('ws://127.0.0.1:$port/companion'),
      throwsA(isA<WebSocketException>()),
    );

    final socket = await WebSocket.connect(
      'ws://127.0.0.1:$port/companion',
      headers: {'X-Open-Dex-Token': 'b' * 43},
    );
    addTearDown(socket.close);
    socket.add(_companionHello().encode());
    final message = await server.messages.first.timeout(
      const Duration(seconds: 2),
    );

    expect(message.type, 'companion.hello');
    expect(server.isAuthenticated, isTrue);
  });
}

ProtocolEnvelope _hello(String token) => ProtocolEnvelope(
  id: 'agent-hello',
  type: 'agent.hello',
  timestamp: DateTime.utc(2026, 8, 24),
  data: {'sessionToken': token},
);

ProtocolEnvelope _companionHello() => ProtocolEnvelope(
  id: 'companion-hello',
  type: 'companion.hello',
  timestamp: DateTime.utc(2026, 8, 24),
);
