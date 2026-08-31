import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test(
    'samples displayed frames separately and stops sampling after close',
    () async {
      final runtime = await Directory.systemTemp.createTemp(
        'droidpier-telemetry-test-',
      );
      addTearDown(() => runtime.delete(recursive: true));
      for (final name in ['scrcpy', 'scrcpy-server', 'ffmpeg']) {
        File('${runtime.path}/$name').createSync();
      }
      final executor = FakeExecutor();
      final textures = FakeTextureHost();
      final gateway = EmbeddedScrcpyWindowGateway(
        executable: '${runtime.path}/scrcpy',
        serverPath: '${runtime.path}/scrcpy-server',
        ffmpegExecutable: '${runtime.path}/ffmpeg',
        adb: AdbClient(executable: 'adb', executor: executor),
        textureHost: textures,
        processExecutor: executor,
        processLauncher: FakeLauncher(),
        telemetryInterval: const Duration(milliseconds: 20),
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
          packageName: 'com.android.settings',
          label: 'Settings',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final measurement = gateway.telemetry.firstWhere(
        (s) => (s.presentedFramesPerSecond ?? 0) > 0,
      );
      textures.statsValue = const WindowTextureStats(
        frames: 10,
        presentedFrames: 2,
        droppedFrames: 8,
        lastFrameMonotonicUs: 0,
        centerLuma: 0,
        probeLuma: 0,
      );
      final result = await measurement.timeout(const Duration(seconds: 1));
      expect(
        result.droppedFramesPerSecond,
        closeTo(result.presentedFramesPerSecond! * 4, .01),
      );
      expect(result.producedFramesPerSecond, isNull);
      await gateway.close(session.id);
      final stoppedAt = textures.statsReads;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(textures.statsReads, stoppedAt);
    },
  );

  test(
    'launches headless scrcpy into an RGBA texture and routes input',
    () async {
      final runtime = await Directory.systemTemp.createTemp(
        'open-dex-embedded-test-',
      );
      addTearDown(() async => runtime.delete(recursive: true));
      final scrcpy = File('${runtime.path}/scrcpy')..createSync();
      final server = File('${runtime.path}/scrcpy-server')..createSync();
      final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
      final executor = FakeExecutor();
      final launcher = FakeLauncher();
      final pointers = FakePointerLauncher();
      final textures = FakeTextureHost();
      final createdDisplays = <int>[];
      final gateway = EmbeddedScrcpyWindowGateway(
        executable: scrcpy.path,
        serverPath: server.path,
        ffmpegExecutable: ffmpeg.path,
        adb: AdbClient(executable: 'adb', executor: executor),
        textureHost: textures,
        processExecutor: executor,
        processLauncher: launcher,
        pointerProcessLauncher: pointers,
        surfaceRetireDelay: Duration.zero,
        onDisplayCreated: (_, displayId) async {
          createdDisplays.add(displayId);
        },
      );
      addTearDown(gateway.dispose);

      final telemetry = gateway.telemetry.first;
      final session = await gateway.launch(
        const DeviceSummary(
          id: 'device-1',
          name: 'Phone',
          connectionKind: DeviceConnectionKind.usb,
          status: DeviceStatus.authorized,
        ),
        const AndroidApplication(
          packageName: 'com.android.settings',
          label: 'Settings',
        ),
      );

      expect(session.displayId, 28);
      expect(session.surface?.textureId, 77);
      expect(session.surface?.pixelSize.width, 1280);
      expect(textures.waited, [77]);
      expect(createdDisplays, [28]);
      expect(launcher.starts, hasLength(2));
      expect(
        launcher.starts.first.arguments,
        containsAllInOrder([
          '-progress',
          'pipe:2',
          '-flags',
          'low_delay',
          '-probesize',
          '32',
          '-analyzeduration',
          '0',
          '-threads',
          '1',
          '-i',
          '-fps_mode',
          'passthrough',
          '-f',
          'rawvideo',
          '-pix_fmt',
          'rgba',
        ]),
      );
      expect(
        launcher.starts.last.arguments,
        containsAll([
          '--no-window',
          '--max-fps=60',
          '--video-bit-rate=8M',
          '--no-vd-system-decorations',
          '--capture-orientation=@',
          '--start-app=com.android.settings',
        ]),
      );
      expect(
        launcher.starts.last.arguments,
        isNot(contains('--start-app=+com.android.settings')),
      );

      expect(
        await telemetry,
        isA<WindowBackendTelemetry>()
            .having((sample) => sample.sessionId, 'sessionId', session.id)
            .having((sample) => sample.producedFramesPerSecond, 'fps', 60),
      );
      final outOfRangeTelemetry = gateway.telemetry.first;
      launcher.processes.first.stderrController.add(utf8.encode('fps=71.9\n'));
      expect(
        await outOfRangeTelemetry,
        isA<WindowBackendTelemetry>().having(
          (sample) => sample.producedFramesPerSecond,
          'fps',
          71.9,
        ),
      );

      await gateway.sendPointer(
        session.id,
        const WindowPointerSample(
          phase: WindowPointerPhase.down,
          x: 320,
          y: 180,
          pointerId: 1,
        ),
      );
      expect(pointers.commands.last, 'input -d 28 motionevent DOWN 320 180');

      pointers.blockInput = true;
      final queuedInput = [
        gateway.sendPointer(
          session.id,
          const WindowPointerSample(
            phase: WindowPointerPhase.move,
            x: 10,
            y: 10,
            pointerId: 1,
          ),
        ),
        gateway.sendPointer(
          session.id,
          const WindowPointerSample(
            phase: WindowPointerPhase.move,
            x: 20,
            y: 20,
            pointerId: 1,
          ),
        ),
        gateway.sendPointer(
          session.id,
          const WindowPointerSample(
            phase: WindowPointerPhase.move,
            x: 30,
            y: 30,
            pointerId: 1,
          ),
        ),
        gateway.sendPointer(
          session.id,
          const WindowPointerSample(
            phase: WindowPointerPhase.up,
            x: 30,
            y: 30,
            pointerId: 1,
          ),
        ),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(pointers.commands, hasLength(2));
      expect(pointers.maximumConcurrentInputCalls, 1);
      pointers.releaseInput();
      await Future.wait(queuedInput);
      expect(pointers.maximumConcurrentInputCalls, 1);
      expect(pointers.commands, [
        'input -d 28 motionevent DOWN 320 180',
        'input -d 28 motionevent MOVE 10 10',
        'input -d 28 motionevent MOVE 30 30',
        'input -d 28 motionevent UP 30 30',
      ]);

      final resized = await gateway.resizeSurface(
        session.id,
        const WindowPixelSize(width: 720, height: 1280),
      );
      expect(resized.id, session.id);
      expect(resized.displayId, 29);
      expect(resized.surface?.textureId, 78);
      expect(
        resized.surface?.pixelSize,
        const WindowPixelSize(width: 720, height: 1280),
      );
      expect(textures.waited, [77, 78]);
      expect(createdDisplays, [28, 29]);
      expect(launcher.starts, hasLength(4));
      expect(
        launcher.starts.last.arguments,
        contains('--new-display=720x1280/240'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(textures.closed, [77]);

      await gateway.sendPointer(
        session.id,
        const WindowPointerSample(
          phase: WindowPointerPhase.down,
          x: 900,
          y: 1400,
          pointerId: 2,
        ),
      );
      expect(pointers.commands.last, 'input -d 29 motionevent DOWN 719 1279');

      await gateway.close(session.id);
      expect(textures.closed, [77, 78]);
      expect(
        launcher.processes,
        everyElement(predicate<FakeProcess>((p) => p.killed)),
      );
    },
  );

  test('relaunches a portrait-only app on a portrait display', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-embedded-portrait-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final scrcpy = File('${runtime.path}/scrcpy')..createSync();
    final server = File('${runtime.path}/scrcpy-server')..createSync();
    final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
    final executor = FakeExecutor()
      ..stackOutput = '''
RootTask id=41 bounds=[0,0][720,1280] displayId=28 userId=0
  taskId=41: com.example.portrait/com.example.portrait.MainActivity
RootTask id=42 bounds=[0,0][720,1280] displayId=29 userId=0
  taskId=42: com.example.portrait/com.example.portrait.MainActivity
''';
    final launcher = FakeLauncher();
    final textures = FakeTextureHost();
    final gateway = EmbeddedScrcpyWindowGateway(
      executable: scrcpy.path,
      serverPath: server.path,
      ffmpegExecutable: ffmpeg.path,
      adb: AdbClient(executable: 'adb', executor: executor),
      textureHost: textures,
      processExecutor: executor,
      processLauncher: launcher,
      surfaceRetireDelay: Duration.zero,
      taskMonitorInterval: const Duration(days: 1),
    );
    addTearDown(gateway.dispose);

    final session = await gateway.launch(
      const DeviceSummary(
        id: 'device-1',
        name: 'Phone',
        connectionKind: DeviceConnectionKind.usb,
        status: DeviceStatus.authorized,
      ),
      const AndroidApplication(
        packageName: 'com.example.portrait',
        label: 'Portrait',
      ),
    );

    expect(session.displayId, 29);
    expect(
      session.surface?.pixelSize,
      const WindowPixelSize(width: 720, height: 1280),
    );
    expect(launcher.starts, hasLength(4));
    expect(
      launcher.starts.last.arguments,
      contains('--new-display=720x1280/240'),
    );
    expect(textures.waited, [77, 78]);
    expect(textures.closed, [77]);
    expect(
      launcher.processes.take(2),
      everyElement(predicate<FakeProcess>((process) => process.killed)),
    );

    await gateway.close(session.id);
    expect(textures.closed, [77, 78]);
  });

  test('retries then caches a preferred hardware AVC encoder', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-embedded-encoder-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final scrcpy = File('${runtime.path}/scrcpy')..createSync();
    final server = File('${runtime.path}/scrcpy-server')..createSync();
    final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
    final executor = FakeExecutor()
      ..encoderFailuresRemaining = 1
      ..encoderOutput = '''
[server] INFO: List of video encoders:
    --video-codec=h264 --video-encoder=OMX.qcom.video.encoder.avc     (hw) [vendor]
    --video-codec=h264 --video-encoder=c2.android.avc.encoder         (sw)
    --video-codec=h264 --video-encoder=OMX.google.h264.encoder        (sw)
''';
    final launcher = FakeLauncher();
    final gateway = EmbeddedScrcpyWindowGateway(
      executable: scrcpy.path,
      serverPath: server.path,
      ffmpegExecutable: ffmpeg.path,
      adb: AdbClient(executable: 'adb', executor: executor),
      textureHost: FakeTextureHost(),
      processExecutor: executor,
      processLauncher: launcher,
      surfaceRetireDelay: Duration.zero,
      taskMonitorInterval: const Duration(days: 1),
    );
    addTearDown(gateway.dispose);

    final session = await gateway.launch(
      const DeviceSummary(
        id: 'device-1',
        name: 'Phone',
        connectionKind: DeviceConnectionKind.usb,
        status: DeviceStatus.authorized,
      ),
      const AndroidApplication(
        packageName: 'com.example.encoder',
        label: 'Encoder',
      ),
    );
    await gateway.resizeSurface(
      session.id,
      const WindowPixelSize(width: 720, height: 1280),
    );
    await gateway.resizeSurface(
      session.id,
      const WindowPixelSize(width: 1280, height: 720),
    );

    expect(
      executor.calls.where(
        (call) => call.arguments.contains('--list-encoders'),
      ),
      hasLength(2),
    );
    final scrcpyStarts = launcher.starts
        .where((start) => start.executable == scrcpy.path)
        .toList();
    expect(
      scrcpyStarts.first.arguments,
      isNot(contains('--video-encoder=OMX.qcom.video.encoder.avc')),
    );
    expect(
      scrcpyStarts.skip(1),
      everyElement(
        predicate<ProcessStart>(
          (start) => start.arguments.contains(
            '--video-encoder=OMX.qcom.video.encoder.avc',
          ),
        ),
      ),
    );
    await gateway.close(session.id);
  });

  test('pauses task liveness polling during a pointer gesture', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-embedded-pointer-monitor-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final scrcpy = File('${runtime.path}/scrcpy')..createSync();
    final server = File('${runtime.path}/scrcpy-server')..createSync();
    final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
    final executor = FakeExecutor()
      ..stackOutput = '''
RootTask id=51 bounds=[0,0][1280,896] displayId=28 userId=0
  taskId=51: com.example.pointer/com.example.pointer.MainActivity
''';
    final pointers = FakePointerLauncher()..blockInput = true;
    final gateway = EmbeddedScrcpyWindowGateway(
      executable: scrcpy.path,
      serverPath: server.path,
      ffmpegExecutable: ffmpeg.path,
      adb: AdbClient(executable: 'adb', executor: executor),
      textureHost: FakeTextureHost(),
      processExecutor: executor,
      processLauncher: FakeLauncher(),
      pointerProcessLauncher: pointers,
      taskMonitorInterval: const Duration(milliseconds: 5),
    );
    addTearDown(gateway.dispose);

    final session = await gateway.launch(
      const DeviceSummary(
        id: 'device-1',
        name: 'Phone',
        connectionKind: DeviceConnectionKind.usb,
        status: DeviceStatus.authorized,
      ),
      const AndroidApplication(
        packageName: 'com.example.pointer',
        label: 'Pointer',
      ),
    );
    executor.calls.clear();
    final down = gateway.sendPointer(
      session.id,
      const WindowPointerSample(
        phase: WindowPointerPhase.down,
        x: 100,
        y: 100,
        pointerId: 1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(
      executor.calls.where((call) => call.arguments.contains('stack')),
      isEmpty,
    );

    pointers.releaseInput();
    await down;
    pointers.blockInput = false;
    await gateway.sendPointer(
      session.id,
      const WindowPointerSample(
        phase: WindowPointerPhase.up,
        x: 100,
        y: 100,
        pointerId: 1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(
      executor.calls.any((call) => call.arguments.contains('stack')),
      isTrue,
    );
    await gateway.close(session.id);
  });

  test('closes the stream when its Android application task exits', () async {
    final runtime = await Directory.systemTemp.createTemp(
      'open-dex-embedded-task-test-',
    );
    addTearDown(() async => runtime.delete(recursive: true));
    final scrcpy = File('${runtime.path}/scrcpy')..createSync();
    final server = File('${runtime.path}/scrcpy-server')..createSync();
    final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
    final executor = FakeExecutor()
      ..stackOutput = '''
RootTask id=51 bounds=[0,0][1280,720] displayId=28 userId=0
  taskId=51: com.example.exits/com.example.exits.MainActivity
''';
    final launcher = FakeLauncher();
    final textures = FakeTextureHost();
    final gateway = EmbeddedScrcpyWindowGateway(
      executable: scrcpy.path,
      serverPath: server.path,
      ffmpegExecutable: ffmpeg.path,
      adb: AdbClient(executable: 'adb', executor: executor),
      textureHost: textures,
      processExecutor: executor,
      processLauncher: launcher,
      surfaceRetireDelay: Duration.zero,
      taskMonitorInterval: const Duration(milliseconds: 5),
    );
    addTearDown(gateway.dispose);
    final exits = <WindowBackendExit>[];
    final exitSubscription = gateway.exits.listen(exits.add);
    addTearDown(exitSubscription.cancel);

    final session = await gateway.launch(
      const DeviceSummary(
        id: 'device-1',
        name: 'Phone',
        connectionKind: DeviceConnectionKind.usb,
        status: DeviceStatus.authorized,
      ),
      const AndroidApplication(
        packageName: 'com.example.exits',
        label: 'Exits',
      ),
    );
    textures.replacementFrameGate = Completer<void>();
    executor.stackOutput = '''
RootTask id=51 bounds=[0,0][720,1280] displayId=29 userId=0
  taskId=51: com.example.exits/com.example.exits.MainActivity
''';
    final resizing = gateway.resizeSurface(
      session.id,
      const WindowPixelSize(width: 720, height: 1280),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(exits, isEmpty);
    textures.replacementFrameGate!.complete();
    final resized = await resizing;
    expect(resized.displayId, 29);
    expect(
      launcher.starts.last.arguments,
      isNot(contains('--start-app=com.example.exits')),
    );
    expect(
      executor.calls.any(
        (call) => call.arguments
            .join(' ')
            .contains('shell am display move-stack 51 29'),
      ),
      isTrue,
    );

    executor.stackOutput = '';
    while (exits.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(exits.single.sessionId, session.id);
    expect(exits.single.exitCode, 20);
    expect(textures.closed, [77, 78]);
    expect(
      launcher.processes,
      everyElement(predicate<FakeProcess>((process) => process.killed)),
    );
  });

  test(
    'force-kills native processes that ignore graceful retirement',
    () async {
      final runtime = await Directory.systemTemp.createTemp(
        'open-dex-embedded-force-stop-test-',
      );
      addTearDown(() async => runtime.delete(recursive: true));
      final scrcpy = File('${runtime.path}/scrcpy')..createSync();
      final server = File('${runtime.path}/scrcpy-server')..createSync();
      final ffmpeg = File('${runtime.path}/ffmpeg')..createSync();
      final executor = FakeExecutor()
        ..stackOutput = '''
RootTask id=61 bounds=[0,0][1280,896] displayId=28 userId=0
  taskId=61: com.example.stubborn/com.example.stubborn.MainActivity
''';
      final launcher = FakeLauncher()..ignoreTerminate = true;
      final gateway = EmbeddedScrcpyWindowGateway(
        executable: scrcpy.path,
        serverPath: server.path,
        ffmpegExecutable: ffmpeg.path,
        adb: AdbClient(executable: 'adb', executor: executor),
        textureHost: FakeTextureHost(),
        processExecutor: executor,
        processLauncher: launcher,
        processStopTimeout: const Duration(milliseconds: 1),
        taskMonitorInterval: const Duration(days: 1),
      );
      addTearDown(gateway.dispose);

      final session = await gateway.launch(
        const DeviceSummary(
          id: 'device-1',
          name: 'Phone',
          connectionKind: DeviceConnectionKind.usb,
          status: DeviceStatus.authorized,
        ),
        const AndroidApplication(
          packageName: 'com.example.stubborn',
          label: 'Stubborn',
        ),
      );
      await gateway.close(session.id);

      expect(
        launcher.processes,
        everyElement(
          predicate<FakeProcess>(
            (process) =>
                process.killSignals.contains(ProcessSignal.sigterm) &&
                process.killSignals.contains(ProcessSignal.sigkill) &&
                process.killed,
          ),
        ),
      );
    },
  );
}

class FakeTextureHost implements WindowTextureHost {
  final closed = <int>[];
  final waited = <int>[];
  var _nextTextureId = 77;
  Completer<void>? replacementFrameGate;
  int statsReads = 0;
  WindowTextureStats statsValue = const WindowTextureStats(
    frames: 0,
    presentedFrames: 0,
    droppedFrames: 0,
    lastFrameMonotonicUs: 0,
    centerLuma: 0,
    probeLuma: 0,
  );

  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) async => _nextTextureId++;

  @override
  Future<void> waitForFirstFrame(
    int textureId, {
    required Duration timeout,
  }) async {
    waited.add(textureId);
    if (textureId > 77 && replacementFrameGate != null) {
      await replacementFrameGate!.future;
    }
  }

  @override
  Future<WindowTextureStats> stats(int textureId) async {
    statsReads++;
    return statsValue;
  }

  @override
  Future<void> closeTexture(int textureId) async => closed.add(textureId);
}

class ProcessCall {
  const ProcessCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class FakeExecutor implements ProcessExecutor {
  final calls = <ProcessCall>[];
  final inputCalls = <ProcessCall>[];
  var blockInput = false;
  var concurrentInputCalls = 0;
  var maximumConcurrentInputCalls = 0;
  Completer<void>? _inputGate;
  String stackOutput = '';
  String encoderOutput = '';
  int encoderFailuresRemaining = 0;

  void releaseInput() => _inputGate?.complete();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    final call = ProcessCall(executable, arguments);
    calls.add(call);
    final isEncoderLookup = arguments.contains('--list-encoders');
    if (isEncoderLookup && encoderFailuresRemaining > 0) {
      encoderFailuresRemaining -= 1;
      return const ProcessOutput(exitCode: 1, stdout: '', stderr: 'busy');
    }
    if (arguments.contains('motionevent')) {
      inputCalls.add(call);
      concurrentInputCalls += 1;
      if (concurrentInputCalls > maximumConcurrentInputCalls) {
        maximumConcurrentInputCalls = concurrentInputCalls;
      }
      if (blockInput) {
        _inputGate ??= Completer<void>();
        await _inputGate!.future;
      }
      concurrentInputCalls -= 1;
    }
    return ProcessOutput(
      exitCode: 0,
      stdout: arguments.contains('stack')
          ? stackOutput
          : isEncoderLookup
          ? encoderOutput
          : '',
      stderr: '',
    );
  }
}

class ProcessStart {
  const ProcessStart(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class FakePointerLauncher implements ManagedProcessLauncher {
  final commands = <String>[];
  final processes = <FakePointerProcess>[];
  bool blockInput = false;
  int concurrentInputCalls = 0;
  int maximumConcurrentInputCalls = 0;
  Completer<void>? _inputGate;

  void releaseInput() => _inputGate?.complete();

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  }) async {
    expect(arguments, ['-s', 'device-1', 'shell']);
    final process = FakePointerProcess(this);
    processes.add(process);
    return process;
  }

  Future<void> record(String data) async {
    commands.add(data.trim());
    concurrentInputCalls += 1;
    if (concurrentInputCalls > maximumConcurrentInputCalls) {
      maximumConcurrentInputCalls = concurrentInputCalls;
    }
    if (blockInput) {
      _inputGate ??= Completer<void>();
      await _inputGate!.future;
    }
    concurrentInputCalls -= 1;
  }
}

class FakePointerProcess implements ManagedProcess {
  FakePointerProcess(this.owner);

  final FakePointerLauncher owner;
  final exit = Completer<int>();

  @override
  Future<int> get exitCode => exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<void> writeInput(String data) => owner.record(data);

  @override
  Future<void> writeBytes(List<int> data) async {}

  @override
  Future<void> flushInput() async {}

  @override
  Future<void> closeInput() async {
    if (!exit.isCompleted) exit.complete(0);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!exit.isCompleted) exit.complete(0);
    return true;
  }
}

class FakeLauncher implements ManagedProcessLauncher {
  final starts = <ProcessStart>[];
  final processes = <FakeProcess>[];
  bool ignoreTerminate = false;

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  }) async {
    starts.add(ProcessStart(executable, arguments));
    final process = FakeProcess(ignoreTerminate: ignoreTerminate);
    processes.add(process);
    if (starts.length.isOdd) {
      scheduleMicrotask(
        () => process.stderrController.add(utf8.encode('fps=60.0\n')),
      );
    } else {
      final displayId = 27 + starts.length ~/ 2;
      scheduleMicrotask(
        () => process.stderrController.add(
          utf8.encode(
            '[server] INFO: New display: 1280x720/240 (id=$displayId)\n',
          ),
        ),
      );
    }
    return process;
  }
}

class FakeProcess implements ManagedProcess {
  FakeProcess({this.ignoreTerminate = false});

  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final exit = Completer<int>();
  final bool ignoreTerminate;
  final killSignals = <ProcessSignal>[];
  bool killed = false;

  @override
  Future<int> get exitCode => exit.future;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<void> writeInput(String data) async {}

  @override
  Future<void> writeBytes(List<int> data) async {}

  @override
  Future<void> flushInput() async {}

  @override
  Future<void> closeInput() async {
    if (!exit.isCompleted) exit.complete(0);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (ignoreTerminate && signal == ProcessSignal.sigterm) return true;
    killed = true;
    if (!exit.isCompleted) exit.complete(0);
    unawaited(stdoutController.close());
    unawaited(stderrController.close());
    return true;
  }
}
