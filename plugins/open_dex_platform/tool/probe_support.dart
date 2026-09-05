/// Shared by the device probes: a texture host that reads the decoder's RGBA
/// pipe and counts whole frames, standing in for the native texture the app
/// uses so a probe can measure the pipeline without a window on screen.
library;

import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

class CountingTextureHost implements WindowTextureHost {
  final Map<int, PipeReader> _readers = {};
  int _next = 1;

  int framesFor(int id) => _readers[id]?.frames ?? 0;

  /// Raw bytes the pipe has delivered, whole frames or not.
  int bytesFor(int id) => _readers[id]?.bytes ?? 0;

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
/// Counts whole frames as they leave the decoder's pipe.
///
/// Deliberately an ordinary async read on this isolate rather than a blocking
/// read on another one: a window at 720x1280 pushes ~110 MB/s of RGBA, and a
/// tight synchronous reader at that rate starves the isolate that is feeding
/// the decoder — which looks like the pipeline hanging. The stream applies
/// backpressure instead, so the count is a floor on what arrived, not an
/// exact frame tally.
class PipeReader {
  PipeReader(String path, this.frameBytes) {
    _sub = File(path).openRead().listen(
      (chunk) {
        bytes += chunk.length;
        final whole = bytes ~/ frameBytes;
        if (whole > frames) {
          frames = whole;
          if (!first.isCompleted) first.complete();
        }
      },
      onError: (Object error) => stdout.writeln('pipe error: $error'),
      cancelOnError: true,
    );
  }

  final int frameBytes;
  final Completer<void> first = Completer<void>();
  int frames = 0;
  int bytes = 0;
  StreamSubscription<List<int>>? _sub;

  void close() => _sub?.cancel();
}
