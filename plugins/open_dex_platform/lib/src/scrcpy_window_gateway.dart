import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import 'managed_process.dart';

class ScrcpyWindowGateway implements WindowGateway {
  ScrcpyWindowGateway({
    required this.executable,
    required this.serverPath,
    this.adbExecutable = 'adb',
    this.processLauncher = const SystemManagedProcessLauncher(),
  });

  final String executable;
  final String serverPath;
  final String adbExecutable;
  final ManagedProcessLauncher processLauncher;
  final StreamController<WindowBackendExit> _exits =
      StreamController<WindowBackendExit>.broadcast(sync: true);
  final StreamController<WindowBackendTelemetry> _telemetry =
      StreamController<WindowBackendTelemetry>.broadcast(sync: true);
  final Map<String, ManagedProcess> _sessions = {};
  final Map<String, List<StreamSubscription<String>>> _outputSubscriptions = {};
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
    if (!File(executable).existsSync() || !File(serverPath).existsSync()) {
      throw _failure('The scrcpy 4.1 runtime is missing.');
    }
    if (!_packageName.hasMatch(application.packageName)) {
      throw _failure('The Android application identifier is invalid.');
    }
    if (device.id.isEmpty || device.id.contains(RegExp(r'[\x00-\x20]'))) {
      throw _failure('The Android device identifier is invalid.');
    }

    final resolvedSessionId =
        sessionId ??
        'scrcpy-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_sequence}';
    try {
      final process = await processLauncher.start(
        executable,
        [
          '--serial=${device.id}',
          '--new-display=1280x720/240',
          '--max-fps=60',
          '--print-fps',
          '--start-app=${application.packageName}',
          '--window-title=${application.label} — DroidPier',
          '--disable-screensaver',
          '--no-terminal-title',
        ],
        environment: {'ADB': adbExecutable, 'SCRCPY_SERVER_PATH': serverPath},
        workingDirectory: File(executable).parent.path,
        captureOutput: true,
        lineBufferedOutput: true,
      );
      _sessions[resolvedSessionId] = process;
      _outputSubscriptions[resolvedSessionId] = [
        _listenToOutput(resolvedSessionId, process.stdout),
        _listenToOutput(resolvedSessionId, process.stderr),
      ];
      unawaited(
        process.exitCode.then((exitCode) async {
          await _cancelOutput(resolvedSessionId);
          if (_sessions.remove(resolvedSessionId) != null && !_exits.isClosed) {
            _exits.add(
              WindowBackendExit(
                sessionId: resolvedSessionId,
                exitCode: exitCode,
              ),
            );
          }
        }),
      );
      return WindowBackendSession(id: resolvedSessionId);
    } on BackendFailure {
      rethrow;
    } on Object catch (error) {
      throw _failure('The Android application window could not start.', error);
    }
  }

  @override
  Future<void> close(String sessionId) async {
    final process = _sessions.remove(sessionId);
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // The OS will reap the client; it no longer owns a tracked session.
    }
  }

  @override
  Future<void> sendPointer(String sessionId, WindowPointerSample sample) async {
    throw _failure(
      'Embedded pointer input is unavailable in external-window mode.',
    );
  }

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async {
    throw _failure(
      'Embedded keyboard input is unavailable in external-window mode.',
    );
  }

  @override
  Future<void> dispose() async {
    for (final sessionId in [..._sessions.keys]) {
      await close(sessionId);
    }
    await _exits.close();
    await _telemetry.close();
  }

  StreamSubscription<String> _listenToOutput(
    String sessionId,
    Stream<List<int>> output,
  ) => output
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _handleOutputLine(sessionId, line));

  void _handleOutputLine(String sessionId, String line) {
    final match = _fpsLine.firstMatch(line);
    final value = match == null ? null : double.tryParse(match.group(1)!);
    if (value == null || value < 0 || value > 240 || _telemetry.isClosed) {
      return;
    }
    _telemetry.add(
      WindowBackendTelemetry(
        sessionId: sessionId,
        producedFramesPerSecond: value,
      ),
    );
  }

  Future<void> _cancelOutput(String sessionId) async {
    final subscriptions = _outputSubscriptions.remove(sessionId);
    if (subscriptions == null) return;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  static final _fpsLine = RegExp(r'(?:^|\s)(\d+(?:\.\d+)?) fps\s*$');

  static BackendFailure _failure(String message, [Object? cause]) =>
      BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: message,
          retryable: true,
          capability: 'application-streaming',
          technicalDetails: cause?.toString(),
        ),
      );
}
