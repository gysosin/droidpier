import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../managed_process.dart';
import '../process_executor.dart';
import 'scrcpy_frames.dart';

abstract interface class H264DecoderCapabilityProbe {
  Future<bool> supportsVaapiH264(String ffmpegPath);
}

abstract interface class H264Decoder {
  Future<int> get exitCode;

  /// The decoder's last lines of diagnostic output, oldest first.
  ///
  /// Part of the interface rather than the implementation because the only
  /// moment this matters is a launch that timed out waiting for a first frame,
  /// and at that point the gateway holds the interface, not the process.
  List<String> get outputTail;

  void feed(ScrcpyVideoPacket packet);

  Future<void> get idle;

  Future<void> stop();
}

abstract interface class H264DecoderStarter {
  Future<H264Decoder> start({
    required String ffmpegPath,
    required String fifoPath,
    required Future<void> Function() resetVideo,
    ScrcpyVideoPacket? latestConfig,
  });
}

class SystemH264DecoderStarter implements H264DecoderStarter {
  const SystemH264DecoderStarter({
    this.processLauncher = const SystemManagedProcessLauncher(),
    this.capabilityProbe = const SystemH264DecoderCapabilityProbe(),
  });

  final ManagedProcessLauncher processLauncher;
  final H264DecoderCapabilityProbe capabilityProbe;

  @override
  Future<H264Decoder> start({
    required String ffmpegPath,
    required String fifoPath,
    required Future<void> Function() resetVideo,
    ScrcpyVideoPacket? latestConfig,
  }) => H264DecoderProcess.start(
    ffmpegPath: ffmpegPath,
    fifoPath: fifoPath,
    resetVideo: resetVideo,
    processLauncher: processLauncher,
    capabilityProbe: capabilityProbe,
    latestConfig: latestConfig,
  );
}

class SystemH264DecoderCapabilityProbe implements H264DecoderCapabilityProbe {
  const SystemH264DecoderCapabilityProbe({
    this.executor = const SystemProcessExecutor(),
    this.vainfoPath = '/usr/bin/vainfo',
  });

  final ProcessExecutor executor;
  final String vainfoPath;

  static final Map<String, Future<bool>> _lookups = {};

  @override
  // Safe to cache as a Future because _probe converts every failure to false;
  // this lookup must never retain a rejected Future.
  Future<bool> supportsVaapiH264(String ffmpegPath) => _lookups.putIfAbsent(
    '$ffmpegPath\u0000$vainfoPath',
    () => _probe(ffmpegPath),
  );

  Future<bool> _probe(String ffmpegPath) async {
    try {
      final decoders = await executor.run(ffmpegPath, const [
        '-hide_banner',
        '-decoders',
      ]);
      if (!decoders.succeeded ||
          !_h264Decoder.hasMatch('${decoders.stdout}\n${decoders.stderr}')) {
        return false;
      }
      // An H.264 decoder and a capable GPU do not mean this FFmpeg binary
      // includes VA-API. The bundled software-only build has neither the
      // driver dependency nor that hardware backend.
      final accelerators = await executor.run(ffmpegPath, const [
        '-hide_banner',
        '-hwaccels',
      ]);
      if (!accelerators.succeeded ||
          !RegExp(
            r'^\s*vaapi\s*$',
            multiLine: true,
          ).hasMatch('${accelerators.stdout}\n${accelerators.stderr}')) {
        return false;
      }
      final profiles = await executor.run(vainfoPath, const [
        '--display',
        'drm',
        '--device',
        _vaapiDevice,
      ]);
      return profiles.succeeded &&
          '${profiles.stdout}\n${profiles.stderr}'.contains('VAProfileH264');
    } on Object {
      return false;
    }
  }

  static final _h264Decoder = RegExp(r'^ V.*\bh264\s', multiLine: true);
}

class H264DecoderProcess implements H264Decoder {
  H264DecoderProcess._(this._process, this._resetVideo) {
    // Drain both streams. `captureOutput: true` creates the pipes whether or
    // not anyone reads them, and an unread pipe is two separate faults: the
    // decoder's own account of why it failed is discarded, and once 64 KiB of
    // unread output accumulates FFmpeg blocks writing to it and stops decoding
    // entirely. The first direct Gate 2 run failed as a bare
    // "produced no frame" timeout for exactly this reason — FFmpeg may well
    // have said what was wrong and nothing was listening.
    for (final Stream<List<int>> output in <Stream<List<int>>>[
      _process.stdout,
      _process.stderr,
    ]) {
      _outputSubscriptions.add(
        output
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(_recordOutputLine, onError: (Object _) {}),
      );
    }
  }

  void _recordOutputLine(String line) {
    if (line.trim().isEmpty) return;
    _outputTail.addLast(line);
    if (_outputTail.length > _outputTailLimit) _outputTail.removeFirst();
  }

  /// The decoder's last lines of diagnostic output, oldest first.
  ///
  /// Bounded so a decoder that fails once per frame cannot grow this without
  /// limit while the session stays alive.
  @override
  List<String> get outputTail => List<String>.unmodifiable(_outputTail);

  static const int _outputTailLimit = 40;
  final Queue<String> _outputTail = Queue<String>();
  final List<StreamSubscription<String>> _outputSubscriptions =
      <StreamSubscription<String>>[];

  static Future<H264DecoderProcess> start({
    required String ffmpegPath,
    required String fifoPath,
    required Future<void> Function() resetVideo,
    ManagedProcessLauncher processLauncher =
        const SystemManagedProcessLauncher(),
    H264DecoderCapabilityProbe capabilityProbe =
        const SystemH264DecoderCapabilityProbe(),
    ScrcpyVideoPacket? latestConfig,
  }) async {
    if (ffmpegPath.isEmpty) {
      throw ArgumentError.value(ffmpegPath, 'ffmpegPath', 'must not be empty');
    }
    if (fifoPath.isEmpty) {
      throw ArgumentError.value(fifoPath, 'fifoPath', 'must not be empty');
    }
    final useVaapi = await capabilityProbe.supportsVaapiH264(ffmpegPath);
    stderr.writeln(
      'open_dex H.264 decoder: ${useVaapi ? 'VA-API' : 'software'}',
    );
    final process = await processLauncher.start(ffmpegPath, [
      '-hide_banner',
      '-nostdin',
      // Overwrite the output target without prompting. The FIFO is created with
      // mkfifo before ffmpeg starts, so without this ffmpeg sees the path
      // already exists and exits with "File ... already exists" before decoding
      // a single frame. The legacy pipeline always passed -y; the direct
      // decoder did not, which is why it never rendered.
      '-y',
      '-loglevel',
      'error',
      '-flags',
      'low_delay',
      '-probesize',
      '32',
      '-analyzeduration',
      '0',
      '-threads',
      '1',
      if (useVaapi) ...const [
        '-hwaccel',
        'vaapi',
        '-hwaccel_device',
        _vaapiDevice,
      ],
      '-f',
      'h264',
      '-i',
      'pipe:0',
      '-an',
      '-fps_mode',
      'passthrough',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgba',
      fifoPath,
    ], captureOutput: true);
    final decoder = H264DecoderProcess._(process, resetVideo);
    if (latestConfig != null) decoder.feed(latestConfig);
    return decoder;
  }

  final ManagedProcess _process;
  final Future<void> Function() _resetVideo;
  final Queue<_DecoderWrite> _pending = Queue<_DecoderWrite>();
  Future<void> _drained = Future<void>.value();
  Future<void> _resetCompleted = Future<void>.value();
  ScrcpyVideoPacket? _latestConfig;
  Object? _writeError;
  StackTrace? _writeStackTrace;
  int _pendingBytes = 0;
  bool _draining = false;
  bool _dropping = false;
  bool _recoveryQueued = false;
  bool _closed = false;

  @override
  Future<int> get exitCode => _process.exitCode;

  int get pendingBytes => _pendingBytes;

  @override
  void feed(ScrcpyVideoPacket packet) {
    if (_closed) return;
    if (packet.isConfig) _latestConfig = packet;

    if (_dropping) {
      if (!packet.isKeyFrame || _recoveryQueued) return;
      _recoveryQueued = true;
      final config = _latestConfig;
      if (config != null) _enqueue(config.data);
      _enqueue(packet.data, completesRecovery: true);
      return;
    }

    if (_pendingBytes + packet.data.length > _maximumPendingBytes) {
      _beginDropping();
      if (packet.isKeyFrame) {
        _recoveryQueued = true;
        final config = _latestConfig;
        if (config != null) _enqueue(config.data);
        _enqueue(packet.data, completesRecovery: true);
      }
      return;
    }

    _enqueue(packet.data);
  }

  void _beginDropping() {
    _dropping = true;
    _recoveryQueued = false;
    while (_pending.isNotEmpty) {
      _pendingBytes -= _pending.removeFirst().bytes.length;
    }
    _resetCompleted = Future<void>.sync(_resetVideo).catchError((Object _) {});
  }

  void _enqueue(Uint8List bytes, {bool completesRecovery = false}) {
    _pending.add(
      _DecoderWrite(bytes: bytes, completesRecovery: completesRecovery),
    );
    _pendingBytes += bytes.length;
    if (_draining) return;
    _draining = true;
    _drained = _drain();
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      final write = _pending.removeFirst();
      try {
        await _process.writeBytes(write.bytes);
        await _process.flushInput();
      } on Object catch (error, stackTrace) {
        _writeError = error;
        _writeStackTrace = stackTrace;
        _pendingBytes -= write.bytes.length;
        while (_pending.isNotEmpty) {
          _pendingBytes -= _pending.removeFirst().bytes.length;
        }
        break;
      }
      _pendingBytes -= write.bytes.length;
      if (write.completesRecovery) {
        _dropping = false;
        _recoveryQueued = false;
      }
    }
    _draining = false;
  }

  @override
  Future<void> get idle async {
    do {
      final currentDrain = _drained;
      await currentDrain;
      if (identical(currentDrain, _drained) && !_draining) break;
    } while (true);
    await _resetCompleted;
    final error = _writeError;
    if (error != null) Error.throwWithStackTrace(error, _writeStackTrace!);
  }

  @override
  Future<void> stop() async {
    for (final StreamSubscription<String> subscription
        in _outputSubscriptions) {
      unawaited(subscription.cancel());
    }
    _outputSubscriptions.clear();
    if (_closed) return;
    _closed = true;
    while (_pending.isNotEmpty) {
      _pendingBytes -= _pending.removeFirst().bytes.length;
    }
    _process.kill();
    try {
      await _process.closeInput().timeout(const Duration(seconds: 1));
    } on Object {
      // A decoder that already exited has already closed its stdin.
    }
    await _drained.timeout(const Duration(seconds: 1), onTimeout: () {});
  }

  static const _maximumPendingBytes = 2 * 1024 * 1024;
}

const _vaapiDevice = '/dev/dri/renderD128';

class _DecoderWrite {
  const _DecoderWrite({required this.bytes, required this.completesRecovery});

  final Uint8List bytes;
  final bool completesRecovery;
}
