/// Shared by the device probes: a texture host that reads the RGBA pipe on
/// an isolate and counts whole frames, so a probe measures the pipeline and
/// not its own event loop.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

class CountingTextureHost implements WindowTextureHost {
  final Map<int, PipeReader> _readers = {};
  int _next = 1;

  int framesFor(int id) => _readers[id]?.frames ?? 0;

  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) async {
    final id = _next++;
    _readers[id] = PipeReader(fifoPath, pixelSize.width * pixelSize.height * 4);
    return id;
  }

  @override
  Future<void> waitForFirstFrame(int textureId, {required Duration timeout}) =>
      _readers[textureId]!.first.future.timeout(timeout);

  @override
  Future<WindowTextureStats> stats(int textureId) async {
    final r = _readers[textureId]!;
    return WindowTextureStats(
      frames: r.frames,
      presentedFrames: r.frames,
      lastFrameMonotonicUs: 0,
      centerLuma: 0,
      probeLuma: 0,
      droppedFrames: 0,
    );
  }

  @override
  Future<void> closeTexture(int textureId) async =>
      _readers.remove(textureId)?.close();
}

/// Reads the RGBA pipe on its own isolate with large synchronous reads, so
/// the measurement is of the pipeline, not of the probe's own event loop.
class PipeReader {
  PipeReader(String path, this.frameBytes) {
    final port = ReceivePort();
    port.listen((Object? message) {
      if (message is int) {
        frames = message;
        if (!first.isCompleted) first.complete();
      } else {
        stdout.writeln('pipe: $message');
      }
    });
    _port = port;
    Isolate.spawn(_pump, (
      path,
      frameBytes,
      port.sendPort,
    )).then((i) => _isolate = i);
  }

  static void _pump((String, int, SendPort) args) {
    final (path, frameBytes, out) = args;
    final file = File(path).openSync();
    final buffer = Uint8List(4 << 20);
    var bytes = 0;
    var frames = 0;
    while (true) {
      final n = file.readIntoSync(buffer);
      if (n <= 0) break;
      bytes += n;
      final f = bytes ~/ frameBytes;
      if (f > frames) {
        frames = f;
        out.send(frames);
      }
    }
    out.send('closed after $bytes bytes');
  }

  final int frameBytes;
  final Completer<void> first = Completer<void>();
  int frames = 0;
  ReceivePort? _port;
  Isolate? _isolate;
  void close() {
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
  }
}
