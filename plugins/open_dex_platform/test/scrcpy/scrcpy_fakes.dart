/// Fakes for the scrcpy pipeline shared by the window and mirror gateway
/// tests: a server handle, a decoder, a texture host, and byte builders for
/// the stream a scrcpy-server would write.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

class FakeServerHandle implements ScrcpyServerSession {
  final _exitCode = Completer<int>();
  bool stopped = false;

  @override
  Future<int> get displayId async => 44;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  List<String> get stderrTail => const [];

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_exitCode.isCompleted) _exitCode.complete(0);
  }

  void fail(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }
}

class FakeDecoderStarter implements H264DecoderStarter {
  final decoders = <FakeDecoder>[];

  FakeDecoder get decoder => decoders.single;

  @override
  Future<H264Decoder> start({
    required String ffmpegPath,
    required String fifoPath,
    required Future<void> Function() resetVideo,
    ScrcpyVideoPacket? latestConfig,
  }) async {
    final decoder = FakeDecoder();
    decoder.initialConfig = latestConfig;
    decoders.add(decoder);
    return decoder;
  }
}

class FakeDecoder implements H264Decoder {
  final _exitCode = Completer<int>();
  final packets = <ScrcpyVideoPacket>[];
  ScrcpyVideoPacket? initialConfig;
  bool stopped = false;
  List<String> output = const <String>[];

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  List<String> get outputTail => output;

  @override
  void feed(ScrcpyVideoPacket packet) => packets.add(packet);

  @override
  Future<void> get idle async {}

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_exitCode.isCompleted) _exitCode.complete(0);
  }

  void fail(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }
}

class FakeTextureHost implements WindowTextureHost {
  final createdSizes = <WindowPixelSize>[];
  final waited = <int>[];
  final closed = <int>[];
  final frameGates = <int, Completer<void>>{};
  var _nextTexture = 91;
  int frames = 1;
  int presentedFrames = 1;
  int droppedFrames = 0;

  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) async {
    createdSizes.add(pixelSize);
    return _nextTexture++;
  }

  @override
  Future<void> waitForFirstFrame(
    int textureId, {
    required Duration timeout,
  }) async {
    waited.add(textureId);
    await frameGates[textureId]?.future;
  }

  @override
  Future<WindowTextureStats> stats(int textureId) async => WindowTextureStats(
    frames: frames,
    presentedFrames: presentedFrames,
    lastFrameMonotonicUs: 0,
    centerLuma: 0,
    probeLuma: 0,
    droppedFrames: droppedFrames,
  );

  @override
  Future<void> closeTexture(int textureId) async => closed.add(textureId);
}

class FakeExecutor implements ProcessExecutor {
  const FakeExecutor();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async => const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
}

Uint8List videoBytes(List<List<int>> messages) {
  final name = Uint8List(64);
  name.setRange(0, 5, 'Phone'.codeUnits);
  final bytes = BytesBuilder(copy: false)
    ..add(name)
    ..add(u32(0x68323634));
  for (final message in messages) {
    bytes.add(message);
  }
  return bytes.takeBytes();
}

Uint8List sessionMeta({
  required int width,
  required int height,
  bool clientResized = false,
}) =>
    (BytesBuilder(copy: false)
          ..add([0x80, 0, 0, clientResized ? 1 : 0])
          ..add(u32(width))
          ..add(u32(height)))
        .takeBytes();

Uint8List videoPacket({
  bool config = false,
  bool key = false,
  required List<int> bytes,
}) =>
    (BytesBuilder(copy: false)
          ..add(u64((config ? 1 << 62 : 0) | (key ? 1 << 61 : 0)))
          ..add(u32(bytes.length))
          ..add(bytes))
        .takeBytes();

Uint8List u32(int value) => Uint8List.fromList(
  [
    value >> 24,
    value >> 16,
    value >> 8,
    value,
  ].map((byte) => byte & 0xff).toList(),
);

Uint8List u64(int value) => Uint8List.fromList(
  [
    value >> 56,
    value >> 48,
    value >> 40,
    value >> 32,
    value >> 24,
    value >> 16,
    value >> 8,
    value,
  ].map((byte) => byte & 0xff).toList(),
);

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TimeoutException('The test condition did not become true.');
}
