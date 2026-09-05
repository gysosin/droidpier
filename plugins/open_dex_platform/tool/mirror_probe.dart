// Device check for the display mirror: runs the real gateway against the
// attached phone with a texture host that reads the RGBA pipe and counts
// frames. Prints the surface size, time to first frame, and the frame rate.
//
// dart run tool/mirror_probe.dart <adb> <scrcpy-server> <ffmpeg> [seconds]
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

Future<void> main(List<String> args) async {
  final adbPath = args[0];
  final jar = args[1];
  final ffmpeg = args[2];
  final seconds = args.length > 3 ? int.parse(args[3]) : 4;
  final maxSize = args.length > 4 ? int.parse(args[4]) : null;
  final stir = args.length > 5 && args[5] == 'stir';
  final countPackets = args.length > 6 && args[6] == 'count';
  final adb = AdbClient(executable: adbPath);
  final devices = await AdbDeviceGateway(adb).discoverDevices();
  final device = devices.firstWhere(
    (d) => d.status == DeviceStatus.authorized,
    orElse: () => throw StateError('no authorized device: $devices'),
  );
  stdout.writeln('device ${device.id} ${device.name}');
  final counting = _CountingDecoderStarter();
  final host = countPackets
      ? _PacketTextureHost(counting)
      : _CountingTextureHost();
  int framesNow(int id) => countPackets
      ? counting.decoders.last.packets
      : (host as _CountingTextureHost).framesFor(id);
  final gateway = DirectScrcpyDisplayMirrorGateway(
    mirrorStarter: ScrcpyServerLauncher(adb: adb),
    decoderStarter: countPackets ? counting : const SystemH264DecoderStarter(),
    serverJarPath: jar,
    ffmpegExecutable: ffmpeg,
    textureHost: host,
    maxSize: maxSize ?? 1080,
  );
  gateway.exits.listen(
    (e) => stdout.writeln('EXIT ${e.exitCode} ${e.details}'),
  );
  gateway.surfaceUpdates.listen(
    (s) => stdout.writeln(
      'SURFACE UPDATE ${s.surface.textureId} '
      '${s.surface.pixelSize.width}x${s.surface.pixelSize.height}',
    ),
  );
  final watch = Stopwatch()..start();
  try {
    final session = await gateway.start(device);
    stdout.writeln(
      'streaming ${session.surface.pixelSize.width}x'
      '${session.surface.pixelSize.height} texture ${session.surface.textureId} '
      'first frame after ${watch.elapsedMilliseconds} ms',
    );
    final before = framesNow(session.surface.textureId);
    final t0 = watch.elapsedMilliseconds;
    if (stir) {
      // Keep the launcher moving so the encoder has something to send.
      final end = watch.elapsedMilliseconds + seconds * 1000;
      var i = 0;
      while (watch.elapsedMilliseconds < end) {
        final (a, b) = i.isEven ? (900, 200) : (200, 900);
        await adb.shell(device.id, [
          'input',
          'swipe',
          '$a',
          '1200',
          '$b',
          '1200',
          '250',
        ]);
        i++;
      }
      stdout.writeln('swiped $i times during the window');
    } else {
      await Future<void>.delayed(Duration(seconds: seconds));
    }
    final after = framesNow(session.surface.textureId);
    final dt = (watch.elapsedMilliseconds - t0) / 1000;
    stdout.writeln(
      '${countPackets ? 'packets' : 'frames'} ${after - before} in '
      '${dt.toStringAsFixed(1)} s = ${((after - before) / dt).toStringAsFixed(1)} fps'
      '${countPackets ? ' (${counting.decoders.last.keyFrames} key frames)' : ''}',
    );
    await gateway.stop(session.id);
    stdout.writeln('stopped cleanly');
  } on BackendFailure catch (f) {
    stdout.writeln('FAILED ${f.error.message} | ${f.error.technicalDetails}');
  } finally {
    await gateway.dispose();
  }
  exit(0);
}

class _CountingTextureHost implements WindowTextureHost {
  final Map<int, _Reader> _readers = {};
  int _next = 1;

  int framesFor(int id) => _readers[id]?.frames ?? 0;

  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) async {
    final id = _next++;
    _readers[id] = _Reader(fifoPath, pixelSize.width * pixelSize.height * 4);
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
class _Reader {
  _Reader(String path, this.frameBytes) {
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

/// Counts packets at the socket boundary instead of decoding them: tells
/// whether the phone sends few frames or the decode side loses them.
class _CountingDecoderStarter implements H264DecoderStarter {
  final decoders = <_CountingDecoder>[];
  @override
  Future<H264Decoder> start({
    required String ffmpegPath,
    required String fifoPath,
    required Future<void> Function() resetVideo,
    ScrcpyVideoPacket? latestConfig,
  }) async {
    final d = _CountingDecoder();
    decoders.add(d);
    return d;
  }
}

class _CountingDecoder implements H264Decoder {
  final Completer<int> _exit = Completer<int>();
  final Completer<void> first = Completer<void>();
  int packets = 0;
  int keyFrames = 0;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  List<String> get outputTail => const [];
  @override
  Future<void> get idle async {}
  @override
  void feed(ScrcpyVideoPacket packet) {
    if (packet.isConfig) return;
    packets++;
    if (packet.isKeyFrame) keyFrames++;
    if (!first.isCompleted) first.complete();
  }

  @override
  Future<void> stop() async {
    if (!_exit.isCompleted) _exit.complete(0);
  }
}

class _PacketTextureHost implements WindowTextureHost {
  _PacketTextureHost(this.starter);
  final _CountingDecoderStarter starter;
  int _next = 1;
  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) async => _next++;
  @override
  Future<void> waitForFirstFrame(int textureId, {required Duration timeout}) =>
      starter.decoders.last.first.future.timeout(timeout);
  @override
  Future<WindowTextureStats> stats(int textureId) async => WindowTextureStats(
    frames: starter.decoders.last.packets,
    presentedFrames: 0,
    lastFrameMonotonicUs: 0,
    centerLuma: 0,
    probeLuma: 0,
    droppedFrames: 0,
  );
  @override
  Future<void> closeTexture(int textureId) async {}
}
