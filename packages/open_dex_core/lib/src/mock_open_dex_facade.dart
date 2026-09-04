import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';

enum MockScenario {
  disconnected,
  ready,
  permissionRequired,
  recovering,
  failure,
}

class MockOpenDexFacade implements OpenDexFacade {
  MockOpenDexFacade({
    MockScenario scenario = MockScenario.ready,
    this.attachSurfaces = false,
  }) : _snapshot = _snapshotFor(scenario);

  /// Whether a launched window carries a stub [WindowSurface].
  ///
  /// Off by default so existing tests still see the surface-less window they
  /// were written against. On when a test needs UI that only appears with a
  /// live surface — fullscreen, the live badge — without a real texture backend.
  final bool attachSurfaces;

  final StreamController<OpenDexSnapshot> _controller =
      StreamController<OpenDexSnapshot>.broadcast(sync: true);
  OpenDexSnapshot _snapshot;
  int _sessionSequence = 0;

  @override
  OpenDexSnapshot get snapshot => _snapshot;

  @override
  Stream<OpenDexSnapshot> get states => _controller.stream;

  void showScenario(MockScenario scenario) => _emit(_snapshotFor(scenario));

  void _emit(OpenDexSnapshot value) {
    _snapshot = value;
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }

  @override
  Future<CommandResult<List<DeviceSummary>>> discoverDevices() async {
    _emit(_snapshot.copyWith(deviceStatus: LoadStatus.loading));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final devices = _demoDevices;
    _emit(_snapshot.copyWith(deviceStatus: LoadStatus.ready, devices: devices));
    return CommandSuccess(devices);
  }

  @override
  Future<VoidResult> selectDevice(String deviceId) async {
    final matches = _snapshot.devices.where((device) => device.id == deviceId);
    if (matches.isEmpty) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.deviceOffline,
          message: 'That Android device is no longer available.',
          retryable: true,
        ),
      );
    }
    if (_snapshot.boot.isReady && _snapshot.selectedDevice?.id != deviceId) {
      await disconnect();
    }
    _emit(_snapshot.copyWith(selectedDevice: matches.first));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> connectSelectedDevice() async {
    if (_snapshot.selectedDevice == null) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Select a device before connecting.',
        ),
      );
    }
    _emit(
      _snapshot.copyWith(
        boot: const BootState(
          phase: BootPhase.awaitingHandshakes,
          progress: .78,
          message: 'Starting Android services…',
          stages: [
            BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
            BootStage(
              id: 'device',
              label: 'Device',
              status: StageStatus.complete,
            ),
            BootStage(
              id: 'agent',
              label: 'Agent :3698',
              status: StageStatus.complete,
            ),
            BootStage(
              id: 'companion',
              label: 'Companion :3699',
              status: StageStatus.active,
            ),
            BootStage(id: 'applications', label: 'Applications'),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _emit(
      _snapshot.copyWith(
        boot: const BootState(
          phase: BootPhase.ready,
          progress: 1,
          message: 'Connected',
          stages: [
            BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
            BootStage(
              id: 'device',
              label: 'Device',
              status: StageStatus.complete,
            ),
            BootStage(
              id: 'agent',
              label: 'Agent :3698',
              status: StageStatus.complete,
            ),
            BootStage(
              id: 'companion',
              label: 'Companion :3699',
              status: StageStatus.complete,
            ),
            BootStage(
              id: 'applications',
              label: 'Applications',
              status: StageStatus.complete,
            ),
          ],
        ),
        applicationStatus: LoadStatus.ready,
        applications: _demoApplications,
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> disconnect() async {
    _emit(
      _snapshot.copyWith(
        boot: const BootState(),
        selectedDevice: null,
        windows: const [],
        recovery: const RecoveryState(),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> retryBoot() => connectSelectedDevice();

  @override
  Future<CommandResult<String>> launchApplication(String packageName) async {
    final matches = _snapshot.applications.where(
      (application) => application.packageName == packageName,
    );
    if (matches.isEmpty) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'The selected application is unavailable.',
        ),
      );
    }
    final id = 'mock-window-${++_sessionSequence}';
    final session = WindowSessionState(
      id: id,
      application: matches.first,
      status: WindowSessionStatus.streaming,
      displayId: 10 + _sessionSequence,
      isFocused: true,
      // Opening an app on desk 3 and having it appear on desk 1 reads as the
      // window failing to open at all.
      workspace: _snapshot.currentWorkspace,
      geometry: WindowGeometry(
        x: 64 + ((_sessionSequence - 1) % 6) * 28,
        y: 64 + ((_sessionSequence - 1) % 6) * 28,
        width: 640,
        height: 480,
      ),
      zOrder: _sessionSequence,
      surface: attachSurfaces
          ? WindowSurface(
              textureId: _sessionSequence,
              pixelSize: const WindowPixelSize(width: 720, height: 1280),
            )
          : null,
    );
    _emit(
      _snapshot.copyWith(
        windows: [
          for (final window in _snapshot.windows)
            _copyWindow(window, isFocused: false),
          session,
        ],
      ),
    );
    return CommandSuccess(id);
  }

  @override
  Future<VoidResult> closeWindow(String sessionId) async {
    _emit(
      _snapshot.copyWith(
        windows: _snapshot.windows
            .where((window) => window.id != sessionId)
            .toList(),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> focusWindow(String sessionId) async {
    if (!_snapshot.windows.any((window) => window.id == sessionId)) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'That application window has closed.',
        ),
      );
    }
    _emit(
      _snapshot.copyWith(
        windows: [
          for (final window in _snapshot.windows)
            _copyWindow(window, isFocused: window.id == sessionId),
        ],
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> moveWindow(
    String sessionId,
    WindowGeometry geometry,
  ) async {
    if (!_validGeometry(geometry)) return _invalidWindowGeometry;
    return _updateWindow(
      sessionId,
      (window) => _copyWindow(window, geometry: geometry),
    );
  }

  @override
  Future<VoidResult> setWindowDisplayState(
    String sessionId,
    WindowDisplayState state,
  ) => _updateWindow(
    sessionId,
    (window) => _copyWindow(
      window,
      displayState: state,
      isFocused: state == WindowDisplayState.minimised
          ? false
          : window.isFocused,
    ),
  );

  @override
  Future<VoidResult> raiseWindow(String sessionId) {
    final topZ = _snapshot.windows.fold<int>(
      -1,
      (highest, window) => window.zOrder > highest ? window.zOrder : highest,
    );
    return _updateWindow(
      sessionId,
      (window) => _copyWindow(window, zOrder: topZ + 1),
    );
  }

  @override
  Future<VoidResult> selectWorkspace(int workspace) async {
    if (!isValidWorkspace(workspace)) return _invalidWorkspace;
    _emit(_snapshot.copyWith(currentWorkspace: workspace));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> moveWindowToWorkspace(
    String sessionId,
    int workspace,
  ) async {
    if (!isValidWorkspace(workspace)) return _invalidWorkspace;
    return _updateWindow(
      sessionId,
      (window) => window.copyWith(workspace: workspace),
    );
  }

  @override
  Future<VoidResult> setWindowScale(String sessionId, double scale) async {
    if (!isValidWindowScale(scale)) return _invalidWindowScale;
    return _updateWindow(sessionId, (window) => window.copyWith(scale: scale));
  }

  @override
  Future<VoidResult> setWindowOrientation(
    String sessionId, {
    required bool landscape,
  }) => _updateWindow(sessionId, (window) {
    if (window.isLandscape == landscape) return window;
    // Rotating swaps the aspect rather than resizing to a remembered box, so
    // rotating back lands exactly where it started without storing anything.
    return window.copyWith(
      isLandscape: landscape,
      geometry: WindowGeometry(
        x: window.geometry.x,
        y: window.geometry.y,
        width: window.geometry.height,
        height: window.geometry.width,
      ),
    );
  });

  @override
  Future<VoidResult> openUrl(String url) async =>
      isWebUrl(url) ? const CommandSuccess(null) : _invalidUrl;

  @override
  Future<VoidResult> sendPointer(
    String sessionId,
    WindowPointerSample sample,
  ) => _windowCommand(sessionId);

  @override
  Future<VoidResult> sendKey(String sessionId, WindowKeySample sample) =>
      _windowCommand(sessionId);

  @override
  Future<VoidResult> sendNavKey(String sessionId, AndroidNavKey key) =>
      _windowCommand(sessionId);

  @override
  Future<VoidResult> setClipboardText(String text) async {
    _emit(
      _snapshot.copyWith(
        clipboard: ClipboardState(
          kind: ClipboardKind.text,
          text: text,
          syncEnabled: _snapshot.clipboard.syncEnabled,
          availability: ClipboardAvailability.available,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> setClipboardSync(bool enabled) async {
    _emit(
      _snapshot.copyWith(
        clipboard: ClipboardState(
          kind: _snapshot.clipboard.kind,
          text: _snapshot.clipboard.text,
          imagePng: _snapshot.clipboard.imagePng,
          syncEnabled: enabled,
          availability: ClipboardAvailability.available,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> pauseClipboardSync() async {
    _emit(
      _snapshot.copyWith(
        clipboard: const ClipboardState(
          availability: ClipboardAvailability.available,
          message: ClipboardState.desktopFailureMessage,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> setVolume(String stream, int value) async {
    final current = _snapshot.telemetry.volume[stream];
    if (current == null || value < 0 || value > current.maximum) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'That volume level is unavailable.',
        ),
      );
    }
    final volume = Map<String, VolumeLevel>.from(_snapshot.telemetry.volume)
      ..[stream] = VolumeLevel(current: value, maximum: current.maximum);
    _emit(
      _snapshot.copyWith(
        telemetry: DeviceTelemetry(
          batteryPercentage: _snapshot.telemetry.batteryPercentage,
          charging: _snapshot.telemetry.charging,
          wifiEnabled: _snapshot.telemetry.wifiEnabled,
          bluetoothEnabled: _snapshot.telemetry.bluetoothEnabled,
          airplaneMode: _snapshot.telemetry.airplaneMode,
          rotationLocked: _snapshot.telemetry.rotationLocked,
          torchEnabled: _snapshot.telemetry.torchEnabled,
          volume: volume,
          linkLatency: _snapshot.telemetry.linkLatency,
          throughput: _snapshot.telemetry.throughput,
          framesPerSecond: _snapshot.telemetry.framesPerSecond,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> sendMediaAction(MediaAction action) async {
    final playback =
        action == MediaAction.playPause &&
            _snapshot.media.playback == PlaybackState.playing
        ? PlaybackState.paused
        : PlaybackState.playing;
    _emit(
      _snapshot.copyWith(
        media: MediaState(
          status: LoadStatus.ready,
          playback: playback,
          title: _snapshot.media.title,
          artist: _snapshot.media.artist,
          artwork: _snapshot.media.artwork,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> setDeviceControl(
    DeviceControl control,
    bool enabled,
  ) async {
    if (control == DeviceControl.wifi &&
        !enabled &&
        _snapshot.selectedDevice?.connectionKind == DeviceConnectionKind.wifi) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message:
              'Wi-Fi stays on while this phone is connected wirelessly. '
              'Connect with USB before turning it off.',
          capability: 'wifi-control',
        ),
      );
    }
    final old = _snapshot.telemetry;
    _emit(
      _snapshot.copyWith(
        telemetry: DeviceTelemetry(
          batteryPercentage: old.batteryPercentage,
          charging: old.charging,
          wifiEnabled: control == DeviceControl.wifi
              ? enabled
              : old.wifiEnabled,
          bluetoothEnabled: control == DeviceControl.bluetooth
              ? enabled
              : old.bluetoothEnabled,
          airplaneMode: control == DeviceControl.airplaneMode
              ? enabled
              : old.airplaneMode,
          rotationLocked: control == DeviceControl.rotationLock
              ? enabled
              : old.rotationLocked,
          torchEnabled: control == DeviceControl.torch
              ? enabled
              : old.torchEnabled,
          volume: old.volume,
          linkLatency: old.linkLatency,
          throughput: old.throughput,
          framesPerSecond: old.framesPerSecond,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> openPermissionSettings(String capability) async =>
      capability == 'notifications'
      ? const CommandSuccess(null)
      : const CommandFailure(
          OpenDexError(
            code: OpenDexErrorCode.capabilityUnavailable,
            message: 'That permission settings screen is unavailable.',
            capability: 'permission-settings',
          ),
        );

  @override
  Future<VoidResult> dismissNotification(String notificationId) async {
    if (!_snapshot.notifications.any((item) => item.id == notificationId)) {
      return _missingNotification();
    }
    _emit(
      _snapshot.copyWith(
        notificationStatus: _snapshot.notifications.length == 1
            ? LoadStatus.empty
            : LoadStatus.ready,
        notifications: _snapshot.notifications
            .where((item) => item.id != notificationId)
            .toList(),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> activateNotification(String notificationId) async =>
      _snapshot.notifications.any((item) => item.id == notificationId)
      ? const CommandSuccess(null)
      : _missingNotification();

  @override
  Future<VoidResult> dismissAllNotifications() async {
    _emit(
      _snapshot.copyWith(
        notificationStatus: LoadStatus.empty,
        notifications: const [],
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> startWirelessDiscovery() async {
    _emit(
      _snapshot.copyWith(
        wirelessDiscovery: const WirelessDiscoveryState(
          status: WirelessDiscoveryStatus.ready,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> stopWirelessDiscovery() async {
    await cancelWirelessPairing();
    _emit(
      _snapshot.copyWith(wirelessDiscovery: const WirelessDiscoveryState()),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> startQrPairing() async {
    _emit(
      _snapshot.copyWith(
        wirelessPairing: WirelessPairingState(
          phase: WirelessPairingPhase.waitingForScan,
          qrPayload: 'WIFI:T:ADB;S:studio-demo;P:synthetic-demo-only;;',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> cancelWirelessPairing() async {
    _emit(_snapshot.copyWith(wirelessPairing: const WirelessPairingState()));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> pairWirelessDevice({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Enter the six-digit pairing code shown on the phone.',
        ),
      );
    }
    _emit(
      _snapshot.copyWith(
        wirelessPairing: WirelessPairingState(
          phase: WirelessPairingPhase.needsConnectionPort,
          host: host,
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<CommandResult<DeviceSummary>> connectWirelessDevice({
    required String host,
    required int port,
  }) async {
    final device = DeviceSummary(
      id: '$host:$port',
      name: 'Demo wireless device',
      connectionKind: DeviceConnectionKind.wifi,
      status: DeviceStatus.authorized,
    );
    _emit(
      _snapshot.copyWith(
        deviceStatus: LoadStatus.ready,
        devices: [
          for (final existing in _snapshot.devices)
            if (existing.id != device.id) existing,
          device,
        ],
        selectedDevice: _snapshot.boot.isReady
            ? _snapshot.selectedDevice
            : device,
      ),
    );
    return CommandSuccess(device);
  }

  @override
  Future<VoidResult> forgetWirelessDevice(String deviceId) async {
    final matches = _snapshot.devices.where((device) => device.id == deviceId);
    if (matches.isEmpty ||
        matches.single.connectionKind != DeviceConnectionKind.wifi) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.deviceOffline,
          message: 'That wireless Android device is no longer available.',
        ),
      );
    }
    if (_snapshot.selectedDevice?.id == deviceId) await disconnect();
    _emit(
      _snapshot.copyWith(
        devices: _snapshot.devices
            .where((device) => device.id != deviceId)
            .toList(),
        selectedDevice: _snapshot.selectedDevice?.id == deviceId
            ? null
            : _snapshot.selectedDevice,
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> reconnect() async {
    _emit(
      _snapshot.copyWith(
        recovery: const RecoveryState(
          phase: RecoveryPhase.reconnecting,
          attempt: 1,
          message: 'Reconnecting to the Android device…',
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _emit(
      _snapshot.copyWith(
        recovery: const RecoveryState(
          phase: RecoveryPhase.recovered,
          attempt: 1,
          message: 'Connection restored',
        ),
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<void> dispose() => _controller.close();

  Future<VoidResult> _updateWindow(
    String sessionId,
    WindowSessionState Function(WindowSessionState window) update,
  ) async {
    if (!_snapshot.windows.any((window) => window.id == sessionId)) {
      return _missingWindow;
    }
    _emit(
      _snapshot.copyWith(
        windows: [
          for (final window in _snapshot.windows)
            window.id == sessionId ? update(window) : window,
        ],
      ),
    );
    return const CommandSuccess(null);
  }

  Future<VoidResult> _windowCommand(String sessionId) async =>
      _snapshot.windows.any((window) => window.id == sessionId)
      ? const CommandSuccess(null)
      : _missingWindow;

  static bool _validGeometry(WindowGeometry geometry) =>
      geometry.x.isFinite &&
      geometry.y.isFinite &&
      geometry.width.isFinite &&
      geometry.height.isFinite &&
      geometry.width >= WindowGeometry.minimumWidth &&
      geometry.height >= WindowGeometry.minimumHeight;

  static WindowSessionState _copyWindow(
    WindowSessionState source, {
    bool? isFocused,
    WindowGeometry? geometry,
    WindowDisplayState? displayState,
    int? zOrder,
  }) => source.copyWith(
    isFocused: isFocused,
    geometry: geometry,
    displayState: displayState,
    zOrder: zOrder,
  );

  static const _missingWindow = CommandFailure<void>(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That application window has closed.',
      capability: 'window-management',
    ),
  );

  static const _invalidWindowGeometry = CommandFailure<void>(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'The application window size or position is invalid.',
      capability: 'window-management',
    ),
  );

  static const _invalidWorkspace = CommandFailure<void>(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That workspace does not exist.',
      capability: 'window-management',
    ),
  );

  static const _invalidWindowScale = CommandFailure<void>(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That zoom level is outside the range a window can be drawn at.',
      capability: 'window-management',
    ),
  );

  static const _invalidUrl = CommandFailure<void>(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That is not a web address the desk can open.',
      capability: 'url-launcher',
    ),
  );

  static OpenDexSnapshot _snapshotFor(MockScenario scenario) {
    switch (scenario) {
      case MockScenario.disconnected:
        return const OpenDexSnapshot(
          deviceStatus: LoadStatus.ready,
          devices: _demoDevices,
        );
      case MockScenario.permissionRequired:
        return _readySnapshot.copyWith(
          permissions: const PermissionState(
            status: LoadStatus.ready,
            grants: {
              'notifications': PermissionGrant.requiresSettings,
              'microphone': PermissionGrant.denied,
            },
          ),
        );
      case MockScenario.recovering:
        return _readySnapshot.copyWith(
          recovery: const RecoveryState(
            phase: RecoveryPhase.reconnecting,
            attempt: 2,
            message: 'Restoring Android services…',
          ),
        );
      case MockScenario.failure:
        return const OpenDexSnapshot(
          deviceStatus: LoadStatus.error,
          boot: BootState(
            phase: BootPhase.failed,
            message: 'Unable to connect',
            stages: [
              BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
              BootStage(
                id: 'device',
                label: 'Device',
                status: StageStatus.failed,
                detail: 'USB debugging authorization required',
              ),
              BootStage(id: 'agent', label: 'Agent :3698'),
              BootStage(id: 'companion', label: 'Companion :3699'),
              BootStage(id: 'applications', label: 'Applications'),
            ],
            error: OpenDexError(
              code: OpenDexErrorCode.deviceUnauthorized,
              message: 'Authorize USB debugging on the Android device.',
              retryable: true,
            ),
          ),
        );
      case MockScenario.ready:
        return _readySnapshot;
    }
  }

  static const _demoDevices = [
    DeviceSummary(
      id: 'demo-usb-device',
      name: 'Demo Android device',
      model: 'demo-device',
      androidVersion: '13',
      connectionKind: DeviceConnectionKind.usb,
      status: DeviceStatus.authorized,
    ),
  ];

  static const _demoApplications = [
    AndroidApplication(packageName: 'com.android.chrome', label: 'Chrome'),
    AndroidApplication(packageName: 'com.spotify.music', label: 'Spotify'),
    AndroidApplication(
      packageName: 'com.google.android.youtube',
      label: 'YouTube',
    ),
  ];

  static final _readySnapshot = OpenDexSnapshot(
    boot: const BootState(
      phase: BootPhase.ready,
      progress: 1,
      message: 'Connected',
      stages: [
        BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
        BootStage(id: 'device', label: 'Device', status: StageStatus.complete),
        BootStage(
          id: 'agent',
          label: 'Agent :3698',
          status: StageStatus.complete,
        ),
        BootStage(
          id: 'companion',
          label: 'Companion :3699',
          status: StageStatus.complete,
        ),
        BootStage(
          id: 'applications',
          label: 'Applications',
          status: StageStatus.complete,
        ),
      ],
    ),
    deviceStatus: LoadStatus.ready,
    devices: _demoDevices,
    selectedDevice: _demoDevices.first,
    applicationStatus: LoadStatus.ready,
    applications: _demoApplications,
    telemetry: const DeviceTelemetry(
      batteryPercentage: 87,
      charging: true,
      wifiEnabled: true,
      bluetoothEnabled: false,
      airplaneMode: false,
      rotationLocked: false,
      torchEnabled: false,
      volume: {
        'music': VolumeLevel(current: 8, maximum: 15),
        'ring': VolumeLevel(current: 4, maximum: 7),
      },
      linkLatency: TelemetryMeasurement(
        value: 24,
        unit: TelemetryUnit.milliseconds,
      ),
      throughput: TelemetryMeasurement(
        value: 1200000,
        unit: TelemetryUnit.bytesPerSecond,
      ),
      framesPerSecond: TelemetryMeasurement(
        value: 60,
        unit: TelemetryUnit.framesPerSecond,
      ),
    ),
    clipboard: const ClipboardState(
      kind: ClipboardKind.text,
      text: 'Clipboard sync is ready',
      availability: ClipboardAvailability.available,
    ),
    notificationStatus: LoadStatus.ready,
    notifications: [
      NotificationItem(
        id: 'demo-notification',
        packageName: 'com.example.chat',
        title: 'DroidPier',
        body: 'The mock backend is connected.',
        timestamp: DateTime.utc(2026, 8, 24, 12),
      ),
    ],
    media: const MediaState(
      status: LoadStatus.ready,
      playback: PlaybackState.playing,
      title: 'Demo Track',
      artist: 'DroidPier',
    ),
    permissions: const PermissionState(
      status: LoadStatus.ready,
      grants: {
        'notifications': PermissionGrant.granted,
        'microphone': PermissionGrant.granted,
      },
    ),
    agentStatus: AgentConnectionStatus.connected,
  );

  static CommandFailure<void> _missingNotification() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That notification is no longer available.',
      capability: 'notification-actions',
    ),
  );
}
