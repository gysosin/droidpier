import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test(
    'launches scrcpy with argument arrays and pinned runtime paths',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'open-dex-scrcpy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final executable = File('${directory.path}/scrcpy')..createSync();
      final server = File('${directory.path}/scrcpy-server')..createSync();
      final launcher = _FakeLauncher();
      final gateway = ScrcpyWindowGateway(
        executable: executable.path,
        serverPath: server.path,
        adbExecutable: '/tools/adb',
        processLauncher: launcher,
      );
      addTearDown(gateway.dispose);

      final session = await gateway.launch(
        const DeviceSummary(
          id: 'device-1',
          name: 'Test phone',
          connectionKind: DeviceConnectionKind.usb,
          status: DeviceStatus.authorized,
        ),
        const AndroidApplication(
          packageName: 'com.example.demo',
          label: 'Demo',
        ),
      );

      expect(session.id, startsWith('scrcpy-'));
      expect(launcher.arguments, contains('--start-app=com.example.demo'));
      expect(
        launcher.arguments,
        isNot(contains('--start-app=+com.example.demo')),
      );
      expect(launcher.arguments, contains('--new-display=1280x720/240'));
      expect(launcher.arguments, contains('--max-fps=60'));
      expect(launcher.arguments, contains('--print-fps'));
      expect(launcher.captureOutput, isTrue);
      expect(launcher.lineBufferedOutput, isTrue);
      expect(launcher.environment['ADB'], '/tools/adb');
      expect(launcher.environment['SCRCPY_SERVER_PATH'], server.path);

      final sample = gateway.telemetry.first;
      launcher.process.addStdout('INFO: 59.8 fps\n');
      expect((await sample).producedFramesPerSecond, 59.8);
    },
  );

  test('rejects invalid package names before starting scrcpy', () async {
    final directory = await Directory.systemTemp.createTemp('open-dex-scrcpy-');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/scrcpy')..createSync();
    final server = File('${directory.path}/scrcpy-server')..createSync();
    final launcher = _FakeLauncher();
    final gateway = ScrcpyWindowGateway(
      executable: executable.path,
      serverPath: server.path,
      processLauncher: launcher,
    );
    addTearDown(gateway.dispose);

    await expectLater(
      gateway.launch(
        const DeviceSummary(
          id: 'device-1',
          name: 'Test phone',
          connectionKind: DeviceConnectionKind.usb,
          status: DeviceStatus.authorized,
        ),
        const AndroidApplication(packageName: 'bad;name', label: 'Unsafe'),
      ),
      throwsA(isA<Object>()),
    );
    expect(launcher.arguments, isEmpty);
  });
}

class _FakeLauncher implements ManagedProcessLauncher {
  List<String> arguments = const [];
  Map<String, String> environment = const {};
  bool captureOutput = false;
  bool lineBufferedOutput = false;
  final process = _FakeProcess();

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  }) async {
    this.arguments = arguments;
    this.environment = environment;
    this.captureOutput = captureOutput;
    this.lineBufferedOutput = lineBufferedOutput;
    return process;
  }
}

class _FakeProcess implements ManagedProcess {
  final _exitCode = Completer<int>();
  final _stdout = StreamController<List<int>>.broadcast();
  final _stderr = StreamController<List<int>>.broadcast();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  void addStdout(String value) => _stdout.add(value.codeUnits);

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
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    _stdout.close();
    _stderr.close();
    return true;
  }
}
