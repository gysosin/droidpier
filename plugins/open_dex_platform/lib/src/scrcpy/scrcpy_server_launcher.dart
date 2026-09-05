import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../adb_client.dart';
import '../managed_process.dart';

class ScrcpyServerLaunchException implements Exception {
  const ScrcpyServerLaunchException(
    this.message, {
    this.exitCode = 24,
    this.stderrTail = const [],
  });

  final String message;
  final int exitCode;
  final List<String> stderrTail;

  @override
  String toString() => 'ScrcpyServerLaunchException: $message';
}

abstract interface class ScrcpyServerStarter {
  Future<ScrcpyServerSession> start({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    required WindowPixelSize displaySize,
    required int dpi,
    String? encoder,
    Duration displayTimeout = const Duration(seconds: 5),
  });
}

/// Starts scrcpy-server mirroring the phone's own display, view only.
///
/// Separate from [ScrcpyServerStarter] because the two ask the server for
/// different things: a window needs a new virtual display and a control
/// channel; a mirror needs neither, only display 0 scaled to fit.
abstract interface class ScrcpyMirrorStarter {
  Future<ScrcpyServerSession> startMirror({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    int maxSize = 1080,
    int maxFps = 30,
  });
}

abstract interface class ScrcpyServerSession {
  Future<int> get displayId;

  Future<int> get exitCode;

  List<String> get stderrTail;

  Future<void> stop();
}

class ScrcpyServerLauncher implements ScrcpyServerStarter, ScrcpyMirrorStarter {
  ScrcpyServerLauncher({
    required this.adb,
    this.processLauncher = const SystemManagedProcessLauncher(),
    Future<String> Function(String path)? fileHasher,
    this.stopTimeout = const Duration(seconds: 3),
  }) : fileHasher = fileHasher ?? _sha256File;

  final AdbClient adb;
  final ManagedProcessLauncher processLauncher;
  final Future<String> Function(String path) fileHasher;
  final Duration stopTimeout;

  static final Map<String, String> _localJarHashes = {};
  static final Map<String, Future<String>> _localJarHashLookups = {};

  @override
  Future<ScrcpyServerHandle> start({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    required WindowPixelSize displaySize,
    required int dpi,
    String? encoder,
    Duration displayTimeout = const Duration(seconds: 5),
  }) async {
    final serverArguments = _serverArguments(
      scid: scid,
      displaySize: displaySize,
      dpi: dpi,
      encoder: encoder,
    );
    if (displayTimeout <= Duration.zero) {
      throw ArgumentError.value(
        displayTimeout,
        'displayTimeout',
        'must be greater than zero',
      );
    }
    return _launch(
      device: device,
      serverJarPath: serverJarPath,
      hostPort: hostPort,
      scid: scid,
      serverArguments: serverArguments,
      displayTimeout: displayTimeout,
    );
  }

  @override
  Future<ScrcpyServerHandle> startMirror({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    int maxSize = 1080,
    int maxFps = 30,
  }) => _launch(
    device: device,
    serverJarPath: serverJarPath,
    hostPort: hostPort,
    scid: scid,
    serverArguments: _mirrorArguments(
      scid: scid,
      maxSize: maxSize,
      maxFps: maxFps,
    ),
    // Display 0 is the phone's own; the server announces no new display.
    displayTimeout: null,
  );

  Future<ScrcpyServerHandle> _launch({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    required List<String> serverArguments,
    required Duration? displayTimeout,
  }) async {
    if (!File(serverJarPath).existsSync()) {
      throw ArgumentError.value(
        serverJarPath,
        'serverJarPath',
        'must identify the scrcpy server jar',
      );
    }
    if (hostPort < 1 || hostPort > 65535) {
      throw ArgumentError.value(hostPort, 'hostPort', 'must be a valid port');
    }
    await _ensureServerJar(device.id, serverJarPath);
    final reverseName = 'scrcpy_$scid';
    var reversed = false;
    try {
      await adb.reverseAbstract(
        device.id,
        deviceSocket: reverseName,
        hostPort: hostPort,
      );
      reversed = true;
      final process = await processLauncher.start(
        adb.executable,
        [
          '-s',
          device.id,
          'shell',
          'CLASSPATH=$_remoteServerPath',
          'app_process',
          '/',
          'com.genymobile.scrcpy.Server',
          _serverVersion,
          ...serverArguments,
        ],
        captureOutput: true,
        lineBufferedOutput: true,
      );
      return ScrcpyServerHandle._(
        adb: adb,
        deviceId: device.id,
        reverseName: reverseName,
        process: process,
        stopTimeout: stopTimeout,
        displayTimeout: displayTimeout,
      );
    } on Object {
      if (reversed) {
        await _bestEffort(
          () => adb.removeReverseByName(device.id, reverseName),
        );
      }
      rethrow;
    }
  }

  Future<void> _ensureServerJar(String deviceId, String localPath) async {
    final localHash = await _localHash(localPath);
    String? remoteHash;
    try {
      final output = await adb.shell(deviceId, const [
        'sha256sum',
        _remoteServerPath,
      ]);
      remoteHash = _firstHash(output);
    } on AdbException {
      // A missing or unreadable remote jar is repaired by the push below.
    }
    if (remoteHash == localHash) return;
    await adb.push(deviceId, localPath, _remoteServerPath);
  }

  Future<String> _localHash(String path) async {
    final cached = _localJarHashes[path];
    if (cached != null) return cached;
    final active = _localJarHashLookups[path];
    if (active != null) return active;
    final lookup = fileHasher(path);
    _localJarHashLookups[path] = lookup;
    try {
      final hash = await lookup;
      if (!_sha256.hasMatch(hash)) {
        throw const ScrcpyServerLaunchException(
          'The bundled scrcpy server returned an invalid SHA-256.',
        );
      }
      final normalized = hash.toLowerCase();
      _localJarHashes[path] = normalized;
      return normalized;
    } finally {
      if (identical(_localJarHashLookups[path], lookup)) {
        _localJarHashLookups.remove(path);
      }
    }
  }

  static Future<String> _sha256File(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  static String? _firstHash(String output) {
    final first = output.trim().split(RegExp(r'\s+')).firstOrNull;
    return first != null && _sha256.hasMatch(first)
        ? first.toLowerCase()
        : null;
  }

  static List<String> _serverArguments({
    required String scid,
    required WindowPixelSize displaySize,
    required int dpi,
    required String? encoder,
  }) {
    _validateScid(scid);
    if (displaySize.width < 1 ||
        displaySize.width > 65535 ||
        displaySize.height < 1 ||
        displaySize.height > 65535) {
      throw ArgumentError.value(
        displaySize,
        'displaySize',
        'must fit the scrcpy display protocol',
      );
    }
    if (dpi < 1 || dpi > 65535) {
      throw ArgumentError.value(dpi, 'dpi', 'must be between 1 and 65535');
    }
    final arguments = <String>[
      'scid=$scid',
      'log_level=info',
      'video=true',
      'audio=false',
      'control=true',
      'video_codec=h264',
      'video_bit_rate=8000000',
      'max_fps=60',
      'new_display=${displaySize.width}x${displaySize.height}/$dpi',
      'flex_display=true',
      'vd_system_decorations=false',
      // Deliberately no `capture_orientation` lock. Locking pinned the display
      // to its initial (portrait) orientation, so a landscape-only app — a
      // game, a video player — rendered sideways inside the fixed frame and
      // never rotated. The lock existed for the legacy fixed-size texture,
      // which a rotation would have corrupted. The direct pipeline instead
      // follows the app: the display rotates with content, emits a new session
      // header with the new dimensions, and the gateway swaps to a matching
      // texture. Removing the lock is what lets landscape apps display upright.
      'send_device_meta=true',
      'send_frame_meta=true',
      'send_stream_meta=true',
      'send_dummy_byte=false',
      'cleanup=true',
      'power_on=false',
      'stay_awake=false',
      'show_touches=false',
      'clipboard_autosync=false',
      if (encoder != null) 'video_encoder=$encoder',
    ];
    return _checked(arguments);
  }

  /// Arguments for mirroring the phone's display 0, view only: no virtual
  /// display, no control socket, capped in size and rate because the mirror
  /// frame on the desk is small and the phone's encoder is shared with any
  /// app windows streaming beside it.
  static List<String> _mirrorArguments({
    required String scid,
    required int maxSize,
    required int maxFps,
  }) {
    _validateScid(scid);
    if (maxSize < 0 || maxSize > 65535) {
      throw ArgumentError.value(maxSize, 'maxSize', 'must fit 0 to 65535');
    }
    if (maxFps < 1 || maxFps > 240) {
      throw ArgumentError.value(maxFps, 'maxFps', 'must be 1 to 240');
    }
    return _checked(<String>[
      'scid=$scid',
      'log_level=info',
      'video=true',
      'audio=false',
      'control=false',
      'video_codec=h264',
      'video_bit_rate=4000000',
      'max_fps=$maxFps',
      'max_size=$maxSize',
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
  }

  static void _validateScid(String scid) {
    final scidValue = _scid.hasMatch(scid) ? int.parse(scid, radix: 16) : 0;
    if (scidValue < 1 || scidValue > 0x7fffffff) {
      throw ArgumentError.value(
        scid,
        'scid',
        'must be eight lowercase hex digits in the signed positive range',
      );
    }
  }

  static List<String> _checked(List<String> arguments) {
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      final value = separator < 0
          ? argument
          : argument.substring(separator + 1);
      if (_forbiddenServerValue.hasMatch(value)) {
        throw ArgumentError.value(
          value,
          'serverArgument',
          'contains a character rejected by scrcpy-server',
        );
      }
    }
    return arguments;
  }

  static const _serverVersion = '4.1';
  static const _remoteServerPath = '/data/local/tmp/scrcpy-server.jar';
  static final _scid = RegExp(r'^[0-7][0-9a-f]{7}$');
  static final _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _forbiddenServerValue = RegExp(
    r'''[ ;'"*${}?&`#\\|<>\[\]{}()!~]''',
  );
}

class ScrcpyServerHandle implements ScrcpyServerSession {
  ScrcpyServerHandle._({
    required this._adb,
    required this._deviceId,
    required this._reverseName,
    required this._process,
    required this._stopTimeout,
    required Duration? displayTimeout,
  }) {
    unawaited(_displayId.future.catchError((_) => -1));
    if (displayTimeout == null) {
      // A mirror of display 0: nothing to wait for, the display exists.
      _displayId.complete(0);
    } else {
      _displayTimer = Timer(displayTimeout, () {
        if (_displayId.isCompleted) return;
        _displayId.completeError(
          ScrcpyServerLaunchException(
            'scrcpy-server did not create a display within '
            '${displayTimeout.inMilliseconds} ms.',
            stderrTail: List.unmodifiable(_stderr),
          ),
        );
      });
    }
    _subscriptions.add(
      _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_readDisplayLine, onError: _readError),
    );
    _subscriptions.add(
      _process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _stderr.addLast(line);
            if (_stderr.length > 40) _stderr.removeFirst();
            _readDisplayLine(line);
          }, onError: _readError),
    );
    unawaited(
      _process.exitCode.then((exitCode) {
        if (!_stopped && !_displayId.isCompleted) {
          _displayTimer?.cancel();
          _displayId.completeError(
            ScrcpyServerLaunchException(
              'scrcpy-server exited with $exitCode before creating a display.'
              '${_stderr.isEmpty ? '' : ' ${_stderr.join(' | ')}'}',
              stderrTail: List.unmodifiable(_stderr),
            ),
          );
        }
      }),
    );
  }

  final AdbClient _adb;
  final String _deviceId;
  final String _reverseName;
  final ManagedProcess _process;
  final Duration _stopTimeout;
  final Completer<int> _displayId = Completer<int>();
  final Queue<String> _stderr = Queue<String>();
  final List<StreamSubscription<String>> _subscriptions = [];
  Timer? _displayTimer;
  bool _stopped = false;

  @override
  Future<int> get displayId => _displayId.future;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  List<String> get stderrTail => List.unmodifiable(_stderr);

  void _readDisplayLine(String line) {
    if (_displayId.isCompleted) return;
    final match = _displayLine.firstMatch(line);
    if (match != null) {
      _displayTimer?.cancel();
      _displayId.complete(int.parse(match.group(1)!));
    }
  }

  void _readError(Object error, StackTrace stackTrace) {
    if (!_displayId.isCompleted) {
      _displayTimer?.cancel();
      _displayId.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _displayTimer?.cancel();
    if (!_displayId.isCompleted) {
      _displayId.completeError(
        ScrcpyServerLaunchException(
          'scrcpy-server stopped before creating a display.',
          stderrTail: List.unmodifiable(_stderr),
        ),
      );
    }
    _process.kill();
    try {
      await _process.exitCode.timeout(_stopTimeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _bestEffort(() => _process.exitCode.timeout(_stopTimeout));
    } finally {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      await _adb.removeReverseByName(_deviceId, _reverseName);
    }
  }

  static final _displayLine = RegExp(r'New display: .*\(id=(\d+)\)');
}

Future<void> _bestEffort(Future<void> Function() operation) async {
  try {
    await operation();
  } on Object {
    // Cleanup continues after a process or reverse mapping already vanished.
  }
}
