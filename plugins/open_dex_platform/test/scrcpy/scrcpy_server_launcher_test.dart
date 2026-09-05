import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  const device = DeviceSummary(
    id: 'device-1',
    name: 'Phone',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
  );

  test('launches the server with byte-exact arguments and cleans up', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-launcher-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashA;
    final processLauncher = _FakeLauncher();
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executable: '/tools/adb', executor: executor),
      processLauncher: processLauncher,
    );

    final handle = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abcd',
      displaySize: const WindowPixelSize(width: 1280, height: 720),
      dpi: 240,
      encoder: 'OMX.qcom.video.encoder.avc',
    );

    expect(processLauncher.executable, '/tools/adb');
    expect(processLauncher.captureOutput, isTrue);
    expect(processLauncher.lineBufferedOutput, isTrue);
    expect(processLauncher.arguments, [
      '-s',
      'device-1',
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server.jar',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '4.1',
      'scid=1234abcd',
      'log_level=info',
      'video=true',
      'audio=false',
      'control=true',
      'video_codec=h264',
      'video_bit_rate=8000000',
      'max_fps=60',
      'new_display=1280x720/240',
      'flex_display=true',
      'vd_system_decorations=false',
      'send_device_meta=true',
      'send_frame_meta=true',
      'send_stream_meta=true',
      'send_dummy_byte=false',
      'cleanup=true',
      'power_on=false',
      'stay_awake=false',
      'show_touches=false',
      'clipboard_autosync=false',
      'video_encoder=OMX.qcom.video.encoder.avc',
    ]);
    expect(
      executor.calls.where((call) => call.arguments.contains('push')),
      isEmpty,
    );
    expect(
      executor.calls.any(
        (call) => call.arguments.contains('localabstract:scrcpy_1234abcd'),
      ),
      isTrue,
    );

    processLauncher.process.addStderr(
      '[server] INFO: New display: 1280x720/240 (id=37)\n',
    );
    expect(await handle.displayId, 37);
    for (var index = 0; index < 45; index += 1) {
      processLauncher.process.addStderr('error-$index\n');
    }
    await Future<void>.delayed(Duration.zero);
    expect(handle.stderrTail, hasLength(40));
    expect(handle.stderrTail.first, 'error-5');

    await handle.stop();
    expect(processLauncher.process.killed, isTrue);
    expect(
      executor.calls.last.arguments,
      containsAllInOrder([
        'reverse',
        '--remove',
        'localabstract:scrcpy_1234abcd',
      ]),
    );
  });

  test('starts a mirror of the phone display with no display wait', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-launcher-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashA;
    final processLauncher = _FakeLauncher();
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executable: '/tools/adb', executor: executor),
      processLauncher: processLauncher,
    );

    final handle = await launcher.startMirror(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abcd',
    );

    expect(processLauncher.arguments, [
      '-s',
      'device-1',
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server.jar',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '4.1',
      'scid=1234abcd',
      'log_level=info',
      'video=true',
      'audio=false',
      // View only: one socket, no control channel, nothing to inject.
      'control=false',
      'video_codec=h264',
      'video_bit_rate=4000000',
      'max_fps=30',
      'max_size=540',
      'send_device_meta=true',
      'send_frame_meta=true',
      'send_stream_meta=true',
      'send_dummy_byte=false',
      'cleanup=true',
      'power_on=false',
      'stay_awake=false',
      'show_touches=false',
      'clipboard_autosync=false',
    ]);
    // Display 0 is the phone's own. scrcpy prints no "New display" line for
    // it, so the handle must not sit in the five-second wait the windows use.
    expect(await handle.displayId.timeout(const Duration(milliseconds: 50)), 0);
    await handle.stop();
  });

  test('pushes only when the device jar hash differs', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-hash-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashB;
    final processLauncher = _FakeLauncher();
    var hashCalls = 0;
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executor: executor),
      processLauncher: processLauncher,
      fileHasher: (_) async {
        hashCalls += 1;
        return _hashA;
      },
    );

    final first = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abce',
      displaySize: const WindowPixelSize(width: 1280, height: 720),
      dpi: 240,
    );
    final second = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41235,
      scid: '1234abcf',
      displaySize: const WindowPixelSize(width: 720, height: 1280),
      dpi: 240,
    );

    expect(hashCalls, 1);
    expect(
      executor.calls.where((call) => call.arguments.contains('push')),
      hasLength(1),
    );
    await first.stop();
    await second.stop();
  });

  test('retries a transient local hash failure', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-hash-retry-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashA;
    final processLauncher = _FakeLauncher();
    var attempts = 0;
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executor: executor),
      processLauncher: processLauncher,
      fileHasher: (_) async {
        attempts += 1;
        if (attempts == 1) throw StateError('temporarily busy');
        return _hashA;
      },
    );

    await expectLater(
      launcher.start(
        device: device,
        serverJarPath: jar.path,
        hostPort: 41234,
        scid: '1234abd0',
        displaySize: const WindowPixelSize(width: 1280, height: 720),
        dpi: 240,
      ),
      throwsStateError,
    );
    final handle = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abd0',
      displaySize: const WindowPixelSize(width: 1280, height: 720),
      dpi: 240,
    );

    expect(attempts, 2);
    await handle.stop();
  });

  test('bounds display discovery and includes the stderr tail', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-display-timeout-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashA;
    final processLauncher = _FakeLauncher();
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executor: executor),
      processLauncher: processLauncher,
    );

    final handle = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abd1',
      displaySize: const WindowPixelSize(width: 1280, height: 720),
      dpi: 240,
      displayTimeout: const Duration(milliseconds: 10),
    );
    processLauncher.process.addStderr('server is stuck\n');

    await expectLater(
      handle.displayId,
      throwsA(
        isA<ScrcpyServerLaunchException>()
            .having((error) => error.exitCode, 'exitCode', 24)
            .having(
              (error) => error.stderrTail,
              'stderrTail',
              contains('server is stuck'),
            ),
      ),
    );
    await handle.stop();
  });

  test('cancels display discovery when stopped before creation', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-scrcpy-display-cancel-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final jar = File('${runtime.path}/scrcpy-server')..createSync();
    final executor = _FakeExecutor()..remoteHash = _hashA;
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executor: executor),
      processLauncher: _FakeLauncher(),
    );
    final handle = await launcher.start(
      device: device,
      serverJarPath: jar.path,
      hostPort: 41234,
      scid: '1234abd2',
      displaySize: const WindowPixelSize(width: 1280, height: 720),
      dpi: 240,
      displayTimeout: const Duration(days: 1),
    );
    final cancelled = expectLater(
      handle.displayId,
      throwsA(
        isA<ScrcpyServerLaunchException>().having(
          (error) => error.message,
          'message',
          contains('stopped before creating'),
        ),
      ),
    );

    await handle.stop();
    await cancelled;
  });

  test('rejects server values containing shell metacharacters', () async {
    final executor = _FakeExecutor();
    final launcher = ScrcpyServerLauncher(
      adb: AdbClient(executor: executor),
      processLauncher: _FakeLauncher(),
    );

    await expectLater(
      () => launcher.start(
        device: device,
        serverJarPath: '/unused',
        hostPort: 41234,
        scid: '1234abcd',
        displaySize: const WindowPixelSize(width: 1280, height: 720),
        dpi: 240,
        encoder: 'encoder;reboot',
      ),
      throwsArgumentError,
    );
    expect(executor.calls, isEmpty);
  });
}

const _hashA =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _ProcessCall {
  const _ProcessCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeExecutor implements ProcessExecutor {
  final calls = <_ProcessCall>[];
  String remoteHash = _hashA;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    calls.add(_ProcessCall(executable, arguments));
    if (arguments.contains('sha256sum')) {
      return ProcessOutput(
        exitCode: 0,
        stdout: '$remoteHash  /data/local/tmp/scrcpy-server.jar\n',
        stderr: '',
      );
    }
    if (arguments.contains('push')) remoteHash = _hashA;
    return const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
  }
}

class _FakeLauncher implements ManagedProcessLauncher {
  String? executable;
  List<String> arguments = const [];
  bool captureOutput = false;
  bool lineBufferedOutput = false;
  final processes = <_FakeProcess>[];

  _FakeProcess get process => processes.last;

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
    this.lineBufferedOutput = lineBufferedOutput;
    final process = _FakeProcess();
    processes.add(process);
    return process;
  }
}

class _FakeProcess implements ManagedProcess {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exitCode = Completer<int>();
  bool killed = false;

  void addStderr(String value) => _stderr.add(value.codeUnits);

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<void> writeInput(String data) async {}

  @override
  Future<void> writeBytes(List<int> data) async {}

  @override
  Future<void> flushInput() async {}

  @override
  Future<void> closeInput() async {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    return true;
  }
}
