import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test('serializes every host control message byte-for-byte', () {
    expect(
      ScrcpyControlMessages.injectKey(
        action: ScrcpyKeyAction.down,
        keycode: 29,
      ),
      _hex('00000000001d0000000000000000'),
    );
    expect(
      ScrcpyControlMessages.injectKey(action: ScrcpyKeyAction.up, keycode: 29),
      _hex('00010000001d0000000000000000'),
    );
    expect(ScrcpyControlMessages.injectText('Hi'), _hex('01000000024869'));
    expect(
      ScrcpyControlMessages.injectTouch(
        action: ScrcpyTouchAction.down,
        x: 100,
        y: 200,
        screenWidth: 1280,
        screenHeight: 720,
      ),
      _hex('0200fffffffffffffffe00000064000000c8050002d0ffff0000000000000000'),
    );
    expect(
      ScrcpyControlMessages.injectTouch(
        action: ScrcpyTouchAction.up,
        x: 100,
        y: 200,
        screenWidth: 1280,
        screenHeight: 720,
      ),
      _hex('0201fffffffffffffffe00000064000000c8050002d000000000000000000000'),
    );
    expect(
      ScrcpyControlMessages.injectScroll(
        x: 100,
        y: 200,
        screenWidth: 1280,
        screenHeight: 720,
        horizontal: 1,
        vertical: -16,
      ),
      _hex('0300000064000000c8050002d00800800000000000'),
    );
    expect(ScrcpyControlMessages.getClipboard(), _hex('0800'));
    expect(
      ScrcpyControlMessages.setClipboard(sequence: 1, text: 'ok', paste: true),
      _hex('09000000000000000101000000026f6b'),
    );
    expect(ScrcpyControlMessages.startApp('com.a'), _hex('1005636f6d2e61'));
    expect(ScrcpyControlMessages.resetVideo(), _hex('11'));
    expect(ScrcpyControlMessages.resizeDisplay(1280, 720), _hex('15050002d0'));
  });

  test('clamps scroll fixed point values to signed 16-bit bounds', () {
    expect(
      ScrcpyControlMessages.injectScroll(
        x: 0,
        y: 0,
        screenWidth: 1,
        screenHeight: 1,
        horizontal: 32,
        vertical: -32,
      ).sublist(13, 17),
      _hex('7fff8000'),
    );
  });

  test('coalesces pending moves while preserving down and up order', () async {
    final pair = await _socketPair();
    addTearDown(pair.close);
    final channel = ScrcpyControlChannel(pair.client);
    final received = BytesBuilder(copy: false);
    final expected = BytesBuilder(copy: false)
      ..add(
        ScrcpyControlMessages.injectTouch(
          action: ScrcpyTouchAction.down,
          x: 1,
          y: 2,
          screenWidth: 1280,
          screenHeight: 720,
        ),
      )
      ..add(
        ScrcpyControlMessages.injectTouch(
          action: ScrcpyTouchAction.move,
          x: 30,
          y: 40,
          screenWidth: 1280,
          screenHeight: 720,
        ),
      )
      ..add(
        ScrcpyControlMessages.injectTouch(
          action: ScrcpyTouchAction.up,
          x: 30,
          y: 40,
          screenWidth: 1280,
          screenHeight: 720,
        ),
      );
    final expectedBytes = expected.takeBytes();
    final allReceived = Completer<void>();
    final subscription = pair.server.listen((chunk) {
      received.add(chunk);
      if (received.length >= expectedBytes.length && !allReceived.isCompleted) {
        allReceived.complete();
      }
    });
    addTearDown(subscription.cancel);

    final writes = [
      channel.injectTouch(
        action: ScrcpyTouchAction.down,
        x: 1,
        y: 2,
        screenWidth: 1280,
        screenHeight: 720,
      ),
      channel.injectTouch(
        action: ScrcpyTouchAction.move,
        x: 10,
        y: 20,
        screenWidth: 1280,
        screenHeight: 720,
      ),
      channel.injectTouch(
        action: ScrcpyTouchAction.move,
        x: 30,
        y: 40,
        screenWidth: 1280,
        screenHeight: 720,
      ),
      channel.injectTouch(
        action: ScrcpyTouchAction.up,
        x: 30,
        y: 40,
        screenWidth: 1280,
        screenHeight: 720,
      ),
    ];
    await Future.wait(writes);
    await allReceived.future.timeout(const Duration(seconds: 2));

    expect(received.takeBytes(), expectedBytes);
    await channel.close();
  });

  test('parses fragmented clipboard messages from the device', () async {
    final pair = await _socketPair();
    addTearDown(pair.close);
    final clipboard = Completer<String>();
    final channel = ScrcpyControlChannel(
      pair.client,
      onClipboard: clipboard.complete,
    );
    final message = Uint8List.fromList([
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      7,
      2,
      0,
      1,
      0,
      2,
      0xaa,
      0xbb,
      0,
      0,
      0,
      0,
      5,
      ...utf8.encode('hello'),
    ]);
    for (final byte in message) {
      pair.server.add([byte]);
      await pair.server.flush();
    }

    expect(await clipboard.future.timeout(const Duration(seconds: 2)), 'hello');
    await channel.close();
  });
}

Uint8List _hex(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), '');
  return Uint8List.fromList([
    for (var offset = 0; offset < compact.length; offset += 2)
      int.parse(compact.substring(offset, offset + 2), radix: 16),
  ]);
}

Future<_SocketPair> _socketPair() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final clientFuture = Socket.connect(listener.address, listener.port);
  final server = await listener.first;
  final client = await clientFuture;
  return _SocketPair(listener: listener, client: client, server: server);
}

class _SocketPair {
  const _SocketPair({
    required this.listener,
    required this.client,
    required this.server,
  });

  final ServerSocket listener;
  final Socket client;
  final Socket server;

  Future<void> close() async {
    client.destroy();
    server.destroy();
    await listener.close();
  }
}
