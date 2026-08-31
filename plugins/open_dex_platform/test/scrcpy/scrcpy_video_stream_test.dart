import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test('parses device, codec, session metadata, and H.264 packets', () async {
    final input = StreamController<List<int>>();
    final parser = ScrcpyVideoStream(input.stream);
    final eventsFuture = parser.events.toList();
    final bytes = _streamBytes([
      _session(width: 1280, height: 720),
      _packet(flags: _configFlag, data: [0, 0, 0, 1, 103]),
      _packet(flags: _keyFrameFlag | 123, data: [0, 0, 0, 1, 101]),
      _packet(flags: 456, data: [0, 0, 1, 65]),
      _session(width: 720, height: 1280, clientResized: true),
    ]);

    input.add(bytes);
    await input.close();

    expect(await parser.deviceName, 'Redmi Note 7 Pro');
    expect(await parser.codecId, 0x68323634);
    final events = await eventsFuture;
    expect(events, hasLength(5));
    expect(
      events[0],
      isA<ScrcpySessionMeta>()
          .having((event) => event.width, 'width', 1280)
          .having((event) => event.height, 'height', 720)
          .having((event) => event.clientResized, 'clientResized', isFalse),
    );
    expect(
      events[1],
      isA<ScrcpyVideoPacket>()
          .having((event) => event.pts, 'pts', 0)
          .having((event) => event.isConfig, 'isConfig', isTrue)
          .having((event) => event.isKeyFrame, 'isKeyFrame', isFalse)
          .having((event) => event.data, 'data', [0, 0, 0, 1, 103]),
    );
    expect(
      events[2],
      isA<ScrcpyVideoPacket>()
          .having((event) => event.pts, 'pts', 123)
          .having((event) => event.isConfig, 'isConfig', isFalse)
          .having((event) => event.isKeyFrame, 'isKeyFrame', isTrue),
    );
    expect(
      events[3],
      isA<ScrcpyVideoPacket>()
          .having((event) => event.pts, 'pts', 456)
          .having((event) => event.isConfig, 'isConfig', isFalse)
          .having((event) => event.isKeyFrame, 'isKeyFrame', isFalse),
    );
    expect(
      events[4],
      isA<ScrcpySessionMeta>()
          .having((event) => event.width, 'width', 720)
          .having((event) => event.height, 'height', 1280)
          .having((event) => event.clientResized, 'clientResized', isTrue),
    );
  });

  test('parses a fully fragmented stream one byte at a time', () async {
    final input = StreamController<List<int>>();
    final parser = ScrcpyVideoStream(input.stream);
    final eventsFuture = parser.events.toList();
    final bytes = _streamBytes([
      _session(width: 832, height: 1280),
      _packet(
        flags: _keyFrameFlag | 987654,
        data: List<int>.generate(257, (i) => i & 0xff),
      ),
    ]);

    for (final byte in bytes) {
      input.add([byte]);
    }
    await input.close();

    expect(await parser.deviceName, 'Redmi Note 7 Pro');
    expect(await parser.codecId, 0x68323634);
    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(
      events.last,
      isA<ScrcpyVideoPacket>()
          .having((event) => event.pts, 'pts', 987654)
          .having((event) => event.isKeyFrame, 'isKeyFrame', isTrue)
          .having((event) => event.data.length, 'data length', 257),
    );
  });

  test(
    'buffers session and CONFIG events emitted before subscription',
    () async {
      final input = StreamController<List<int>>(sync: true);
      final parser = ScrcpyVideoStream(input.stream);
      final bytes = _streamBytes([
        _session(width: 1280, height: 896),
        _packet(flags: _configFlag, data: [0, 0, 0, 1, 103, 66]),
      ]);

      input.add(bytes);
      final eventsFuture = parser.events.toList();
      await input.close();

      final events = await eventsFuture;
      expect(events, hasLength(2));
      expect(parser.latestSessionMeta, same(events.first));
      expect(parser.latestConfig, same(events.last));
      expect(parser.latestConfig?.data, [0, 0, 0, 1, 103, 66]);
    },
  );

  test('keeps packet parsing consistent during synchronous re-entry', () async {
    final input = StreamController<List<int>>(sync: true);
    final parser = ScrcpyVideoStream(input.stream);
    final packets = <ScrcpyVideoPacket>[];
    late final StreamSubscription<ScrcpyVideoEvent> subscription;
    subscription = parser.events.listen((event) {
      if (event is! ScrcpyVideoPacket) return;
      packets.add(event);
      if (packets.length == 1) {
        input.add(_packet(flags: 222, data: [5, 6, 7, 8]));
      }
    });
    addTearDown(subscription.cancel);

    input.add(_streamPrefix());
    input.add(_packet(flags: 111, data: [1, 2, 3, 4]));
    await input.close();

    expect(packets.map((packet) => packet.pts), [111, 222]);
    expect(packets.map((packet) => packet.data), [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
    ]);
  });

  test(
    'fails codec metadata and events when video configuration failed',
    () async {
      final input = StreamController<List<int>>();
      final parser = ScrcpyVideoStream(input.stream);
      final eventError = Completer<Object>();
      final subscription = parser.events.listen(
        (_) {},
        onError: (Object error) => eventError.complete(error),
      );
      addTearDown(subscription.cancel);

      input.add(_streamPrefix(codecId: 1));
      await input.close();

      await expectLater(
        parser.codecId,
        throwsA(
          isA<ScrcpyVideoStreamException>().having(
            (error) => error.message,
            'message',
            contains('could not configure'),
          ),
        ),
      );
      expect(await eventError.future, isA<ScrcpyVideoStreamException>());
    },
  );
}

Uint8List _streamBytes(List<List<int>> messages) {
  final bytes = BytesBuilder(copy: false)..add(_streamPrefix());
  for (final message in messages) {
    bytes.add(message);
  }
  return bytes.takeBytes();
}

Uint8List _streamPrefix({int codecId = 0x68323634}) {
  final name = Uint8List(64);
  final encodedName = utf8.encode('Redmi Note 7 Pro');
  name.setRange(0, encodedName.length, encodedName);
  return (BytesBuilder(copy: false)
        ..add(name)
        ..add(_uint32(codecId)))
      .takeBytes();
}

Uint8List _session({
  required int width,
  required int height,
  bool clientResized = false,
}) =>
    (BytesBuilder(copy: false)
          ..add([0x80, 0, 0, clientResized ? 1 : 0])
          ..add(_uint32(width))
          ..add(_uint32(height)))
        .takeBytes();

Uint8List _packet({required int flags, required List<int> data}) =>
    (BytesBuilder(copy: false)
          ..add(_uint64(flags))
          ..add(_uint32(data.length))
          ..add(data))
        .takeBytes();

Uint8List _uint32(int value) => Uint8List.fromList([
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
]);

Uint8List _uint64(int value) => Uint8List.fromList([
  (value >> 56) & 0xff,
  (value >> 48) & 0xff,
  (value >> 40) & 0xff,
  (value >> 32) & 0xff,
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
]);

const _configFlag = 1 << 62;
const _keyFrameFlag = 1 << 61;
