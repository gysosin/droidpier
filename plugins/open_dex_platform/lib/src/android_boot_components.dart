import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

import 'adb_client.dart';
import 'managed_process.dart';

class AgentBootComponent implements BootComponent {
  AgentBootComponent({
    required this.adb,
    required this.sessionToken,
    required this.agentJarPath,
    this.processLauncher = const SystemManagedProcessLauncher(),
    this.handshakeTimeout = const Duration(seconds: 12),
  });

  static const _devicePort = 3698;
  static const _remotePath = '/data/local/tmp/open-dex-agent.jar';

  final AdbClient adb;
  final ManagedProcessLauncher processLauncher;
  final String sessionToken;
  final String agentJarPath;
  final Duration handshakeTimeout;
  AgentTcpServer? _server;
  ManagedProcess? _process;
  Set<String> _capabilities = const {};
  Map<String, Object?> _helloData = const {};

  @override
  String get stageId => 'agent';

  Set<String> get capabilities => _capabilities;

  Map<String, Object?> get helloData => _helloData;

  AgentTcpServer? get server => _server;

  bool get isAvailable => _server?.isAuthenticated ?? false;

  Future<ProtocolEnvelope> request(
    String type, {
    Map<String, Object?> data = const {},
    String responseType = 'command.result',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final server = _server;
    if (server == null || !server.isAuthenticated) {
      throw const ProtocolException('The Android agent is unavailable.');
    }
    final requestId =
        'request-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
    final response = Completer<ProtocolEnvelope>();
    final subscription = server.messages.listen((message) {
      if (message.type == responseType &&
          message.data['replyTo'] == requestId &&
          !response.isCompleted) {
        response.complete(message);
      }
    });
    try {
      server.send(
        ProtocolEnvelope(
          id: requestId,
          type: type,
          timestamp: DateTime.now().toUtc(),
          data: data,
        ),
      );
      return await response.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> start(DeviceSummary device) async {
    if (!File(agentJarPath).existsSync()) {
      throw _failure('The Android agent artifact is missing.');
    }
    final server = AgentTcpServer(sessionToken: sessionToken);
    _server = server;
    final hello = Completer<ProtocolEnvelope>();
    final helloSubscription = server.messages.listen((message) {
      if (message.type == 'agent.hello' && !hello.isCompleted) {
        hello.complete(message);
      }
    });
    try {
      final hostPort = await server.start();
      await adb.reverse(device.id, devicePort: _devicePort, hostPort: hostPort);
      await adb.push(device.id, agentJarPath, _remotePath);
      _process = await processLauncher.start(adb.executable, [
        '-s',
        device.id,
        'shell',
        'CLASSPATH=$_remotePath',
        'app_process',
        '/',
        'io.github.shrey113.openandroiddex.agent.Main',
        '--token',
        sessionToken,
        '--port',
        '$_devicePort',
      ]);
      final handshake = await hello.future.timeout(handshakeTimeout);
      _helloData = Map.unmodifiable(handshake.data);
      _capabilities = _readCapabilities(handshake);
    } on Object catch (error) {
      await helloSubscription.cancel();
      await _cleanup(device.id);
      if (error is BackendFailure) rethrow;
      throw _failure(
        error is TimeoutException
            ? 'The Android agent did not complete its handshake.'
            : 'The Android agent could not start.',
        error,
      );
    }
    await helloSubscription.cancel();
  }

  @override
  Future<void> stop(DeviceSummary device) => _cleanup(device.id);

  Future<void> _cleanup(String deviceId) async {
    _process?.kill();
    _process = null;
    await _bestEffort(() => _stopRemoteAgent(deviceId));
    await _bestEffort(() => adb.removeReverse(deviceId, _devicePort));
    await _bestEffort(
      () => adb.shell(deviceId, const ['rm', '-f', _remotePath]),
    );
    await _server?.close();
    _server = null;
    _capabilities = const {};
    _helloData = const {};
  }

  Future<void> _stopRemoteAgent(String deviceId) async {
    final output = await adb.shell(deviceId, const [
      'ps',
      '-A',
      '-o',
      'PID,ARGS',
    ]);
    for (final line in output.split('\n')) {
      if (!line.contains('io.github.shrey113.openandroiddex.agent.Main')) {
        continue;
      }
      final pid = int.tryParse(line.trim().split(RegExp(r'\s+')).first);
      if (pid != null) await adb.shell(deviceId, ['kill', '$pid']);
    }
  }
}

class CompanionBootComponent
    implements
        BootComponent,
        BackendStateProvider,
        NotificationGateway,
        UserDisconnectProvider {
  CompanionBootComponent({
    required this.adb,
    required this.sessionToken,
    required this.companionApkPath,
    this.handshakeTimeout = const Duration(seconds: 15),
  });

  static const _devicePort = 3699;
  static const packageName = 'io.github.shrey113.openandroiddex.companion';

  final AdbClient adb;
  final String sessionToken;
  final String companionApkPath;
  final Duration handshakeTimeout;
  CompanionWebSocketServer? _server;
  StreamSubscription<ProtocolEnvelope>? _eventSubscription;
  final StreamController<BackendStateUpdate> _updates =
      StreamController<BackendStateUpdate>.broadcast(sync: true);
  Set<String> _capabilities = const {};
  Map<String, Object?> _helloData = const {};
  DeviceTelemetry _telemetry = const DeviceTelemetry();
  PermissionState _permissions = const PermissionState();
  MediaState? _media;
  final Map<String, NotificationItem> _notifications = {};
  final _disconnectRequests = StreamController<void>.broadcast();
  bool _disconnectRequested = false;

  @override
  bool get userDisconnectRequested => _disconnectRequested;

  @override
  Stream<void> get userDisconnectRequests => _disconnectRequests.stream;

  @override
  String get stageId => 'companion';

  Set<String> get capabilities => _capabilities;

  Map<String, Object?> get helloData => _helloData;

  CompanionWebSocketServer? get server => _server;

  @override
  BackendStateUpdate get currentUpdate => BackendStateUpdate(
    telemetry: _telemetry,
    permissions: _permissions,
    media: _media,
    notificationStatus: _permissions.status == LoadStatus.idle
        ? LoadStatus.idle
        : _notifications.isEmpty
        ? LoadStatus.empty
        : LoadStatus.ready,
    notifications: List.unmodifiable(_notifications.values),
  );

  @override
  Stream<BackendStateUpdate> get updates => _updates.stream;

  Future<ProtocolEnvelope> request(
    String type, {
    Map<String, Object?> data = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final server = _server;
    if (server == null || !server.isAuthenticated) {
      throw _notificationFailure(
        OpenDexErrorCode.connectionFailed,
        'The Android companion is unavailable.',
        retryable: true,
      );
    }
    if (!_capabilities.contains('notification-actions')) {
      throw _notificationFailure(
        OpenDexErrorCode.capabilityUnavailable,
        'Notification actions are unavailable on this companion build.',
      );
    }
    final requestId =
        'request-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
    final response = Completer<ProtocolEnvelope>();
    final subscription = server.messages.listen((message) {
      if (message.type == 'notification.command.result' &&
          message.data['replyTo'] == requestId &&
          !response.isCompleted) {
        response.complete(message);
      }
    });
    try {
      server.send(
        ProtocolEnvelope(
          id: requestId,
          type: type,
          timestamp: DateTime.now().toUtc(),
          data: data,
        ),
      );
      final result = await response.future.timeout(timeout);
      if (result.data['success'] != true) {
        final unavailable = result.data['error'] == 'unavailable';
        throw _notificationFailure(
          unavailable
              ? OpenDexErrorCode.capabilityUnavailable
              : OpenDexErrorCode.connectionFailed,
          unavailable
              ? 'That notification cannot be opened on the phone.'
              : 'The notification is no longer available.',
        );
      }
      return result;
    } on TimeoutException {
      throw _notificationFailure(
        OpenDexErrorCode.timeout,
        'The phone did not answer the notification command in time.',
        retryable: true,
      );
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> dismiss(String notificationId) async {
    _validateNotificationId(notificationId);
    await request('notification.dismiss', data: {'key': notificationId});
  }

  @override
  Future<void> activate(String notificationId, {int? displayId}) async {
    _validateNotificationId(notificationId);
    await request(
      'notification.activate',
      data: {'key': notificationId, 'displayId': ?displayId},
    );
  }

  @override
  Future<void> dismissAll() async {
    await request('notification.dismissAll');
  }

  @override
  Future<void> start(DeviceSummary device) async {
    if (!File(companionApkPath).existsSync()) {
      throw _failure('The Android companion APK is missing.');
    }
    _disconnectRequested = false;
    final server = CompanionWebSocketServer(sessionToken: sessionToken);
    _server = server;
    _eventSubscription = server.messages.listen(_handleEvent);
    final hello = Completer<ProtocolEnvelope>();
    final helloSubscription = server.messages.listen((message) {
      if (message.type == 'companion.hello' && !hello.isCompleted) {
        hello.complete(message);
      }
    });
    try {
      final hostPort = await server.start();
      await adb.installIfNeeded(device.id, companionApkPath, packageName);
      await adb.reverse(device.id, devicePort: _devicePort, hostPort: hostPort);
      await adb.stopServiceIfRunning(
        device.id,
        '$packageName/.CompanionService',
      );
      await adb.shell(device.id, [
        'am',
        'start-foreground-service',
        '-n',
        '$packageName/.CompanionService',
        '--es',
        'session_token',
        sessionToken,
      ]);
      final handshake = await hello.future.timeout(handshakeTimeout);
      _helloData = Map.unmodifiable(handshake.data);
      _capabilities = _readCapabilities(handshake);
      server.send(
        ProtocolEnvelope(
          id: 'welcome',
          type: 'companion.welcome',
          timestamp: DateTime.now().toUtc(),
          data: {
            'sessionDisconnect': handshake.data['sessionDisconnect'] == true,
          },
        ),
      );
    } on Object catch (error) {
      await helloSubscription.cancel();
      await _cleanup(device.id);
      if (error is BackendFailure) rethrow;
      if (error is AdbException) {
        throw _failure(
          error.operation == 'install companion'
              ? error.message.contains('different key')
                    ? error.message
                    : 'Android did not allow the companion installation or update. Check the phone for an approval or Play Protect prompt.'
              : 'The companion is installed, but Android refused its startup or USB tunnel. Open DroidPier Companion on the phone and retry.',
          'operation=${error.operation}; exit=${error.exitCode}; timeout=${error.timedOut}',
        );
      }
      throw _failure(
        error is TimeoutException
            ? 'The Android companion did not complete its handshake.'
            : 'The Android companion could not start.',
        error,
      );
    }
    await helloSubscription.cancel();
  }

  @override
  Future<void> stop(DeviceSummary device) => _cleanup(device.id);

  Future<void> _cleanup(String deviceId) async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _bestEffort(
      () => adb.shell(deviceId, const [
        'am',
        'stopservice',
        '-n',
        '$packageName/.CompanionService',
      ]),
    );
    await _bestEffort(() => adb.removeReverse(deviceId, _devicePort));
    await _server?.close();
    _server = null;
    _capabilities = const {};
    _helloData = const {};
    _telemetry = const DeviceTelemetry();
    _permissions = const PermissionState();
    _media = null;
    _notifications.clear();
  }

  void _handleEvent(ProtocolEnvelope message) {
    switch (message.type) {
      case 'companion.disconnect.request':
        if (_helloData['sessionDisconnect'] != true || _disconnectRequested) {
          return;
        }
        _disconnectRequested = true;
        _server?.send(
          ProtocolEnvelope(
            id: 'disconnect-ack',
            type: 'companion.disconnect.ack',
            timestamp: DateTime.now().toUtc(),
            data: {'replyTo': message.id},
          ),
        );
        _disconnectRequests.add(null);
        return;
      case 'battery.update':
        final percentage = message.data['percentage'];
        final charging = message.data['charging'];
        _telemetry = DeviceTelemetry(
          batteryPercentage:
              percentage is int && percentage >= 0 && percentage <= 100
              ? percentage
              : null,
          charging: charging == true,
          wifiEnabled: _telemetry.wifiEnabled,
          bluetoothEnabled: _telemetry.bluetoothEnabled,
          airplaneMode: _telemetry.airplaneMode,
          rotationLocked: _telemetry.rotationLocked,
          torchEnabled: _telemetry.torchEnabled,
          mobileDataEnabled: _telemetry.mobileDataEnabled,
          locationEnabled: _telemetry.locationEnabled,
          volume: _telemetry.volume,
          linkLatency: _telemetry.linkLatency,
          throughput: _telemetry.throughput,
          framesPerSecond: _telemetry.framesPerSecond,
        );
        break;
      case 'device.update':
        _telemetry = DeviceTelemetry(
          batteryPercentage: _telemetry.batteryPercentage,
          charging: _telemetry.charging,
          wifiEnabled: message.data['wifiEnabled'] is bool
              ? message.data['wifiEnabled'] as bool
              : _telemetry.wifiEnabled,
          bluetoothEnabled: message.data['bluetoothEnabled'] is bool
              ? message.data['bluetoothEnabled'] as bool
              : _telemetry.bluetoothEnabled,
          airplaneMode: message.data['airplaneMode'] is bool
              ? message.data['airplaneMode'] as bool
              : _telemetry.airplaneMode,
          rotationLocked: message.data['rotationLocked'] is bool
              ? message.data['rotationLocked'] as bool
              : _telemetry.rotationLocked,
          torchEnabled: _telemetry.torchEnabled,
          mobileDataEnabled: message.data['mobileDataEnabled'] is bool
              ? message.data['mobileDataEnabled'] as bool
              : _telemetry.mobileDataEnabled,
          locationEnabled: message.data['locationEnabled'] is bool
              ? message.data['locationEnabled'] as bool
              : _telemetry.locationEnabled,
          volume: _volumeLevels(message.data['volume'], _telemetry.volume),
          linkLatency: _telemetry.linkLatency,
          throughput: _telemetry.throughput,
          framesPerSecond: _telemetry.framesPerSecond,
        );
        break;
      case 'media.update':
        final Object? pos = message.data['positionMs'];
        final Object? dur = message.data['durationMs'];
        final Object? title = message.data['title'];
        final Object? artist = message.data['artist'];
        final Object? art = message.data['artwork'];
        List<int>? artwork;
        if (art is String && art.isNotEmpty) {
          try {
            artwork = base64Decode(art);
          } on FormatException {
            artwork = null;
          }
        }
        _media = MediaState(
          status: LoadStatus.ready,
          playback: switch (message.data['playback']) {
            'playing' => PlaybackState.playing,
            'paused' => PlaybackState.paused,
            'stopped' => PlaybackState.stopped,
            _ => PlaybackState.unavailable,
          },
          title: title is String && title.isNotEmpty ? title : null,
          artist: artist is String && artist.isNotEmpty ? artist : null,
          artwork: artwork,
          positionMs: pos is num ? pos.toInt() : null,
          durationMs: dur is num && dur > 0 ? dur.toInt() : null,
        );
        break;
      case 'permissions.update':
        _permissions = PermissionState(
          status: LoadStatus.ready,
          grants: {
            'notifications': message.data['notifications'] == true
                ? PermissionGrant.granted
                : PermissionGrant.requiresSettings,
          },
        );
        break;
      case 'notification.posted':
        final notification = _notificationFrom(message.data);
        if (notification != null) {
          _notifications[notification.id] = notification;
        }
        break;
      case 'notification.removed':
        final key = message.data['key'];
        if (key is String) _notifications.remove(key);
        break;
      default:
        return;
    }
    if (!_updates.isClosed) _updates.add(currentUpdate);
  }

  static Map<String, VolumeLevel> _volumeLevels(
    Object? value,
    Map<String, VolumeLevel> fallback,
  ) {
    if (value is! Map) return fallback;
    final levels = <String, VolumeLevel>{};
    for (final entry in value.entries) {
      final level = entry.value;
      if (entry.key is! String || level is! Map) continue;
      final current = level['current'];
      final maximum = level['maximum'];
      if (current is int && maximum is int && maximum > 0) {
        levels[entry.key as String] = VolumeLevel(
          current: current.clamp(0, maximum),
          maximum: maximum,
        );
      }
    }
    return levels.isEmpty ? fallback : Map.unmodifiable(levels);
  }

  static NotificationItem? _notificationFrom(Map<String, Object?> data) {
    final key = data['key'];
    final packageName = data['packageName'];
    final timestamp = data['timestamp'];
    if (key is! String || packageName is! String || timestamp is! int) {
      return null;
    }
    return NotificationItem(
      id: key,
      packageName: packageName,
      title: data['title'] is String ? data['title'] as String : '',
      body: data['body'] is String ? data['body'] as String : '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc(),
    );
  }

  static void _validateNotificationId(String notificationId) {
    if (notificationId.isEmpty || notificationId.length > 4096) {
      throw _notificationFailure(
        OpenDexErrorCode.capabilityUnavailable,
        'That notification identifier is invalid.',
      );
    }
  }

  static BackendFailure _notificationFailure(
    OpenDexErrorCode code,
    String message, {
    bool retryable = false,
  }) => BackendFailure(
    OpenDexError(
      code: code,
      message: message,
      retryable: retryable,
      capability: 'notification-actions',
    ),
  );
}

class ApplicationCatalogBootComponent
    implements BootComponent, ApplicationCatalogProvider {
  ApplicationCatalogBootComponent({
    required this.agent,
    this.responseTimeout = const Duration(seconds: 10),
  });

  final AgentBootComponent agent;
  final Duration responseTimeout;
  List<AndroidApplication> _applications = const [];

  @override
  String get stageId => 'applications';

  @override
  List<AndroidApplication> get applications => _applications;

  @override
  Future<void> start(DeviceSummary device) async {
    try {
      final message = await agent.request(
        'apps.list',
        responseType: 'apps.result',
        timeout: responseTimeout,
      );
      if (message.data['success'] != true) {
        throw const ProtocolException('Android package query failed.');
      }
      _applications = parseApplications(message.data['applications']);
    } on Object catch (error) {
      throw _catalogFailure(
        error is TimeoutException
            ? 'The Android application list did not arrive in time.'
            : 'DroidPier could not load Android applications.',
        error,
      );
    }
  }

  @override
  Future<void> stop(DeviceSummary device) async {
    _applications = const [];
  }

  static List<AndroidApplication> parseApplications(Object? value) {
    if (value is! Iterable) return const [];
    final byPackage = <String, AndroidApplication>{};
    for (final item in value) {
      if (item is! Map) continue;
      final packageName = item['packageName'];
      final label = item['label'];
      if (packageName is! String || !_packageName.hasMatch(packageName)) {
        continue;
      }
      byPackage[packageName] = AndroidApplication(
        packageName: packageName,
        label: label is String && label.trim().isNotEmpty
            ? label.trim()
            : packageName,
        iconPng: _parseIcon(item['iconPngBase64']),
        isSystemApp: item['isSystemApp'] == true,
      );
    }
    final applications = byPackage.values.toList()
      ..sort((left, right) => left.label.compareTo(right.label));
    return List.unmodifiable(applications);
  }

  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static List<int>? _parseIcon(Object? value) {
    if (value is! String || value.isEmpty || value.length > 131072) return null;
    try {
      final bytes = base64Decode(value);
      if (bytes.length < 8 || bytes.length > 98304) return null;
      const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      for (var index = 0; index < pngSignature.length; index++) {
        if (bytes[index] != pngSignature[index]) return null;
      }
      return List<int>.unmodifiable(bytes);
    } on FormatException {
      return null;
    }
  }
}

class AgentClipboardBootComponent
    implements BootComponent, BackendStateProvider, ClipboardGateway {
  AgentClipboardBootComponent({
    required this.agent,
    this.pollInterval = const Duration(seconds: 1),
    this.responseTimeout = const Duration(seconds: 3),
  });

  final AgentBootComponent agent;
  final Duration pollInterval;
  final Duration responseTimeout;
  final _updates = StreamController<BackendStateUpdate>.broadcast(sync: true);
  ClipboardState _clipboard = const ClipboardState();
  Timer? _pollTimer;
  bool _supported = false;
  bool _polling = false;
  int _revision = 0;

  @override
  String get stageId => 'clipboard';
  @override
  ClipboardState get clipboard => _clipboard;
  @override
  BackendStateUpdate get currentUpdate =>
      BackendStateUpdate(clipboard: _clipboard);
  @override
  Stream<BackendStateUpdate> get updates => _updates.stream;

  @override
  Future<void> start(DeviceSummary device) async {
    _pollTimer?.cancel();
    _revision++;
    _supported =
        agent.capabilities.contains('clipboard.get') &&
        agent.capabilities.contains('clipboard.set');
    _clipboard = ClipboardState(
      availability: _supported
          ? ClipboardAvailability.available
          : ClipboardAvailability.unavailable,
      message: _supported
          ? null
          : 'Clipboard sync is unavailable on this Android build.',
    );
    _publish();
    // Negotiation never reads clipboard content. Only explicit opt-in does.
    if (_supported) {
      _pollTimer = Timer.periodic(pollInterval, (_) {
        if (_clipboard.syncEnabled) unawaited(_refresh());
      });
    }
  }

  @override
  Future<void> stop(DeviceSummary device) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _supported = false;
    _revision++;
    _clipboard = const ClipboardState();
    _publish();
  }

  @override
  void setSyncEnabled(bool enabled) {
    if (enabled && !_supported) throw _unavailable();
    _revision++;
    _clipboard = ClipboardState(
      availability: _clipboard.availability,
      syncEnabled: enabled && _supported,
    );
    _publish();
    if (_clipboard.syncEnabled) unawaited(_refresh());
  }

  @override
  Future<void> writeText(String text) async {
    if (!_supported || !_clipboard.syncEnabled) throw _unavailable();
    final revision = ++_revision;
    try {
      final response = await agent.request(
        'clipboard.set',
        data: {'text': text},
        timeout: responseTimeout,
      );
      if (revision != _revision) return;
      if (response.data['success'] != true) {
        _pause(unsupported: true);
        throw _unavailable();
      }
      _clipboard = ClipboardState(
        kind: text.isEmpty ? ClipboardKind.empty : ClipboardKind.text,
        text: text.isEmpty ? null : text,
        syncEnabled: true,
        availability: ClipboardAvailability.available,
      );
      _publish();
    } on Object {
      if (revision == _revision) _pause();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    if (_polling || !_supported || !_clipboard.syncEnabled) return;
    _polling = true;
    final revision = _revision;
    try {
      final response = await agent.request(
        'clipboard.get',
        responseType: 'clipboard.result',
        timeout: responseTimeout,
      );
      if (revision != _revision) return;
      if (response.data['success'] != true) {
        _pause(unsupported: true);
        return;
      }
      final text = response.data['text'];
      if (text is! String || text.length > 65536) {
        _pause();
        return;
      }
      _clipboard = ClipboardState(
        kind: text.isEmpty ? ClipboardKind.empty : ClipboardKind.text,
        text: text.isEmpty ? null : text,
        syncEnabled: true,
        availability: ClipboardAvailability.available,
      );
      _publish();
    } on Object {
      if (revision == _revision) _pause();
    } finally {
      _polling = false;
    }
  }

  void _pause({bool unsupported = false}) {
    _revision++;
    if (unsupported) _supported = false;
    _clipboard = ClipboardState(
      availability: unsupported
          ? ClipboardAvailability.unavailable
          : ClipboardAvailability.available,
      message: unsupported
          ? 'Clipboard access was refused by Android. Sync is off for this connection.'
          : 'Clipboard sync paused after a communication error. Retry when the phone is ready.',
    );
    _publish();
  }

  void _publish() {
    if (!_updates.isClosed) _updates.add(currentUpdate);
  }

  static BackendFailure _unavailable() => const BackendFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'Clipboard sync is not available or has not been enabled.',
      capability: 'clipboard',
    ),
  );
}

Set<String> _readCapabilities(ProtocolEnvelope hello) {
  final value = hello.data['capabilities'];
  if (value is! Iterable) return const {};
  final capabilities = <String>{};
  for (final item in value) {
    if (item is String) capabilities.add(item);
  }
  return Set.unmodifiable(capabilities);
}

BackendFailure _failure(String message, [Object? cause]) => BackendFailure(
  OpenDexError(
    code: cause is TimeoutException
        ? OpenDexErrorCode.timeout
        : OpenDexErrorCode.deploymentFailed,
    message: message,
    retryable: true,
    technicalDetails: cause?.toString(),
  ),
);

BackendFailure _catalogFailure(String message, [Object? cause]) =>
    BackendFailure(
      OpenDexError(
        code: cause is TimeoutException
            ? OpenDexErrorCode.timeout
            : OpenDexErrorCode.protocolError,
        message: message,
        retryable: true,
        technicalDetails: cause?.toString(),
      ),
    );

Future<void> _bestEffort(Future<Object?> Function() operation) async {
  try {
    await operation();
  } on Object {
    // Cleanup continues so a disconnected device cannot strand host resources.
  }
}
