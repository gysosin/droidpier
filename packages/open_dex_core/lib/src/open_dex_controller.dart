import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';

import 'backend_ports.dart';
import 'wireless_coordinator.dart';

class OpenDexController implements OpenDexFacade {
  OpenDexController({
    required DeviceGateway deviceGateway,
    List<BootComponent> components = const [],
    WindowGateway? windowGateway,
    DeviceCommandGateway? deviceCommandGateway,
    PermissionGateway? permissionGateway,
    NotificationGateway? notificationGateway,
    WirelessDeviceGateway? wirelessDeviceGateway,
    ClipboardGateway? clipboardGateway,
    WirelessDiscoveryGateway? wirelessDiscoveryGateway,
    UrlLauncherGateway? urlLauncherGateway,
    int reconnectAttempts = 3,
    Duration reconnectDelay = const Duration(seconds: 1),
    Duration surfaceRetireDelay = const Duration(milliseconds: 34),
    Duration surfaceResizeDebounce = const Duration(milliseconds: 180),
    Future<void> Function(Duration) delay = _defaultDelay,
  }) : _deviceGateway = deviceGateway,
       _components = List.unmodifiable(components),
       _windowGateway = windowGateway,
       _deviceCommandGateway = deviceCommandGateway,
       _permissionGateway = permissionGateway,
       _notificationGateway = notificationGateway,
       _wirelessDeviceGateway =
           wirelessDeviceGateway ??
           (deviceGateway is WirelessDeviceGateway
               ? deviceGateway as WirelessDeviceGateway
               : null),
       _clipboardGateway = clipboardGateway,
       _urlLauncherGateway = urlLauncherGateway,
       _reconnectAttempts = reconnectAttempts,
       _reconnectDelay = reconnectDelay,
       _surfaceRetireDelay = surfaceRetireDelay,
       _surfaceResizeDebounce = surfaceResizeDebounce,
       _delay = delay {
    if (reconnectAttempts < 1) {
      throw ArgumentError.value(
        reconnectAttempts,
        'reconnectAttempts',
        'must be at least 1',
      );
    }
    final wireless = _wirelessDeviceGateway;
    if (wireless != null) {
      _wireless = WirelessCoordinator(
        gateway: wireless,
        discovery: wirelessDiscoveryGateway,
        onDiscovery: (state) =>
            _emit(_snapshot.copyWith(wirelessDiscovery: state)),
        onPairing: (state) => _emit(_snapshot.copyWith(wirelessPairing: state)),
        onConnected: _acceptWirelessDevice,
      );
    }
    _windowExits = windowGateway?.exits.listen(_handleWindowExit);
    _windowTelemetry = windowGateway?.telemetry.listen(_handleWindowTelemetry);
    if (windowGateway is WindowSurfaceUpdateGateway) {
      _windowSurfaces = (windowGateway as WindowSurfaceUpdateGateway)
          .surfaceUpdates
          .listen(_handleWindowSurface);
    }
  }

  WirelessCoordinator? _wireless;
  final DeviceGateway _deviceGateway;
  final List<BootComponent> _components;
  final WindowGateway? _windowGateway;
  final DeviceCommandGateway? _deviceCommandGateway;
  final PermissionGateway? _permissionGateway;
  final NotificationGateway? _notificationGateway;
  final WirelessDeviceGateway? _wirelessDeviceGateway;
  final ClipboardGateway? _clipboardGateway;
  final UrlLauncherGateway? _urlLauncherGateway;
  final int _reconnectAttempts;
  final Duration _reconnectDelay;
  final Duration _surfaceRetireDelay;
  final Duration _surfaceResizeDebounce;
  final Future<void> Function(Duration) _delay;
  StreamSubscription<WindowBackendExit>? _windowExits;
  StreamSubscription<WindowBackendTelemetry>? _windowTelemetry;
  StreamSubscription<WindowBackendSession>? _windowSurfaces;
  final List<StreamSubscription<BackendStateUpdate>> _backendSubscriptions = [];
  final List<StreamSubscription<void>> _disconnectSubscriptions = [];
  bool _userDisconnectRequested = false;
  final StreamController<OpenDexSnapshot> _states =
      StreamController<OpenDexSnapshot>.broadcast();
  OpenDexSnapshot _snapshot = const OpenDexSnapshot();
  bool _disposed = false;
  Future<VoidResult>? _activeReconnect;
  final Map<String, Future<VoidResult>> _surfaceShapeChanges = {};
  int _windowSequence = 0;

  @override
  OpenDexSnapshot get snapshot => _snapshot;

  @override
  Stream<OpenDexSnapshot> get states => _states.stream;

  void _emit(OpenDexSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_states.isClosed) {
      _states.add(snapshot);
    }
  }

  @override
  Future<CommandResult<List<DeviceSummary>>> discoverDevices() async {
    _emit(_snapshot.copyWith(deviceStatus: LoadStatus.loading));
    try {
      await _deviceGateway.start();
      final devices = await _deviceGateway.discoverDevices();
      _emit(
        _snapshot.copyWith(
          deviceStatus: devices.isEmpty ? LoadStatus.empty : LoadStatus.ready,
          devices: devices,
          selectedDevice:
              devices.length == 1 &&
                  devices.single.status == DeviceStatus.authorized
              ? devices.single
              : null,
        ),
      );
      return CommandSuccess(devices);
    } on BackendFailure catch (failure) {
      _emit(_snapshot.copyWith(deviceStatus: LoadStatus.error));
      return CommandFailure(failure.error);
    } on Object catch (error) {
      _emit(_snapshot.copyWith(deviceStatus: LoadStatus.error));
      return CommandFailure(_unexpected(error));
    }
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
    final device = matches.single;
    if (device.status != DeviceStatus.authorized) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.deviceUnauthorized,
          message: 'Authorize USB debugging on the Android device.',
          retryable: true,
        ),
      );
    }
    if (_snapshot.boot.isReady && _snapshot.selectedDevice?.id != device.id) {
      await disconnect();
    }
    _emit(_snapshot.copyWith(selectedDevice: device));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> connectSelectedDevice() async {
    final selected = _snapshot.selectedDevice;
    if (selected == null) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Select an authorized Android device first.',
        ),
      );
    }

    final stages = [...defaultBootStages];
    _userDisconnectRequested = false;
    final startedComponents = <BootComponent>[];
    await _clearBackendSubscriptions();
    try {
      _updateBoot(
        stages,
        'adb',
        StageStatus.active,
        BootPhase.startingAdb,
        .08,
        'Starting ADB…',
      );
      await _deviceGateway.start();
      _setStage(stages, 'adb', StageStatus.complete);

      _updateBoot(
        stages,
        'device',
        StageStatus.active,
        BootPhase.connectingDevice,
        .2,
        'Preparing ${selected.name}…',
      );
      final prepared = await _deviceGateway.prepareDevice(selected);
      _emit(_snapshot.copyWith(selectedDevice: prepared));
      _setStage(stages, 'device', StageStatus.complete);

      var progress = .2;
      for (final component in _components) {
        progress += .7 / _components.length;
        _updateBoot(
          stages,
          component.stageId,
          StageStatus.active,
          _phaseFor(component.stageId),
          progress.clamp(0, .9),
          'Starting ${_stageLabel(stages, component.stageId)}…',
        );
        if (component.stageId == 'applications') {
          _emit(_snapshot.copyWith(applicationStatus: LoadStatus.loading));
        }
        if (component.stageId == 'agent') {
          _emit(
            _snapshot.copyWith(agentStatus: AgentConnectionStatus.starting),
          );
        }
        await component.start(prepared);
        startedComponents.add(component);
        if (component is UserDisconnectProvider) {
          final provider = component as UserDisconnectProvider;
          _userDisconnectRequested |= provider.userDisconnectRequested;
          _disconnectSubscriptions.add(
            provider.userDisconnectRequests.listen((_) {
              _userDisconnectRequested = true;
              if (_snapshot.boot.isReady) unawaited(disconnect());
            }),
          );
        }
        if (_userDisconnectRequested) {
          await disconnect();
          return const CommandSuccess(null);
        }
        if (component is ApplicationCatalogProvider) {
          final applications =
              (component as ApplicationCatalogProvider).applications;
          _emit(
            _snapshot.copyWith(
              applicationStatus: applications.isEmpty
                  ? LoadStatus.empty
                  : LoadStatus.ready,
              applications: applications,
            ),
          );
        }
        if (component is BackendStateProvider) {
          final provider = component as BackendStateProvider;
          _applyBackendUpdate(provider.currentUpdate);
          _backendSubscriptions.add(
            provider.updates.listen(
              _applyBackendUpdate,
              onError: (_) {
                // Component health/recovery will own transport errors.
              },
            ),
          );
        }
        _setStage(stages, component.stageId, StageStatus.complete);
      }

      final incomplete = stages.where(
        (stage) => stage.status != StageStatus.complete,
      );
      if (incomplete.isNotEmpty) {
        throw BackendFailure(
          OpenDexError(
            code: OpenDexErrorCode.internal,
            message: 'The desktop backend is missing a boot component.',
            technicalDetails:
                'Incomplete stages: ${incomplete.map((stage) => stage.id).join(', ')}',
          ),
        );
      }

      _emit(
        _snapshot.copyWith(
          boot: BootState(
            phase: BootPhase.ready,
            progress: 1,
            message: 'Connected',
            stages: stages,
          ),
          agentStatus: AgentConnectionStatus.connected,
        ),
      );
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      await _clearBackendSubscriptions();
      await _rollback(startedComponents, _snapshot.selectedDevice ?? selected);
      _failActiveStage(stages);
      _emit(
        _snapshot.copyWith(
          boot: BootState(
            phase: BootPhase.failed,
            progress: _snapshot.boot.progress,
            message: failure.error.message,
            stages: stages,
            error: failure.error,
          ),
          agentStatus: AgentConnectionStatus.unavailable,
        ),
      );
      return CommandFailure(failure.error);
    } on Object catch (error) {
      await _clearBackendSubscriptions();
      await _rollback(startedComponents, _snapshot.selectedDevice ?? selected);
      final failure = _unexpected(error);
      _failActiveStage(stages);
      _emit(
        _snapshot.copyWith(
          boot: BootState(
            phase: BootPhase.failed,
            progress: _snapshot.boot.progress,
            message: failure.message,
            stages: stages,
            error: failure,
          ),
          agentStatus: AgentConnectionStatus.unavailable,
        ),
      );
      return CommandFailure(failure);
    }
  }

  @override
  Future<VoidResult> retryBoot() => connectSelectedDevice();

  @override
  Future<VoidResult> disconnect() async {
    final device = _snapshot.selectedDevice;
    _emit(_snapshot.copyWith(clipboard: const ClipboardState()));
    final closingWindows = [..._snapshot.windows];
    if (closingWindows.isNotEmpty) {
      _emit(
        _snapshot.copyWith(
          windows: const [],
          telemetry: _withoutFramesPerSecond(_snapshot.telemetry),
        ),
      );
      await _delay(_surfaceRetireDelay);
    }
    if (device != null) {
      await _stopRuntime(device, windows: closingWindows);
    }
    _emit(
      _snapshot.copyWith(
        boot: const BootState(),
        selectedDevice: null,
        applicationStatus: LoadStatus.idle,
        applications: const [],
        windows: const [],
        recovery: const RecoveryState(),
        agentStatus: AgentConnectionStatus.unavailable,
      ),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<CommandResult<String>> launchApplication(String packageName) async {
    final gateway = _windowGateway;
    final device = _snapshot.selectedDevice;
    if (gateway == null || device == null || !_snapshot.boot.isReady) {
      return _unsupported('application-streaming');
    }
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
    final application = matches.single;
    final sessionId =
        'window-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_windowSequence}';
    final cascade = _snapshot.windows.length % 6;
    final topZ = _snapshot.windows.fold<int>(
      -1,
      (highest, window) => window.zOrder > highest ? window.zOrder : highest,
    );
    final startingWindow = WindowSessionState(
      id: sessionId,
      application: application,
      status: WindowSessionStatus.starting,
      isFocused: true,
      geometry: WindowGeometry(
        x: 64 + cascade * 28,
        y: 64 + cascade * 28,
        width: 640,
        height: 480,
      ),
      zOrder: topZ + 1,
    );
    _emit(
      _snapshot.copyWith(
        windows: [
          for (final window in _snapshot.windows)
            _copyWindow(window, isFocused: false),
          startingWindow,
        ],
      ),
    );
    try {
      final launched = await gateway.launch(
        device,
        application,
        sessionId: sessionId,
      );
      final current = _window(sessionId);
      if (current == null) {
        await gateway.close(launched.id);
        return CommandSuccess(launched.id);
      }
      final windows = [
        for (final window in _snapshot.windows)
          if (window.id == sessionId)
            WindowSessionState(
              id: launched.id,
              application: application,
              status: WindowSessionStatus.streaming,
              displayId: launched.displayId,
              isFocused: current.isFocused,
              geometry:
                  current.geometry == startingWindow.geometry &&
                      launched.surface != null &&
                      launched.surface!.pixelSize.height >
                          launched.surface!.pixelSize.width
                  ? WindowGeometry(
                      x: current.geometry.x,
                      y: current.geometry.y,
                      width: 360,
                      height: 674,
                    )
                  : current.geometry,
              displayState: current.displayState,
              zOrder: current.zOrder,
              surface: launched.surface,
            )
          else
            window,
      ];
      _emit(_snapshot.copyWith(windows: windows));
      await _synchronizeSurfaceShape(launched.id);
      return CommandSuccess(launched.id);
    } on BackendFailure catch (failure) {
      _removeStartingWindow(sessionId);
      return CommandFailure(failure.error);
    } on Object catch (error) {
      _removeStartingWindow(sessionId);
      return CommandFailure(_unexpected(error));
    }
  }

  void _removeStartingWindow(String sessionId) {
    if (!_snapshot.windows.any((window) => window.id == sessionId)) return;
    _emit(
      _snapshot.copyWith(
        windows: _snapshot.windows
            .where((window) => window.id != sessionId)
            .toList(),
      ),
    );
  }

  @override
  Future<VoidResult> closeWindow(String sessionId) async {
    final gateway = _windowGateway;
    if (gateway == null ||
        !_snapshot.windows.any((window) => window.id == sessionId)) {
      return _unsupported('application-streaming');
    }
    try {
      final closing = _snapshot.windows.singleWhere(
        (window) => window.id == sessionId,
      );
      _emit(
        _snapshot.copyWith(
          windows: _snapshot.windows
              .where((window) => window.id != sessionId)
              .toList(),
          telemetry: closing.isFocused
              ? _withoutFramesPerSecond(_snapshot.telemetry)
              : _snapshot.telemetry,
        ),
      );
      await _delay(_surfaceRetireDelay);
      await gateway.close(sessionId);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> focusWindow(String sessionId) async {
    final target = _window(sessionId);
    if (target == null) return _missingWindow();
    if (target.displayState == WindowDisplayState.minimised) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'Restore the application window before focusing it.',
          capability: 'window-management',
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
    if (_window(sessionId) == null) return _missingWindow();
    if (!_validGeometry(geometry)) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'The application window size or position is invalid.',
          capability: 'window-management',
        ),
      );
    }
    _replaceWindow(
      sessionId,
      (window) => _copyWindow(window, geometry: geometry),
    );
    return _synchronizeSurfaceShape(sessionId);
  }

  Future<VoidResult> _synchronizeSurfaceShape(String sessionId) async {
    final windowGateway = _windowGateway;
    if (windowGateway is! ResizableWindowGateway) {
      return const CommandSuccess(null);
    }
    final gateway = windowGateway as ResizableWindowGateway;
    final active = _surfaceShapeChanges[sessionId];
    if (active != null) return active;
    final synchronization = _resizeSurfaceUntilCurrent(sessionId, gateway);
    _surfaceShapeChanges[sessionId] = synchronization;
    try {
      return await synchronization;
    } finally {
      if (identical(_surfaceShapeChanges[sessionId], synchronization)) {
        _surfaceShapeChanges.remove(sessionId);
      }
    }
  }

  Future<VoidResult> _resizeSurfaceUntilCurrent(
    String sessionId,
    ResizableWindowGateway gateway,
  ) async {
    while (true) {
      await _delay(_surfaceResizeDebounce);
      final window = _window(sessionId);
      if (window == null || window.surface == null) {
        return const CommandSuccess(null);
      }
      final desired = _pixelSizeForGeometry(window.geometry, window.surface!);
      final current = window.surface!.pixelSize;
      if (desired.width == current.width && desired.height == current.height) {
        return const CommandSuccess(null);
      }
      try {
        final resized = await gateway.resizeSurface(sessionId, desired);
        final latest = _window(sessionId);
        if (latest == null) {
          try {
            await _windowGateway?.close(sessionId);
          } on Object {
            // A concurrent close already owns cleanup for this session.
          }
          return const CommandSuccess(null);
        }
        _replaceWindow(
          sessionId,
          (source) => _copyWindow(
            source,
            displayId: resized.displayId,
            surface: resized.surface,
          ),
        );
      } on BackendFailure catch (failure) {
        if (_window(sessionId) == null) return const CommandSuccess(null);
        return CommandFailure(failure.error);
      } on Object catch (error) {
        if (_window(sessionId) == null) return const CommandSuccess(null);
        return CommandFailure(_unexpected(error));
      }
    }
  }

  @override
  Future<VoidResult> setWindowDisplayState(
    String sessionId,
    WindowDisplayState state,
  ) async {
    final target = _window(sessionId);
    if (target == null) return _missingWindow();
    final minimised = state == WindowDisplayState.minimised;
    var windows = [
      for (final window in _snapshot.windows)
        window.id == sessionId
            ? _copyWindow(
                window,
                displayState: state,
                isFocused: minimised ? false : window.isFocused,
              )
            : window,
    ];
    if (minimised && target.isFocused) {
      final candidates =
          windows
              .where(
                (window) =>
                    window.displayState != WindowDisplayState.minimised &&
                    window.id != sessionId,
              )
              .toList()
            ..sort((a, b) => b.zOrder.compareTo(a.zOrder));
      if (candidates.isNotEmpty) {
        final nextId = candidates.first.id;
        windows = [
          for (final window in windows)
            _copyWindow(window, isFocused: window.id == nextId),
        ];
      }
    }
    _emit(_snapshot.copyWith(windows: windows));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> raiseWindow(String sessionId) async {
    if (_window(sessionId) == null) return _missingWindow();
    final topZ = _snapshot.windows.fold<int>(
      -1,
      (highest, window) => window.zOrder > highest ? window.zOrder : highest,
    );
    _replaceWindow(
      sessionId,
      (window) => _copyWindow(window, zOrder: topZ + 1),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> selectWorkspace(int workspace) async {
    if (!isValidWorkspace(workspace)) return _invalidWorkspace();
    _emit(_snapshot.copyWith(currentWorkspace: workspace));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> moveWindowToWorkspace(
    String sessionId,
    int workspace,
  ) async {
    if (!isValidWorkspace(workspace)) return _invalidWorkspace();
    if (_window(sessionId) == null) return _missingWindow();
    _replaceWindow(
      sessionId,
      (window) => window.copyWith(workspace: workspace),
    );
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> setWindowScale(String sessionId, double scale) async {
    if (!isValidWindowScale(scale)) return _invalidWindowScale();
    if (_window(sessionId) == null) return _missingWindow();
    _replaceWindow(sessionId, (window) => window.copyWith(scale: scale));
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> setWindowOrientation(
    String sessionId, {
    required bool landscape,
  }) async {
    final window = _window(sessionId);
    if (window == null) return _missingWindow();
    if (window.isLandscape == landscape) return const CommandSuccess(null);
    // Swap the aspect rather than resize to a remembered box, so rotating back
    // lands exactly where it started without storing anything.
    final rotated = WindowGeometry(
      x: window.geometry.x,
      y: window.geometry.y,
      width: window.geometry.height,
      height: window.geometry.width,
    );
    _replaceWindow(
      sessionId,
      (w) => w.copyWith(isLandscape: landscape, geometry: rotated),
    );
    return moveWindow(sessionId, rotated);
  }

  @override
  Future<VoidResult> openUrl(String url) async {
    if (!isWebUrl(url)) return _invalidUrl();
    final gateway = _urlLauncherGateway;
    if (gateway == null) return _unsupported('url-launcher');
    try {
      await gateway.open(Uri.parse(url));
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    }
    return const CommandSuccess(null);
  }

  static CommandFailure<void> _invalidWorkspace() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That workspace does not exist.',
      capability: 'window-management',
    ),
  );

  static CommandFailure<void> _invalidWindowScale() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That zoom level is outside the range a window can be drawn at.',
      capability: 'window-management',
    ),
  );

  static CommandFailure<void> _invalidUrl() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That is not a web address the desk can open.',
      capability: 'url-launcher',
    ),
  );

  @override
  Future<VoidResult> sendPointer(
    String sessionId,
    WindowPointerSample sample,
  ) async {
    final gateway = _windowGateway;
    final window = _window(sessionId);
    if (window == null) return _missingWindow();
    if (gateway == null || window.surface == null) {
      return _unsupported('embedded-window-input');
    }
    // Malformed samples — non-finite coordinates or a negative pointer id — are
    // never produced by a real gesture, so surfacing them helps catch a bug.
    if (!sample.x.isFinite ||
        !sample.y.isFinite ||
        !sample.scrollDeltaX.isFinite ||
        !sample.scrollDeltaY.isFinite ||
        sample.pointerId < 0) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'The pointer sample is malformed.',
          capability: 'embedded-window-input',
        ),
      );
    }
    // A pointer outside the phone's surface is ordinary: the cursor moved off
    // the mirrored screen, or a drag ran past its edge. Drop it silently — it
    // used to surface as "The pointer sample is outside the Android surface",
    // a warning that flashed under the window on nearly every mouse move.
    if (sample.x < 0 ||
        sample.y < 0 ||
        sample.x > window.surface!.pixelSize.width ||
        sample.y > window.surface!.pixelSize.height) {
      return const CommandSuccess(null);
    }
    try {
      await gateway.sendPointer(sessionId, sample);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> sendKey(String sessionId, WindowKeySample sample) async {
    final gateway = _windowGateway;
    final window = _window(sessionId);
    if (window == null) return _missingWindow();
    if (gateway == null || window.surface == null) {
      return _unsupported('embedded-window-input');
    }
    if (sample.physicalKeyId < 0 || sample.logicalKeyId < 0) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'The keyboard sample is invalid.',
          capability: 'embedded-window-input',
        ),
      );
    }
    try {
      await gateway.sendKey(sessionId, sample);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> sendNavKey(String sessionId, AndroidNavKey key) async {
    final gateway = _windowGateway;
    final window = _window(sessionId);
    if (window == null) return _missingWindow();
    if (gateway is! NavKeyWindowGateway || window.surface == null) {
      return _unsupported('embedded-window-input');
    }
    try {
      await (gateway as NavKeyWindowGateway).sendNavKey(sessionId, key);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> setClipboardText(String text) async {
    final gateway = _clipboardGateway;
    if (gateway == null ||
        !_snapshot.boot.isReady ||
        _snapshot.agentStatus != AgentConnectionStatus.connected ||
        !_snapshot.clipboard.syncEnabled ||
        _snapshot.clipboard.availability != ClipboardAvailability.available) {
      return _unsupported('clipboard');
    }
    if (text.length > 65536) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'Clipboard text must be 64 KiB or smaller.',
          capability: 'clipboard',
        ),
      );
    }
    try {
      await gateway.writeText(text);
      _emit(_snapshot.copyWith(clipboard: gateway.clipboard));
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> setClipboardSync(bool enabled) async {
    final gateway = _clipboardGateway;
    if (gateway == null) return _unsupported('clipboard');
    if (enabled &&
        (!_snapshot.boot.isReady ||
            _snapshot.agentStatus != AgentConnectionStatus.connected)) {
      return _unsupported('clipboard');
    }
    try {
      gateway.setSyncEnabled(enabled);
      _emit(_snapshot.copyWith(clipboard: gateway.clipboard));
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> pauseClipboardSync() async {
    final result = await setClipboardSync(false);
    if (_snapshot.boot.isReady &&
        _snapshot.clipboard.availability == ClipboardAvailability.available) {
      _emit(
        _snapshot.copyWith(
          clipboard: const ClipboardState(
            availability: ClipboardAvailability.available,
            message: ClipboardState.desktopFailureMessage,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<VoidResult> setVolume(String stream, int value) async {
    final gateway = _deviceCommandGateway;
    if (gateway == null) return _unsupported('volume');
    try {
      await gateway.setVolume(stream, value);
      final current = _snapshot.telemetry.volume[stream];
      if (current != null) {
        _emit(
          _snapshot.copyWith(
            telemetry: _copyTelemetry(
              _snapshot.telemetry,
              volume: {
                ..._snapshot.telemetry.volume,
                stream: VolumeLevel(current: value, maximum: current.maximum),
              },
            ),
          ),
        );
      }
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> sendMediaAction(MediaAction action) async {
    final gateway = _deviceCommandGateway;
    if (gateway == null) return _unsupported('media');
    try {
      await gateway.sendMediaAction(action);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
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
    final gateway = _deviceCommandGateway;
    if (gateway == null) return _unsupported('device-controls');
    try {
      await gateway.setDeviceControl(control, enabled);
      final telemetry = _snapshot.telemetry;
      _emit(
        _snapshot.copyWith(
          agentStatus: AgentConnectionStatus.connected,
          telemetry: _copyTelemetry(
            telemetry,
            wifiEnabled: control == DeviceControl.wifi
                ? enabled
                : telemetry.wifiEnabled,
            bluetoothEnabled: control == DeviceControl.bluetooth
                ? enabled
                : telemetry.bluetoothEnabled,
            rotationLocked: control == DeviceControl.rotationLock
                ? enabled
                : telemetry.rotationLocked,
            airplaneMode: control == DeviceControl.airplaneMode
                ? enabled
                : telemetry.airplaneMode,
            mobileDataEnabled: control == DeviceControl.mobileData
                ? enabled
                : telemetry.mobileDataEnabled,
            locationEnabled: control == DeviceControl.location
                ? enabled
                : telemetry.locationEnabled,
          ),
        ),
      );
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      if (failure.error.code == OpenDexErrorCode.connectionFailed ||
          failure.error.code == OpenDexErrorCode.timeout) {
        _emit(
          _snapshot.copyWith(agentStatus: AgentConnectionStatus.reconnecting),
        );
        unawaited(reconnect());
      }
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> openPermissionSettings(String capability) async {
    final gateway = _permissionGateway;
    if (gateway == null || !_snapshot.boot.isReady) {
      return _unsupported('permission-settings');
    }
    try {
      await gateway.openSettings(capability);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> dismissNotification(String notificationId) async {
    final gateway = _notificationGateway;
    if (gateway == null || !_snapshot.boot.isReady) {
      return _unsupported('notification-actions');
    }
    if (!_snapshot.notifications.any((item) => item.id == notificationId)) {
      return _missingNotification();
    }
    try {
      await gateway.dismiss(notificationId);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> activateNotification(String notificationId) async {
    final gateway = _notificationGateway;
    if (gateway == null || !_snapshot.boot.isReady) {
      return _unsupported('notification-actions');
    }
    final matches = _snapshot.notifications.where(
      (item) => item.id == notificationId,
    );
    if (matches.isEmpty) return _missingNotification();
    final notification = matches.single;

    WindowSessionState? target;
    final existing = _snapshot.windows.where(
      (window) =>
          window.application.packageName == notification.packageName &&
          window.status == WindowSessionStatus.streaming,
    );
    if (existing.isNotEmpty) {
      target = existing.reduce(
        (front, candidate) =>
            candidate.zOrder > front.zOrder ? candidate : front,
      );
      if (target.displayState == WindowDisplayState.minimised) {
        await setWindowDisplayState(target.id, WindowDisplayState.normal);
      }
      await raiseWindow(target.id);
      await focusWindow(target.id);
    } else {
      final applications = _snapshot.applications.where(
        (application) => application.packageName == notification.packageName,
      );
      if (applications.isNotEmpty) {
        final launched = await launchApplication(notification.packageName);
        if (launched case CommandFailure<String>(:final error)) {
          return CommandFailure(error);
        }
        final sessionId = (launched as CommandSuccess<String>).value;
        target = _window(sessionId);
      }
    }

    try {
      await gateway.activate(notificationId, displayId: target?.displayId);
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> dismissAllNotifications() async {
    final gateway = _notificationGateway;
    if (gateway == null || !_snapshot.boot.isReady) {
      return _unsupported('notification-actions');
    }
    try {
      await gateway.dismissAll();
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  @override
  Future<VoidResult> reconnect() {
    final active = _activeReconnect;
    if (active != null) return active;
    late final Future<VoidResult> operation;
    operation = _performReconnect().whenComplete(() {
      if (identical(_activeReconnect, operation)) _activeReconnect = null;
    });
    _activeReconnect = operation;
    return operation;
  }

  @override
  Future<VoidResult> startWirelessDiscovery() async =>
      await _wireless?.start() ?? _unsupported('wireless-discovery');
  @override
  Future<VoidResult> stopWirelessDiscovery() async =>
      await _wireless?.stop() ?? const CommandSuccess(null);
  @override
  Future<VoidResult> startQrPairing() async =>
      await _wireless?.startQr() ?? _unsupported('wireless-pairing');
  @override
  Future<VoidResult> cancelWirelessPairing() async =>
      await _wireless?.cancel() ?? const CommandSuccess(null);

  @override
  Future<VoidResult> pairWirelessDevice({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) async =>
      await _wireless?.pairManual(
        host: host,
        port: pairingPort,
        code: pairingCode,
      ) ??
      _unsupported('wireless-pairing');

  @override
  Future<CommandResult<DeviceSummary>> connectWirelessDevice({
    required String host,
    required int port,
  }) async =>
      await _wireless?.connect(host: host, port: port) ??
      const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'Wireless connections are unavailable.',
        ),
      );

  void _acceptWirelessDevice(DeviceSummary device) {
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
  }

  @override
  Future<VoidResult> forgetWirelessDevice(String deviceId) async {
    final gateway = _wirelessDeviceGateway;
    if (gateway == null) return _unsupported('wireless-connection');
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
    try {
      final wasSelected = _snapshot.selectedDevice?.id == deviceId;
      if (wasSelected) await disconnect();
      await gateway.forget(deviceId);
      _emit(
        _snapshot.copyWith(
          devices: _snapshot.devices
              .where((device) => device.id != deviceId)
              .toList(),
          selectedDevice: wasSelected ? null : _snapshot.selectedDevice,
        ),
      );
      return const CommandSuccess(null);
    } on BackendFailure catch (failure) {
      return CommandFailure(failure.error);
    } on Object catch (error) {
      return CommandFailure(_unexpected(error));
    }
  }

  Future<VoidResult> _performReconnect() async {
    _emit(_snapshot.copyWith(clipboard: const ClipboardState()));
    final previousDevice = _snapshot.selectedDevice;
    if (previousDevice == null) {
      const error = OpenDexError(
        code: OpenDexErrorCode.connectionFailed,
        message: 'Select an authorized Android device before reconnecting.',
        retryable: true,
      );
      _emit(
        _snapshot.copyWith(
          recovery: const RecoveryState(
            phase: RecoveryPhase.failed,
            message: 'No Android device is selected.',
            error: error,
          ),
        ),
      );
      return const CommandFailure(error);
    }

    _emit(
      _snapshot.copyWith(
        agentStatus: AgentConnectionStatus.reconnecting,
        windows: [
          for (final window in _snapshot.windows)
            _copyWindow(window, status: WindowSessionStatus.reconnecting),
        ],
        recovery: const RecoveryState(
          phase: RecoveryPhase.detecting,
          message: 'Checking the Android connection…',
        ),
      ),
    );
    final closingWindows = [..._snapshot.windows];
    _emit(
      _snapshot.copyWith(
        windows: const [],
        telemetry: _withoutFramesPerSecond(_snapshot.telemetry),
      ),
    );
    if (closingWindows.isNotEmpty) await _delay(_surfaceRetireDelay);
    await _stopRuntime(previousDevice, windows: closingWindows);

    OpenDexError lastError = const OpenDexError(
      code: OpenDexErrorCode.deviceOffline,
      message: 'The Android device is not available.',
      retryable: true,
    );
    for (var attempt = 1; attempt <= _reconnectAttempts; attempt++) {
      if (attempt > 1) await _delay(_reconnectDelay);
      _emit(
        _snapshot.copyWith(
          recovery: RecoveryState(
            phase: RecoveryPhase.reconnecting,
            attempt: attempt,
            message: 'Reconnecting to ${previousDevice.name}…',
          ),
        ),
      );

      try {
        await _deviceGateway.start();
        final devices = await _deviceGateway.discoverDevices();
        final matches = devices.where(
          (device) => device.id == previousDevice.id,
        );
        if (matches.isEmpty) {
          lastError = const OpenDexError(
            code: OpenDexErrorCode.deviceOffline,
            message:
                'Reconnect the Android device and keep USB debugging enabled.',
            retryable: true,
          );
          _emit(
            _snapshot.copyWith(
              deviceStatus: devices.isEmpty
                  ? LoadStatus.empty
                  : LoadStatus.ready,
              devices: devices,
            ),
          );
          continue;
        }
        final device = matches.single;
        if (device.status != DeviceStatus.authorized) {
          lastError = const OpenDexError(
            code: OpenDexErrorCode.deviceUnauthorized,
            message: 'Authorize USB debugging on the Android device.',
            retryable: true,
          );
          _emit(
            _snapshot.copyWith(
              deviceStatus: LoadStatus.ready,
              devices: devices,
              selectedDevice: device,
            ),
          );
          continue;
        }

        _emit(
          _snapshot.copyWith(
            deviceStatus: LoadStatus.ready,
            devices: devices,
            selectedDevice: device,
            recovery: RecoveryState(
              phase: RecoveryPhase.restartingServices,
              attempt: attempt,
              message: 'Restarting Android services…',
            ),
          ),
        );
        final result = await connectSelectedDevice();
        if (result case CommandSuccess<void>()) {
          _emit(
            _snapshot.copyWith(
              agentStatus: AgentConnectionStatus.connected,
              recovery: RecoveryState(
                phase: RecoveryPhase.recovered,
                attempt: attempt,
                message: 'Connection restored',
              ),
            ),
          );
          return const CommandSuccess(null);
        }
        lastError = (result as CommandFailure<void>).error;
      } on BackendFailure catch (failure) {
        lastError = failure.error;
      } on Object catch (error) {
        lastError = _unexpected(error);
      }
    }

    _emit(
      _snapshot.copyWith(
        agentStatus: AgentConnectionStatus.unavailable,
        recovery: RecoveryState(
          phase: RecoveryPhase.failed,
          attempt: _reconnectAttempts,
          message: 'Could not restore the Android connection.',
          error: lastError,
        ),
      ),
    );
    return CommandFailure(lastError);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _wireless?.stop();
    await disconnect();
    await _windowExits?.cancel();
    await _windowTelemetry?.cancel();
    await _windowSurfaces?.cancel();
    await _windowGateway?.dispose();
    await _states.close();
  }

  void _handleWindowExit(WindowBackendExit exit) {
    final index = _snapshot.windows.indexWhere(
      (window) => window.id == exit.sessionId,
    );
    if (index < 0) return;
    final old = _snapshot.windows[index];
    final telemetry = old.isFocused
        ? _withoutFramesPerSecond(_snapshot.telemetry)
        : _snapshot.telemetry;
    if (exit.exitCode == 0) {
      _emit(
        _snapshot.copyWith(
          windows: _snapshot.windows
              .where((window) => window.id != exit.sessionId)
              .toList(),
          telemetry: telemetry,
        ),
      );
      return;
    }
    final windows = [..._snapshot.windows];
    windows[index] = _copyWindow(
      old,
      status: WindowSessionStatus.failed,
      error: OpenDexError(
        code: OpenDexErrorCode.connectionFailed,
        message: '${old.application.label} stopped unexpectedly.',
        retryable: true,
        technicalDetails:
            exit.details ?? 'window backend exit code ${exit.exitCode}',
      ),
    );
    _emit(_snapshot.copyWith(windows: windows, telemetry: telemetry));
  }

  void _handleWindowTelemetry(WindowBackendTelemetry update) {
    final window = _window(update.sessionId);
    if (window == null) return;
    final displayRate =
        update.presentedFramesPerSecond ??
        window.presentedFramesPerSecond ??
        update.producedFramesPerSecond;
    final windows = [
      for (final candidate in _snapshot.windows)
        candidate.id == update.sessionId
            ? _copyWindow(
                candidate,
                producedFramesPerSecond: update.producedFramesPerSecond,
                presentedFramesPerSecond: update.presentedFramesPerSecond,
                droppedFramesPerSecond: update.droppedFramesPerSecond,
              )
            : candidate,
    ];
    if (!window.isFocused) {
      _emit(_snapshot.copyWith(windows: windows));
      return;
    }
    final old = _snapshot.telemetry;
    _emit(
      _snapshot.copyWith(
        windows: windows,
        telemetry: DeviceTelemetry(
          batteryPercentage: old.batteryPercentage,
          charging: old.charging,
          wifiEnabled: old.wifiEnabled,
          bluetoothEnabled: old.bluetoothEnabled,
          airplaneMode: old.airplaneMode,
          rotationLocked: old.rotationLocked,
          torchEnabled: old.torchEnabled,
          volume: old.volume,
          linkLatency: old.linkLatency,
          throughput: old.throughput,
          framesPerSecond: displayRate == null
              ? old.framesPerSecond
              : TelemetryMeasurement(
                  value: displayRate,
                  unit: TelemetryUnit.framesPerSecond,
                ),
        ),
      ),
    );
  }

  void _handleWindowSurface(WindowBackendSession update) {
    if (_window(update.id) == null || update.surface == null) return;
    _replaceWindow(
      update.id,
      (window) => _copyWindow(
        window,
        displayId: update.displayId,
        surface: update.surface,
      ),
    );
  }

  void _applyBackendUpdate(BackendStateUpdate update) {
    final incomingTelemetry = update.telemetry;
    _emit(
      _snapshot.copyWith(
        telemetry: incomingTelemetry == null
            ? null
            : _withFramesPerSecond(
                incomingTelemetry,
                incomingTelemetry.framesPerSecond ??
                    _snapshot.telemetry.framesPerSecond,
              ),
        clipboard: update.clipboard,
        permissions: update.permissions,
        notificationStatus: update.notificationStatus,
        notifications: update.notifications,
        media: update.media,
      ),
    );
  }

  Future<void> _clearBackendSubscriptions() async {
    for (final subscription in _disconnectSubscriptions) {
      await subscription.cancel();
    }
    _disconnectSubscriptions.clear();
    for (final subscription in _backendSubscriptions) {
      await subscription.cancel();
    }
    _backendSubscriptions.clear();
  }

  Future<void> _stopRuntime(
    DeviceSummary device, {
    List<WindowSessionState>? windows,
  }) async {
    await _clearBackendSubscriptions();
    final gateway = _windowGateway;
    if (gateway != null) {
      for (final window in windows ?? [..._snapshot.windows]) {
        try {
          await gateway.close(window.id);
        } on Object {
          // Continue cleanup if a native window already exited.
        }
      }
    }
    for (final component in _components.reversed) {
      try {
        await component.stop(device);
      } on Object {
        // Best-effort cleanup prevents one component stranding the others.
      }
    }
    try {
      await _deviceGateway.disconnectDevice(device);
    } on Object {
      // A disconnected cable is already the intended runtime state.
    }
  }

  static WindowSessionState _copyWindow(
    WindowSessionState source, {
    WindowSessionStatus? status,
    int? displayId,
    bool? isFocused,
    WindowGeometry? geometry,
    WindowDisplayState? displayState,
    int? zOrder,
    WindowSurface? surface,
    double? producedFramesPerSecond,
    double? presentedFramesPerSecond,
    double? droppedFramesPerSecond,
    OpenDexError? error,
  }) => source.copyWith(
    status: status,
    displayId: displayId,
    isFocused: isFocused,
    geometry: geometry,
    displayState: displayState,
    zOrder: zOrder,
    surface: surface,
    producedFramesPerSecond: producedFramesPerSecond,
    presentedFramesPerSecond: presentedFramesPerSecond,
    droppedFramesPerSecond: droppedFramesPerSecond,
    error: error,
  );

  WindowSessionState? _window(String sessionId) {
    for (final window in _snapshot.windows) {
      if (window.id == sessionId) return window;
    }
    return null;
  }

  void _replaceWindow(
    String sessionId,
    WindowSessionState Function(WindowSessionState window) replace,
  ) {
    _emit(
      _snapshot.copyWith(
        windows: [
          for (final window in _snapshot.windows)
            window.id == sessionId ? replace(window) : window,
        ],
      ),
    );
  }

  static bool _validGeometry(WindowGeometry geometry) =>
      geometry.x.isFinite &&
      geometry.y.isFinite &&
      geometry.width.isFinite &&
      geometry.height.isFinite &&
      geometry.width >= WindowGeometry.minimumWidth &&
      geometry.height >= WindowGeometry.minimumHeight;

  static WindowPixelSize _pixelSizeForGeometry(
    WindowGeometry geometry,
    WindowSurface surface,
  ) {
    final contentHeight = (geometry.height - _windowChromeHeight).clamp(
      1.0,
      double.infinity,
    );
    final aspectRatio = geometry.width / contentHeight;
    final desired = aspectRatio >= 1
        ? WindowPixelSize(
            width: _surfaceLongEdge,
            height: _quantizedSurfaceEdge(_surfaceLongEdge / aspectRatio),
          )
        : WindowPixelSize(
            width: _quantizedSurfaceEdge(_surfaceLongEdge * aspectRatio),
            height: _surfaceLongEdge,
          );
    final current = surface.pixelSize;
    return desired.width == current.width && desired.height == current.height
        ? current
        : desired;
  }

  static int _quantizedSurfaceEdge(double value) {
    final clamped = value.clamp(_surfaceShortEdge, _surfaceLongEdge).round();
    return ((clamped + _surfaceQuantum ~/ 2) ~/ _surfaceQuantum) *
        _surfaceQuantum;
  }

  static const _windowChromeHeight = 34.0;
  static const _surfaceLongEdge = 1280;
  static const _surfaceShortEdge = 384;
  static const _surfaceQuantum = 16;

  static CommandFailure<void> _missingWindow() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That application window has closed.',
      capability: 'window-management',
    ),
  );

  static CommandFailure<void> _missingNotification() => const CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'That notification is no longer available.',
      capability: 'notification-actions',
    ),
  );

  static DeviceTelemetry _withoutFramesPerSecond(DeviceTelemetry source) =>
      _withFramesPerSecond(source, null);

  static DeviceTelemetry _withFramesPerSecond(
    DeviceTelemetry source,
    TelemetryMeasurement? framesPerSecond,
  ) => DeviceTelemetry(
    batteryPercentage: source.batteryPercentage,
    charging: source.charging,
    wifiEnabled: source.wifiEnabled,
    bluetoothEnabled: source.bluetoothEnabled,
    airplaneMode: source.airplaneMode,
    rotationLocked: source.rotationLocked,
    torchEnabled: source.torchEnabled,
    volume: source.volume,
    linkLatency: source.linkLatency,
    throughput: source.throughput,
    framesPerSecond: framesPerSecond,
  );

  static DeviceTelemetry _copyTelemetry(
    DeviceTelemetry source, {
    bool? wifiEnabled,
    bool? bluetoothEnabled,
    bool? rotationLocked,
    bool? airplaneMode,
    bool? mobileDataEnabled,
    bool? locationEnabled,
    Map<String, VolumeLevel>? volume,
  }) => DeviceTelemetry(
    batteryPercentage: source.batteryPercentage,
    charging: source.charging,
    wifiEnabled: wifiEnabled ?? source.wifiEnabled,
    bluetoothEnabled: bluetoothEnabled ?? source.bluetoothEnabled,
    airplaneMode: airplaneMode ?? source.airplaneMode,
    rotationLocked: rotationLocked ?? source.rotationLocked,
    torchEnabled: source.torchEnabled,
    mobileDataEnabled: mobileDataEnabled ?? source.mobileDataEnabled,
    locationEnabled: locationEnabled ?? source.locationEnabled,
    volume: volume ?? source.volume,
    linkLatency: source.linkLatency,
    throughput: source.throughput,
    framesPerSecond: source.framesPerSecond,
  );

  void _updateBoot(
    List<BootStage> stages,
    String stageId,
    StageStatus stageStatus,
    BootPhase phase,
    double progress,
    String message,
  ) {
    _setStage(stages, stageId, stageStatus);
    _emit(
      _snapshot.copyWith(
        boot: BootState(
          phase: phase,
          progress: progress,
          message: message,
          stages: List.unmodifiable(stages),
        ),
      ),
    );
  }

  static void _setStage(List<BootStage> stages, String id, StageStatus status) {
    final index = stages.indexWhere((stage) => stage.id == id);
    if (index < 0) return;
    final old = stages[index];
    stages[index] = BootStage(
      id: old.id,
      label: old.label,
      status: status,
      detail: old.detail,
    );
  }

  static void _failActiveStage(List<BootStage> stages) {
    final index = stages.indexWhere(
      (stage) => stage.status == StageStatus.active,
    );
    if (index >= 0) {
      _setStage(stages, stages[index].id, StageStatus.failed);
    }
  }

  static Future<void> _rollback(
    List<BootComponent> components,
    DeviceSummary device,
  ) async {
    for (final component in components.reversed) {
      try {
        await component.stop(device);
      } on Object {
        // Preserve the original boot failure while completing best-effort cleanup.
      }
    }
  }

  static String _stageLabel(List<BootStage> stages, String id) => stages
      .firstWhere(
        (stage) => stage.id == id,
        orElse: () => BootStage(id: id, label: id),
      )
      .label;

  static BootPhase _phaseFor(String stageId) => switch (stageId) {
    'agent' => BootPhase.deployingAgent,
    'companion' => BootPhase.installingCompanion,
    'applications' => BootPhase.loadingApplications,
    _ => BootPhase.awaitingHandshakes,
  };

  static CommandFailure<T> _unsupported<T>(String capability) => CommandFailure(
    OpenDexError(
      code: OpenDexErrorCode.capabilityUnavailable,
      message: 'This capability is not ready yet.',
      capability: capability,
    ),
  );

  static OpenDexError _unexpected(Object error) => OpenDexError(
    code: OpenDexErrorCode.internal,
    message: 'DroidPier could not complete the operation.',
    retryable: true,
    technicalDetails: error.toString(),
  );
}

Future<void> _defaultDelay(Duration duration) => Future<void>.delayed(duration);
