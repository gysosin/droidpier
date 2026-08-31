import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test('starts ffmpeg with the low-latency raw H.264 argument list', () async {
    final launcher = _FakeLauncher();

    final decoder = await H264DecoderProcess.start(
      ffmpegPath: '/opt/ffmpeg',
      fifoPath: '/tmp/open-dex-raw.fifo',
      processLauncher: launcher,
      capabilityProbe: const _FixedCapabilityProbe(false),
      resetVideo: () async {},
    );

    expect(launcher.executable, '/opt/ffmpeg');
    expect(launcher.arguments, const [
      '-hide_banner',
      '-nostdin',
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
      '/tmp/open-dex-raw.fifo',
    ]);
    expect(launcher.captureOutput, isTrue);
    await decoder.stop();
  });

  test(
    'adds VA-API arguments only after the capability probe passes',
    () async {
      final launcher = _FakeLauncher();

      final decoder = await H264DecoderProcess.start(
        ffmpegPath: '/usr/bin/ffmpeg',
        fifoPath: '/tmp/open-dex-raw.fifo',
        processLauncher: launcher,
        capabilityProbe: const _FixedCapabilityProbe(true),
        resetVideo: () async {},
      );

      expect(
        launcher.arguments,
        containsAllInOrder(const [
          '-hwaccel',
          'vaapi',
          '-hwaccel_device',
          '/dev/dri/renderD128',
          '-f',
          'h264',
        ]),
      );
      await decoder.stop();
    },
  );

  test('writes the retained CONFIG before packets after startup', () async {
    final launcher = _FakeLauncher();
    final config = _packet([0, 0, 0, 1, 103], config: true);
    final key = _packet([0, 0, 0, 1, 101], key: true);

    final decoder = await H264DecoderProcess.start(
      ffmpegPath: '/usr/bin/ffmpeg',
      fifoPath: '/tmp/open-dex-raw.fifo',
      processLauncher: launcher,
      capabilityProbe: const _FixedCapabilityProbe(false),
      latestConfig: config,
      resetVideo: () async {},
    );
    decoder.feed(key);
    await decoder.idle;

    expect(launcher.process.writes, [config.data, key.data]);
    await decoder.stop();
  });

  test('stalled decoder drops until keyframe and resets once', () async {
    final launcher = _FakeLauncher()..process.blockFlushes = true;
    var resets = 0;
    final config = _packet([7, 8, 9], config: true);
    final decoder = await H264DecoderProcess.start(
      ffmpegPath: '/usr/bin/ffmpeg',
      fifoPath: '/tmp/open-dex-raw.fifo',
      processLauncher: launcher,
      capabilityProbe: const _FixedCapabilityProbe(false),
      latestConfig: config,
      resetVideo: () async => resets++,
    );

    decoder.feed(_packet(Uint8List(2 * 1024 * 1024)));
    decoder.feed(_packet([1, 2, 3]));
    decoder.feed(_packet([4, 5, 6]));
    decoder.feed(_packet([10, 11], key: true));
    decoder.feed(_packet([12, 13]));
    await Future<void>.delayed(Duration.zero);

    expect(resets, 1);
    launcher.process.releaseFlushes();
    await decoder.idle;
    expect(launcher.process.writes, [
      config.data,
      config.data,
      [10, 11],
    ]);
    await decoder.stop();
  });
}

ScrcpyVideoPacket _packet(
  List<int> bytes, {
  bool config = false,
  bool key = false,
}) => ScrcpyVideoPacket(
  pts: 0,
  isConfig: config,
  isKeyFrame: key,
  data: Uint8List.fromList(bytes),
);

class _FixedCapabilityProbe implements H264DecoderCapabilityProbe {
  const _FixedCapabilityProbe(this.result);

  final bool result;

  @override
  Future<bool> supportsVaapiH264(String ffmpegPath) async => result;
}

class _FakeLauncher implements ManagedProcessLauncher {
  final _FakeProcess process = _FakeProcess();
  String? executable;
  List<String> arguments = const [];
  bool captureOutput = false;

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.captureOutput = captureOutput;
    return process;
  }
}

class _FakeProcess implements ManagedProcess {
  final writes = <List<int>>[];
  final _exitCode = Completer<int>();
  Completer<void>? _flushGate;
  bool blockFlushes = false;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<void> writeInput(String data) async {}

  @override
  Future<void> writeBytes(List<int> data) async {
    writes.add(List<int>.from(data));
  }

  @override
  Future<void> flushInput() {
    if (!blockFlushes) return Future<void>.value();
    return (_flushGate ??= Completer<void>()).future;
  }

  void releaseFlushes() {
    blockFlushes = false;
    _flushGate?.complete();
    _flushGate = null;
  }

  @override
  Future<void> closeInput() async {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    return true;
  }
}
