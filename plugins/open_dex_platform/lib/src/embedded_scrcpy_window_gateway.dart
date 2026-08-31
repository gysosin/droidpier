import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import 'adb_client.dart';
import 'managed_process.dart';
import 'process_executor.dart';
import 'scrcpy/display_orientation.dart';

/// Streams a headless scrcpy recording into a Flutter Linux RGBA texture.
class EmbeddedScrcpyWindowGateway
    implements WindowGateway, ResizableWindowGateway {
  EmbeddedScrcpyWindowGateway({
    required this.executable,
    required this.serverPath,
    required this.ffmpegExecutable,
    required this.adb,
    required this.textureHost,
    this.processLauncher = const SystemManagedProcessLauncher(),
    this.pointerProcessLauncher = const SystemManagedProcessLauncher(),
    this.processExecutor = const SystemProcessExecutor(),
    this.startTimeout = const Duration(seconds: 15),
    this.processStopTimeout = const Duration(seconds: 3),
    this.surfaceRetireDelay = const Duration(milliseconds: 34),
    this.taskMonitorInterval = const Duration(seconds: 5),
    this.pixelSize = const WindowPixelSize(width: 1280, height: 896),
    this.onDisplayCreated,
  }) {
    if (taskMonitorInterval <= Duration.zero) {
      throw ArgumentError.value(
        taskMonitorInterval,
        'taskMonitorInterval',
        'must be greater than zero',
      );
    }
    if (processStopTimeout <= Duration.zero) {
      throw ArgumentError.value(
        processStopTimeout,
        'processStopTimeout',
        'must be greater than zero',
      );
    }
  }

  final String executable;
  final String serverPath;
  final String ffmpegExecutable;
  final AdbClient adb;
  final WindowTextureHost textureHost;
  final ManagedProcessLauncher processLauncher;
  final ManagedProcessLauncher pointerProcessLauncher;
  final ProcessExecutor processExecutor;
  final Duration startTimeout;
  final Duration processStopTimeout;
  final Duration surfaceRetireDelay;
  final Duration taskMonitorInterval;
  final WindowPixelSize pixelSize;
  final Future<void> Function(DeviceSummary device, int displayId)?
  onDisplayCreated;
  final StreamController<WindowBackendExit> _exits =
      StreamController<WindowBackendExit>.broadcast(sync: true);
  final StreamController<WindowBackendTelemetry> _telemetry =
      StreamController<WindowBackendTelemetry>.broadcast(sync: true);
  final Map<String, _EmbeddedSession> _sessions = {};
  final Map<String, String?> _videoEncoders = {};
  final Map<String, Future<String?>> _videoEncoderLookups = {};
  final Set<Future<void>> _retiring = {};
  final Map<String, Future<void>> _sessionRetirements = {};
  Timer? _taskMonitor;
  bool _taskMonitorActive = false;
  var _sequence = 0;

  @override
  Stream<WindowBackendExit> get exits => _exits.stream;

  @override
  Stream<WindowBackendTelemetry> get telemetry => _telemetry.stream;

  @override
  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  }) async {
    _validateRuntime(device, application);
    final resolvedSessionId =
        sessionId ??
        'embedded-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_sequence}';
    if (_sessions.containsKey(resolvedSessionId)) throw _closed();
    final initialSize = await _initialPixelSizeFor(device);
    var started = await _startSession(
      device,
      application,
      resolvedSessionId,
      initialSize,
    );
    final detectedSize = started.session.taskPixelSize;
    if (detectedSize != null &&
        _isPortrait(detectedSize) != _isPortrait(initialSize)) {
      final correctedSize = _isPortrait(detectedSize)
          ? _portraitPixelSize
          : _landscapePixelSize;
      await _disposeSession(started.session);
      started = await _startSession(
        device,
        application,
        resolvedSessionId,
        correctedSize,
      );
    }
    _sessions[resolvedSessionId] = started.session;
    _ensureTaskMonitor();
    return started.backend;
  }

  Future<({WindowBackendSession backend, _EmbeddedSession session})>
  _startSession(
    DeviceSummary device,
    AndroidApplication application,
    String resolvedSessionId,
    WindowPixelSize resolvedPixelSize, {
    int? existingTaskId,
  }) async {
    final videoEncoderFuture = _videoEncoderFor(device);
    final directory = await Directory.systemTemp.createTemp('open-dex-window-');
    final encodedFifo = '${directory.path}/video.mkv';
    final rawFifo = '${directory.path}/frames.rgba';
    int? textureId;
    ManagedProcess? decoder;
    ManagedProcess? scrcpy;
    final subscriptions = <StreamSubscription<String>>[];
    try {
      await _createFifo(encodedFifo);
      await _createFifo(rawFifo);
      textureId = await textureHost.createRawRgbaTexture(
        fifoPath: rawFifo,
        pixelSize: resolvedPixelSize,
      );
      decoder = await processLauncher.start(ffmpegExecutable, [
        '-hide_banner',
        '-nostdin',
        '-loglevel',
        'error',
        '-progress',
        'pipe:2',
        '-stats_period',
        '1',
        '-nostats',
        '-y',
        '-flags',
        'low_delay',
        '-probesize',
        '32',
        '-analyzeduration',
        '0',
        '-threads',
        '1',
        '-i',
        encodedFifo,
        '-an',
        // Matroska exposes a 1000 Hz time base for scrcpy's variable-rate
        // stream. FFmpeg's default sync duplicates frames toward that nominal
        // rate, flooding the RGBA pipe with stale pixels. Preserve exactly the
        // frames produced by Android instead.
        '-fps_mode',
        'passthrough',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgba',
        rawFifo,
      ], captureOutput: true);
      subscriptions.add(
        _listenDecoderTelemetry(resolvedSessionId, decoder.stderr),
      );
      final videoEncoder = await videoEncoderFuture;
      final displayId = Completer<int>();
      scrcpy = await processLauncher.start(
        executable,
        [
          '--serial=${device.id}',
          '--new-display=${resolvedPixelSize.width}x${resolvedPixelSize.height}/240',
          '--max-fps=60',
          '--video-codec=h264',
          '--video-bit-rate=8M',
          if (videoEncoder != null) '--video-encoder=$videoEncoder',
          '--no-vd-system-decorations',
          // The RGBA texture has fixed dimensions. Without a locked capture,
          // an app-requested rotation swaps the encoded width and height while
          // preserving the byte count, so the texture misinterprets portrait
          // rows as landscape pixels and visibly stretches the image.
          '--capture-orientation=@',
          '--no-window',
          '--no-audio',
          '--record=$encodedFifo',
          '--record-format=mkv',
          '--print-fps',
          if (existingTaskId == null) '--start-app=${application.packageName}',
          '--no-terminal-title',
        ],
        environment: {'ADB': adb.executable, 'SCRCPY_SERVER_PATH': serverPath},
        workingDirectory: File(executable).parent.path,
        captureOutput: true,
        lineBufferedOutput: true,
      );
      subscriptions.addAll([
        _listen(resolvedSessionId, scrcpy.stdout, displayId),
        _listen(resolvedSessionId, scrcpy.stderr, displayId),
      ]);
      final session = _EmbeddedSession(
        id: resolvedSessionId,
        device: device,
        application: application,
        pixelSize: resolvedPixelSize,
        directory: directory,
        textureId: textureId,
        decoder: decoder,
        scrcpy: scrcpy,
        subscriptions: subscriptions,
        inputDispatcher: _InputDispatcher(),
      );
      unawaited(
        scrcpy.exitCode.then(
          (code) => _handleUnexpectedExit(resolvedSessionId, session, code),
        ),
      );
      unawaited(
        decoder.exitCode.then(
          (code) => _handleUnexpectedExit(resolvedSessionId, session, code),
        ),
      );
      session.displayId = await displayId.future.timeout(startTimeout);
      await onDisplayCreated?.call(device, session.displayId!);
      await textureHost.waitForFirstFrame(textureId, timeout: startTimeout);
      if (existingTaskId != null) {
        await _bestEffort(
          () => adb.shell(device.id, [
            'am',
            'display',
            'move-stack',
            '$existingTaskId',
            '${session.displayId}',
          ]),
        );
      }
      final task = await _waitForApplicationTask(
        device.id,
        application.packageName,
        session.displayId!,
      );
      if (existingTaskId != null && task == null) {
        throw _failure(
          'The Android application could not move to its resized display.',
        );
      }
      session.taskId = task?.taskId;
      session.taskPixelSize = task?.pixelSize;
      return (
        backend: WindowBackendSession(
          id: resolvedSessionId,
          displayId: session.displayId,
          surface: WindowSurface(
            textureId: textureId,
            pixelSize: resolvedPixelSize,
          ),
        ),
        session: session,
      );
    } on Object catch (error) {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await _stopProcess(scrcpy);
      await _stopProcess(decoder);
      if (textureId != null) {
        await _bestEffort(() => textureHost.closeTexture(textureId!));
      }
      await _deleteSessionDirectory(directory);
      if (error is BackendFailure) rethrow;
      throw _failure('The embedded Android window could not start.', error);
    }
  }

  @override
  Future<WindowBackendSession> resizeSurface(
    String sessionId,
    WindowPixelSize pixelSize,
  ) async {
    await _sessionRetirements[sessionId];
    final current = _sessions[sessionId];
    if (current == null) throw _closed();
    if (current.pixelSize.width == pixelSize.width &&
        current.pixelSize.height == pixelSize.height) {
      return WindowBackendSession(
        id: sessionId,
        displayId: current.displayId,
        surface: WindowSurface(
          textureId: current.textureId,
          pixelSize: current.pixelSize,
        ),
      );
    }
    current.isReplacing = true;
    late final ({WindowBackendSession backend, _EmbeddedSession session})
    replacement;
    try {
      replacement = await _startSession(
        current.device,
        current.application,
        sessionId,
        pixelSize,
        existingTaskId: current.taskId,
      );
    } on Object {
      current.isReplacing = false;
      rethrow;
    }
    if (!identical(_sessions[sessionId], current)) {
      await _disposeSession(replacement.session);
      throw _closed();
    }
    _sessions[sessionId] = replacement.session;
    _ensureTaskMonitor();
    _retire(current);
    return replacement.backend;
  }

  @override
  Future<void> close(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) await _disposeSession(session);
    await _sessionRetirements[sessionId];
    _stopTaskMonitorIfIdle();
  }

  @override
  Future<void> sendPointer(String sessionId, WindowPointerSample sample) async {
    final session = _sessions[sessionId];
    final displayId = session?.displayId;
    if (session == null || displayId == null) throw _closed();
    final x = sample.x.round().clamp(0, session.pixelSize.width - 1);
    final y = sample.y.round().clamp(0, session.pixelSize.height - 1);
    final command = switch (sample.phase) {
      WindowPointerPhase.down => [
        'input',
        '-d',
        '$displayId',
        'motionevent',
        'DOWN',
        '$x',
        '$y',
      ],
      WindowPointerPhase.move => [
        'input',
        '-d',
        '$displayId',
        'motionevent',
        'MOVE',
        '$x',
        '$y',
      ],
      WindowPointerPhase.up => [
        'input',
        '-d',
        '$displayId',
        'motionevent',
        'UP',
        '$x',
        '$y',
      ],
      WindowPointerPhase.cancel => [
        'input',
        '-d',
        '$displayId',
        'motionevent',
        'CANCEL',
        '$x',
        '$y',
      ],
      WindowPointerPhase.scroll => [
        'input',
        'mouse',
        '-d',
        '$displayId',
        'roll',
        '${sample.scrollDeltaX}',
        '${sample.scrollDeltaY}',
      ],
    };
    return session.inputDispatcher.submit(
      () async {
        try {
          if (sample.phase != WindowPointerPhase.scroll) {
            await _sendPersistentPointerCommand(session, command, sample.phase);
            return;
          }
          await adb.shell(session.device.id, command);
        } on Object catch (error) {
          throw _failure(
            'Pointer input could not reach the Android window.',
            error,
          );
        }
      },
      coalescingKey: sample.phase == WindowPointerPhase.move
          ? _pointerMoveKey
          : null,
    );
  }

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async {
    final session = _sessions[sessionId];
    final displayId = session?.displayId;
    if (session == null || displayId == null) throw _closed();
    if (sample.phase == WindowKeyPhase.up) return;
    final character = sample.character;
    final keyCode = _androidKeyCode(sample.physicalKeyId);
    final command = character != null && character.isNotEmpty
        ? [
            'input',
            'keyboard',
            '-d',
            '$displayId',
            'text',
            _inputText(character),
          ]
        : keyCode != null
        ? ['input', 'keyboard', '-d', '$displayId', 'keyevent', '$keyCode']
        : null;
    if (command == null) {
      throw _failure('That keyboard key is not supported yet.');
    }
    return session.inputDispatcher.submit(() async {
      try {
        await adb.shell(session.device.id, command);
      } on Object catch (error) {
        throw _failure(
          'Keyboard input could not reach the Android window.',
          error,
        );
      }
    });
  }

  @override
  Future<void> dispose() async {
    _taskMonitor?.cancel();
    _taskMonitor = null;
    for (final sessionId in [..._sessions.keys]) {
      await close(sessionId);
    }
    await Future.wait([..._retiring]);
    await _exits.close();
    await _telemetry.close();
  }

  StreamSubscription<String> _listen(
    String sessionId,
    Stream<List<int>> output,
    Completer<int> displayId,
  ) => output.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    final displayMatch = _displayLine.firstMatch(line);
    final parsedDisplay = displayMatch == null
        ? null
        : int.tryParse(displayMatch.group(1)!);
    if (parsedDisplay != null && !displayId.isCompleted) {
      displayId.complete(parsedDisplay);
    }
    final fpsMatch = _fpsLine.firstMatch(line);
    final fps = fpsMatch == null ? null : double.tryParse(fpsMatch.group(1)!);
    if (fps != null && fps >= 0 && !_telemetry.isClosed) {
      _telemetry.add(
        WindowBackendTelemetry(
          sessionId: sessionId,
          producedFramesPerSecond: fps,
        ),
      );
    }
  });

  StreamSubscription<String> _listenDecoderTelemetry(
    String sessionId,
    Stream<List<int>> output,
  ) => output.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    final match = _decoderFpsLine.firstMatch(line.trim());
    final fps = match == null ? null : double.tryParse(match.group(1)!);
    if (fps != null && fps >= 0 && !_telemetry.isClosed) {
      _telemetry.add(
        WindowBackendTelemetry(
          sessionId: sessionId,
          producedFramesPerSecond: fps,
        ),
      );
    }
  });

  Future<void> _createFifo(String path) async {
    final output = await processExecutor.run('/usr/bin/mkfifo', [
      path,
    ], timeout: const Duration(seconds: 3));
    if (!output.succeeded) {
      throw _failure('The Linux frame pipe could not be created.');
    }
  }

  Future<String?> _videoEncoderFor(DeviceSummary device) async {
    if (_videoEncoders.containsKey(device.id)) {
      return _videoEncoders[device.id];
    }
    final activeLookup = _videoEncoderLookups[device.id];
    if (activeLookup != null) return activeLookup;
    final lookup = _discoverVideoEncoder(device);
    _videoEncoderLookups[device.id] = lookup;
    try {
      return await lookup;
    } finally {
      if (identical(_videoEncoderLookups[device.id], lookup)) {
        _videoEncoderLookups.remove(device.id);
      }
    }
  }

  Future<String?> _discoverVideoEncoder(DeviceSummary device) async {
    try {
      final output = await processExecutor.run(executable, [
        '--serial=${device.id}',
        '--list-encoders',
      ], timeout: startTimeout);
      if (!output.succeeded) return null;
      final listing = '${output.stdout}\n${output.stderr}';
      String? selected;
      for (final encoder in _preferredHardwareAvcEncoders) {
        if (listing.contains('--video-encoder=$encoder')) {
          selected = encoder;
          break;
        }
      }
      _videoEncoders[device.id] = selected;
      return selected;
    } on Object {
      // Encoder discovery is an optimisation. A transient failure is not
      // cached, so a later launch can retry without blocking this one.
      return null;
    }
  }

  Future<void> _handleUnexpectedExit(
    String sessionId,
    _EmbeddedSession expected,
    int exitCode,
  ) async {
    if (!identical(_sessions[sessionId], expected)) return;
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    await _disposeSession(session);
    _stopTaskMonitorIfIdle();
    if (!_exits.isClosed) {
      _exits.add(WindowBackendExit(sessionId: sessionId, exitCode: exitCode));
    }
  }

  Future<void> _disposeSession(_EmbeddedSession session) async {
    await session.inputDispatcher.close();
    await _closePointerProcess(session);
    for (final subscription in session.subscriptions) {
      await subscription.cancel();
    }
    // Close the raw-frame reader first so FFmpeg cannot remain blocked writing
    // into a retired texture. Its exit then closes the encoded FIFO and lets
    // scrcpy stop without stranding a virtual display.
    await _bestEffort(() => textureHost.closeTexture(session.textureId));
    await _stopProcess(session.decoder);
    await _stopProcess(session.scrcpy);
    await _deleteSessionDirectory(session.directory);
  }

  Future<void> _sendPersistentPointerCommand(
    _EmbeddedSession session,
    List<String> command,
    WindowPointerPhase phase,
  ) async {
    if (phase == WindowPointerPhase.down && session.pointerProcess != null) {
      await _closePointerProcess(session);
    }
    final process = session.pointerProcess ??= await pointerProcessLauncher
        .start(adb.executable, ['-s', session.device.id, 'shell']);
    if (command.any((token) => !_pointerShellToken.hasMatch(token))) {
      throw _failure('The pointer command contained an invalid value.');
    }
    await process.writeInput('${command.join(' ')}\n');
    if (phase == WindowPointerPhase.up || phase == WindowPointerPhase.cancel) {
      await _closePointerProcess(session);
    }
  }

  Future<void> _closePointerProcess(_EmbeddedSession session) async {
    final process = session.pointerProcess;
    session.pointerProcess = null;
    if (process == null) return;
    try {
      await process.closeInput();
      await process.exitCode.timeout(processStopTimeout);
    } on Object {
      await _stopProcess(process);
    }
  }

  void _retire(_EmbeddedSession session) {
    late final Future<void> retirement;
    retirement = Future<void>.delayed(surfaceRetireDelay)
        .then((_) => _disposeSession(session))
        .whenComplete(() {
          _retiring.remove(retirement);
          if (identical(_sessionRetirements[session.id], retirement)) {
            _sessionRetirements.remove(session.id);
          }
        });
    _retiring.add(retirement);
    _sessionRetirements[session.id] = retirement;
  }

  Future<_ApplicationTask?> _readApplicationTask(
    String deviceId,
    String packageName,
    int displayId,
  ) async {
    try {
      final output = await adb.shell(deviceId, const ['am', 'stack', 'list']);
      return _applicationTaskFromStackList(output, packageName, displayId);
    } on Object {
      return null;
    }
  }

  Future<_ApplicationTask?> _waitForApplicationTask(
    String deviceId,
    String packageName,
    int displayId,
  ) async {
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final task = await _readApplicationTask(deviceId, packageName, displayId);
      if (task != null) return task;
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  void _ensureTaskMonitor() {
    if (_taskMonitor != null ||
        !_sessions.values.any((session) => session.taskId != null)) {
      return;
    }
    _taskMonitor = Timer.periodic(
      taskMonitorInterval,
      (_) => unawaited(_checkApplicationTasks()),
    );
  }

  void _stopTaskMonitorIfIdle() {
    if (_sessions.values.any((session) => session.taskId != null)) return;
    _taskMonitor?.cancel();
    _taskMonitor = null;
  }

  Future<void> _checkApplicationTasks() async {
    if (_taskMonitorActive ||
        _sessions.isEmpty ||
        _sessions.values.any((session) => session.pointerProcess != null)) {
      return;
    }
    _taskMonitorActive = true;
    try {
      final outputs = <String, String>{};
      for (final session in [..._sessions.values]) {
        if (session.isReplacing ||
            session.taskId == null ||
            !identical(_sessions[session.id], session)) {
          continue;
        }
        final output = outputs[session.device.id] ??= await adb.shell(
          session.device.id,
          const ['am', 'stack', 'list'],
        );
        final task = _applicationTaskFromStackList(
          output,
          session.application.packageName,
          session.displayId!,
        );
        if (task != null) {
          session.taskId = task.taskId;
          session.missingTaskChecks = 0;
          continue;
        }
        session.missingTaskChecks += 1;
        if (session.missingTaskChecks < 2 ||
            !identical(_sessions[session.id], session)) {
          continue;
        }
        _sessions.remove(session.id);
        await _disposeSession(session);
        if (!_exits.isClosed) {
          _exits.add(
            WindowBackendExit(
              sessionId: session.id,
              exitCode: _applicationTaskExitCode,
            ),
          );
        }
      }
    } on Object {
      // A transient ADB failure must not close otherwise healthy windows.
    } finally {
      _taskMonitorActive = false;
      _stopTaskMonitorIfIdle();
    }
  }

  static _ApplicationTask? _applicationTaskFromStackList(
    String output,
    String packageName,
    int displayId,
  ) {
    _ApplicationTask? current;
    for (final line in const LineSplitter().convert(output)) {
      final root = _rootTaskLine.firstMatch(line);
      if (root != null) {
        current = int.parse(root.group(4)!) == displayId
            ? _ApplicationTask(
                taskId: int.parse(root.group(1)!),
                pixelSize: WindowPixelSize(
                  width: int.parse(root.group(2)!),
                  height: int.parse(root.group(3)!),
                ),
              )
            : null;
      }
      if (current != null && line.contains('$packageName/')) return current;
    }
    return null;
  }

  static bool _isPortrait(WindowPixelSize size) => size.height > size.width;

  /// The initial display size for a launch, matched to the phone's own
  /// orientation.
  ///
  /// A phone whose launcher is portrait-locked — nearly all of them — renders
  /// rotated 90° inside a landscape virtual display, because Android composites
  /// the portrait content sideways to fill it. Creating the display in the
  /// phone's natural orientation keeps the home screen and portrait apps
  /// upright. The task-bounds correction below cannot catch this on its own:
  /// the bounds report the display's orientation, not the content's.
  ///
  /// Cached per device, and falls back to the configured default when the query
  /// fails — a wrong-orientation mirror still beats no mirror, so orientation is
  /// never worth failing a launch over.
  Future<WindowPixelSize> _initialPixelSizeFor(DeviceSummary device) async {
    final cached = _naturalSizeCache[device.id];
    if (cached != null) return cached;
    var size = pixelSize;
    try {
      final output = await adb.shell(device.id, const ['wm', 'size']);
      size = DisplayOrientation.fromWmSize(
        output,
        portrait: _portraitPixelSize,
        landscape: _landscapePixelSize,
        fallback: pixelSize,
      );
    } on Object {
      // Keep the default. Orientation is a nicety; a launch is not.
    }
    _naturalSizeCache[device.id] = size;
    return size;
  }

  final Map<String, WindowPixelSize> _naturalSizeCache =
      <String, WindowPixelSize>{};

  Future<void> _stopProcess(ManagedProcess? process) async {
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(processStopTimeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(processStopTimeout);
      } on TimeoutException {
        // The process no longer owns a tracked session. The force-kill request
        // is the final host-side cleanup available through this abstraction.
      }
    }
  }

  static Future<void> _deleteSessionDirectory(Directory directory) async {
    final tempRoot = Directory.systemTemp.absolute.path;
    final path = directory.absolute.path;
    if (!path.startsWith(
      '$tempRoot${Platform.pathSeparator}open-dex-window-',
    )) {
      return;
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void _validateRuntime(DeviceSummary device, AndroidApplication application) {
    if (!Platform.isLinux) {
      throw _failure(
        'Embedded Android windows are currently available on Linux only.',
      );
    }
    if (!File(executable).existsSync() ||
        !File(serverPath).existsSync() ||
        !File('/usr/bin/mkfifo').existsSync()) {
      throw _failure('The embedded video runtime is incomplete.');
    }
    if (!File(ffmpegExecutable).existsSync()) {
      throw _failure(
        'FFmpeg is required to decode embedded Android application video.',
      );
    }
    if (!_packageName.hasMatch(application.packageName)) {
      throw _failure('The Android application identifier is invalid.');
    }
    if (device.id.isEmpty || device.id.contains(RegExp(r'[\x00-\x20]'))) {
      throw _failure('The Android device identifier is invalid.');
    }
  }

  static int? _androidKeyCode(int physicalKeyId) {
    final usage = physicalKeyId & 0xffff;
    if (usage >= 0x04 && usage <= 0x1d) return 29 + usage - 0x04;
    if (usage >= 0x1e && usage <= 0x26) return 8 + usage - 0x1e;
    if (usage == 0x27) return 7;
    return const {
      0x28: 66,
      0x29: 111,
      0x2a: 67,
      0x2b: 61,
      0x2c: 62,
      0x4c: 112,
      0x4f: 22,
      0x50: 21,
      0x51: 20,
      0x52: 19,
    }[usage];
  }

  static String _inputText(String value) => value.replaceAll(' ', '%s');

  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  static final _displayLine = RegExp(r'New display: .*\(id=(\d+)\)');
  static final _rootTaskLine = RegExp(
    r'RootTask id=(\d+) bounds=\[[^\]]+\]\[(\d+),(\d+)\] displayId=(\d+)',
  );
  static final _fpsLine = RegExp(r'(?:^|\s)(\d+(?:\.\d+)?) fps\s*$');
  static final _decoderFpsLine = RegExp(r'^fps=(\d+(?:\.\d+)?)$');
  static final _pointerShellToken = RegExp(r'^[A-Za-z0-9_.@+\-]+$');
  static const _preferredHardwareAvcEncoders = [
    'c2.qti.avc.encoder',
    'OMX.qcom.video.encoder.avc',
    'c2.mtk.avc.encoder',
    'OMX.MTK.VIDEO.ENCODER.AVC',
    'c2.exynos.h264.encoder',
  ];
  static const _pointerMoveKey = 'pointer-move';
  static const _applicationTaskExitCode = 20;
  static const _landscapePixelSize = WindowPixelSize(width: 1280, height: 896);
  static const _portraitPixelSize = WindowPixelSize(width: 720, height: 1280);

  static BackendFailure _closed() =>
      _failure('That embedded Android window has closed.');

  static BackendFailure _failure(String message, [Object? cause]) =>
      BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: message,
          retryable: true,
          capability: 'embedded-application-streaming',
          technicalDetails: cause?.toString(),
        ),
      );
}

class _EmbeddedSession {
  _EmbeddedSession({
    required this.id,
    required this.device,
    required this.application,
    required this.pixelSize,
    required this.directory,
    required this.textureId,
    required this.decoder,
    required this.scrcpy,
    required this.subscriptions,
    required this.inputDispatcher,
  });

  final String id;
  final DeviceSummary device;
  final AndroidApplication application;
  final WindowPixelSize pixelSize;
  final Directory directory;
  final int textureId;
  final ManagedProcess decoder;
  final ManagedProcess scrcpy;
  final List<StreamSubscription<String>> subscriptions;
  final _InputDispatcher inputDispatcher;
  ManagedProcess? pointerProcess;
  int? displayId;
  int? taskId;
  WindowPixelSize? taskPixelSize;
  int missingTaskChecks = 0;
  bool isReplacing = false;
}

class _ApplicationTask {
  const _ApplicationTask({required this.taskId, required this.pixelSize});

  final int taskId;
  final WindowPixelSize pixelSize;
}

/// Keeps Android input ordered without allowing pointer motion to build an
/// unbounded queue of host-side ADB processes.
class _InputDispatcher {
  final Queue<_QueuedInput> _pending = Queue<_QueuedInput>();
  Future<void> _drained = Future<void>.value();
  bool _isDraining = false;
  bool _isClosed = false;

  Future<void> submit(
    Future<void> Function() operation, {
    Object? coalescingKey,
  }) {
    if (_isClosed) {
      return Future<void>.error(EmbeddedScrcpyWindowGateway._closed());
    }
    final completion = Completer<void>();
    if (coalescingKey != null &&
        _pending.isNotEmpty &&
        _pending.last.coalescingKey == coalescingKey) {
      final pending = _pending.last;
      pending.operation = operation;
      pending.completions.add(completion);
    } else {
      _pending.add(
        _QueuedInput(
          operation: operation,
          coalescingKey: coalescingKey,
          completions: [completion],
        ),
      );
    }
    if (!_isDraining) {
      _isDraining = true;
      _drained = _drain();
    }
    return completion.future;
  }

  Future<void> close() async {
    _isClosed = true;
    await _drained;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final queued = _pending.removeFirst();
      try {
        await queued.operation();
        for (final completion in queued.completions) {
          completion.complete();
        }
      } on Object catch (error, stackTrace) {
        for (final completion in queued.completions) {
          completion.completeError(error, stackTrace);
        }
      }
    }
    _isDraining = false;
  }
}

class _QueuedInput {
  _QueuedInput({
    required this.operation,
    required this.coalescingKey,
    required this.completions,
  });

  Future<void> Function() operation;
  final Object? coalescingKey;
  final List<Completer<void>> completions;
}

Future<void> _bestEffort(Future<void> Function() operation) async {
  try {
    await operation();
  } on Object {
    // Cleanup continues when one native resource already exited.
  }
}
