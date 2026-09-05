import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'companion user disconnect tears down the session without recovery',
    () async {
      final device = FakeDeviceGateway();
      final companion = DisconnectingCompanion();
      final controller = OpenDexController(
        deviceGateway: device,
        components: [
          FakeBootComponent('agent'),
          companion,
          FakeBootComponent('applications'),
        ],
      );
      addTearDown(controller.dispose);
      addTearDown(companion.requests.close);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      expect(controller.snapshot.boot.isReady, isTrue);
      final disconnected = controller.states.firstWhere(
        (state) =>
            state.boot.phase == BootPhase.idle && state.selectedDevice == null,
      );
      companion.requests.add(null);
      await disconnected.timeout(const Duration(seconds: 2));
      expect(device.disconnectCount, 1);
      expect(companion.startCount, 1);
      expect(companion.stopCount, 1);
      expect(controller.snapshot.windows, isEmpty);
      expect(controller.snapshot.recovery, isA<RecoveryState>());
    },
  );

  test(
    'disconnect requested during companion startup never publishes ready',
    () async {
      final companion = DisconnectingCompanion(requestOnStart: true);
      final apps = FakeBootComponent('applications');
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [FakeBootComponent('agent'), companion, apps],
      );
      addTearDown(controller.dispose);
      addTearDown(companion.requests.close);
      await controller.discoverDevices();
      final states = <OpenDexSnapshot>[];
      final subscription = controller.states.listen(states.add);
      addTearDown(subscription.cancel);
      await controller.connectSelectedDevice();
      expect(controller.snapshot.selectedDevice, isNull);
      expect(controller.snapshot.boot.phase, BootPhase.idle);
      expect(states.any((state) => state.boot.isReady), isFalse);
      expect(apps.startCount, 0);
    },
  );

  test('discovers and auto-selects one authorized device', () async {
    final gateway = FakeDeviceGateway();
    final controller = OpenDexController(deviceGateway: gateway);
    addTearDown(controller.dispose);

    final result = await controller.discoverDevices();

    expect(result, isA<CommandSuccess<List<DeviceSummary>>>());
    expect(controller.snapshot.selectedDevice?.id, 'device-1');
    expect(gateway.started, isTrue);
  });

  test('publishes ordered boot stages while components start', () async {
    final gateway = FakeDeviceGateway();
    final components = [
      FakeBootComponent('agent'),
      FakeBootComponent('companion'),
      FakeBootComponent('applications'),
    ];
    final controller = OpenDexController(
      deviceGateway: gateway,
      components: components,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();

    final states = <OpenDexSnapshot>[];
    final subscription = controller.states.listen(states.add);
    addTearDown(subscription.cancel);
    final result = await controller.connectSelectedDevice();

    expect(result.isSuccess, isTrue);
    expect(controller.snapshot.boot.phase, BootPhase.ready);
    expect(
      controller.snapshot.boot.stages.map((stage) => stage.status),
      everyElement(StageStatus.complete),
    );
    expect(
      states
          .expand((state) => state.boot.stages)
          .any(
            (stage) =>
                stage.id == 'agent' && stage.status == StageStatus.active,
          ),
      isTrue,
    );
  });

  test('marks the active stage failed with a safe backend error', () async {
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [FailingBootComponent('agent')],
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();

    final result = await controller.connectSelectedDevice();

    expect(result.isSuccess, isFalse);
    expect(controller.snapshot.boot.phase, BootPhase.failed);
    expect(
      controller.snapshot.boot.stages
          .singleWhere((stage) => stage.id == 'agent')
          .status,
      StageStatus.failed,
    );
  });

  test('rolls back components that started before a later failure', () async {
    final started = FakeBootComponent('agent');
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [started, FailingBootComponent('companion')],
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();

    await controller.connectSelectedDevice();

    expect(started.stopCount, 1);
  });

  test('does not report ready when boot components are missing', () async {
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [FakeBootComponent('agent'), FakeBootComponent('companion')],
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();

    final result = await controller.connectSelectedDevice();

    expect(result.isSuccess, isFalse);
    expect(controller.snapshot.boot.phase, BootPhase.failed);
    expect(controller.snapshot.boot.error?.code, OpenDexErrorCode.internal);
  });

  test(
    'launches and closes an application through the window gateway',
    () async {
      final windows = FakeWindowGateway();
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeCatalogComponent(),
        ],
        windowGateway: windows,
        surfaceResizeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();

      windows.launchGate = Completer<void>();
      final launchFuture = controller.launchApplication('com.example.demo');
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.snapshot.windows.single.status,
        WindowSessionStatus.starting,
      );
      windows.launchGate!.complete();
      final launched = await launchFuture;

      expect(launched, isA<CommandSuccess<String>>());
      final launchedId = (launched as CommandSuccess<String>).value;
      expect(
        controller.snapshot.windows.single.status,
        WindowSessionStatus.streaming,
      );
      windows.addTelemetry(controller.snapshot.windows.single.id, 60);
      expect(controller.snapshot.telemetry.framesPerSecond?.value, 60);
      expect(controller.snapshot.windows.single.producedFramesPerSecond, 60);
      windows.addTelemetry(launchedId, 60, presented: 9);
      expect(controller.snapshot.telemetry.framesPerSecond?.value, 9);
      // A later encoder/decoder sample must not replace the measured rate
      // displayed by the native texture with the faster source rate.
      windows.addTelemetry(launchedId, 60);
      expect(controller.snapshot.telemetry.framesPerSecond?.value, 9);
      windows.onClose = (_) => expect(controller.snapshot.windows, isEmpty);
      await controller.closeWindow(controller.snapshot.windows.single.id);
      expect(controller.snapshot.windows, isEmpty);
      expect(controller.snapshot.telemetry.framesPerSecond, isNull);
      expect(windows.closed, [launchedId]);
    },
  );

  test(
    'owns window geometry, stacking, display state, and input routing',
    () async {
      final windows = FakeWindowGateway();
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeCatalogComponent(),
        ],
        windowGateway: windows,
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      final first =
          (await controller.launchApplication('com.example.demo')
                  as CommandSuccess<String>)
              .value;
      final second =
          (await controller.launchApplication('com.example.demo')
                  as CommandSuccess<String>)
              .value;

      expect(controller.snapshot.windows, hasLength(2));
      expect(controller.snapshot.windows.last.zOrder, greaterThan(0));
      expect(controller.snapshot.windows.last.surfaceSize?.width, 1280);

      const geometry = WindowGeometry(x: 120, y: 80, width: 800, height: 600);
      expect((await controller.moveWindow(first, geometry)).isSuccess, isTrue);
      expect(
        controller.snapshot.windows
            .singleWhere((window) => window.id == first)
            .geometry,
        same(geometry),
      );
      expect((await controller.focusWindow(first)).isSuccess, isTrue);
      expect((await controller.raiseWindow(first)).isSuccess, isTrue);
      expect(
        controller.snapshot.windows
            .singleWhere((window) => window.id == first)
            .zOrder,
        greaterThan(
          controller.snapshot.windows
              .singleWhere((window) => window.id == second)
              .zOrder,
        ),
      );

      const pointer = WindowPointerSample(
        phase: WindowPointerPhase.down,
        x: 640,
        y: 360,
        pointerId: 1,
        buttons: 1,
      );
      const key = WindowKeySample(
        phase: WindowKeyPhase.down,
        physicalKeyId: 4,
        logicalKeyId: 65,
        character: 'a',
      );
      expect((await controller.sendPointer(first, pointer)).isSuccess, isTrue);
      expect((await controller.sendKey(first, key)).isSuccess, isTrue);
      expect(windows.pointers, [(first, pointer)]);
      expect(windows.keys, [(first, key)]);

      await controller.setWindowDisplayState(
        first,
        WindowDisplayState.minimised,
      );
      expect(
        controller.snapshot.windows
            .singleWhere((window) => window.id == first)
            .isFocused,
        isFalse,
      );
      expect(
        controller.snapshot.windows
            .singleWhere((window) => window.id == second)
            .isFocused,
        isTrue,
      );
    },
  );

  test('replaces the Android surface when the window shape changes', () async {
    final windows = FakeWindowGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [
        FakeBootComponent('agent'),
        FakeBootComponent('companion'),
        FakeCatalogComponent(),
      ],
      windowGateway: windows,
      surfaceResizeDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();
    final id =
        (await controller.launchApplication('com.example.demo')
                as CommandSuccess<String>)
            .value;

    await controller.moveWindow(
      id,
      const WindowGeometry(x: 20, y: 20, width: 400, height: 700),
    );

    expect(windows.resized.map((entry) => entry.$1), [id]);
    expect(
      windows.resized.map((entry) => '${entry.$2.width}x${entry.$2.height}'),
      ['768x1280'],
    );
    var state = controller.snapshot.windows.single;
    expect(state.id, id);
    expect(state.displayId, 101);
    expect(
      '${state.surfaceSize?.width}x${state.surfaceSize?.height}',
      '768x1280',
    );

    await controller.moveWindow(
      id,
      const WindowGeometry(x: 20, y: 20, width: 800, height: 500),
    );

    expect(windows.resized.last.$1, id);
    expect(
      '${windows.resized.last.$2.width}x${windows.resized.last.$2.height}',
      '1280x752',
    );
    state = controller.snapshot.windows.single;
    expect(state.displayId, 102);
    expect(
      '${state.surfaceSize?.width}x${state.surfaceSize?.height}',
      '1280x752',
    );
  });

  test('accepts a backend-driven surface change after app rotation', () async {
    final windows = FakeWindowGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [
        FakeBootComponent('agent'),
        FakeBootComponent('companion'),
        FakeCatalogComponent(),
      ],
      windowGateway: windows,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();
    final id =
        (await controller.launchApplication('com.example.demo')
                as CommandSuccess<String>)
            .value;

    windows.emitSurface(
      WindowBackendSession(
        id: id,
        displayId: 12,
        surface: const WindowSurface(
          textureId: 91,
          pixelSize: WindowPixelSize(width: 720, height: 1280),
        ),
      ),
    );

    final window = controller.snapshot.windows.single;
    expect(window.surface?.textureId, 91);
    expect(window.surfaceSize?.width, 720);
    expect(window.surfaceSize?.height, 1280);
  });

  test(
    'shows a stopped state when the Android application task exits',
    () async {
      final windows = FakeWindowGateway();
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeCatalogComponent(),
        ],
        windowGateway: windows,
        surfaceResizeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      final id =
          (await controller.launchApplication('com.example.demo')
                  as CommandSuccess<String>)
              .value;

      windows.emitExit(id, 20);
      await Future<void>.delayed(Duration.zero);

      final stopped = controller.snapshot.windows.single;
      expect(stopped.status, WindowSessionStatus.failed);
      expect(stopped.error?.message, 'Demo stopped unexpectedly.');
    },
  );

  test('rejects invalid window geometry and out-of-surface input', () async {
    final windows = FakeWindowGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [
        FakeBootComponent('agent'),
        FakeBootComponent('companion'),
        FakeCatalogComponent(),
      ],
      windowGateway: windows,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();
    final id =
        (await controller.launchApplication('com.example.demo')
                as CommandSuccess<String>)
            .value;

    final geometry = await controller.moveWindow(
      id,
      const WindowGeometry(x: 0, y: 0, width: 100, height: 100),
    );
    // A pointer past the surface edge is ordinary mouse movement, not an error:
    // it succeeds as a silent no-op and nothing is forwarded to the phone.
    final outside = await controller.sendPointer(
      id,
      const WindowPointerSample(
        phase: WindowPointerPhase.move,
        x: 1300,
        y: 360,
        pointerId: 1,
      ),
    );

    // A malformed sample — a negative pointer id here — is a real fault and is
    // still rejected.
    final malformed = await controller.sendPointer(
      id,
      const WindowPointerSample(
        phase: WindowPointerPhase.move,
        x: 10,
        y: 10,
        pointerId: -1,
      ),
    );

    expect(geometry.isSuccess, isFalse);
    expect(outside.isSuccess, isTrue);
    expect(malformed.isSuccess, isFalse);
    expect(windows.pointers, isEmpty);
  });

  test('reconnect stops runtime and restarts the same device', () async {
    final gateway = FakeDeviceGateway();
    final components = [
      FakeBootComponent('agent'),
      FakeBootComponent('companion'),
      FakeCatalogComponent(),
    ];
    final controller = OpenDexController(
      deviceGateway: gateway,
      components: components,
      reconnectDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();

    final phases = <RecoveryPhase>[];
    final subscription = controller.states.listen(
      (state) => phases.add(state.recovery.phase),
    );
    addTearDown(subscription.cancel);
    final result = await controller.reconnect();
    await Future<void>.delayed(Duration.zero);

    expect(result.isSuccess, isTrue);
    expect(gateway.disconnectCount, 1);
    expect(
      components,
      everyElement(
        predicate<FakeBootComponent>((item) => item.startCount == 2),
      ),
    );
    expect(
      components,
      everyElement(predicate<FakeBootComponent>((item) => item.stopCount == 1)),
    );
    expect(
      phases,
      containsAllInOrder([
        RecoveryPhase.detecting,
        RecoveryPhase.reconnecting,
        RecoveryPhase.restartingServices,
        RecoveryPhase.recovered,
      ]),
    );
    expect(controller.snapshot.boot.phase, BootPhase.ready);
  });

  test('reconnect retries discovery and reports recovery attempt', () async {
    final gateway = FakeDeviceGateway(
      discoveries: const [
        [FakeDeviceGateway.device],
        [],
        [FakeDeviceGateway.device],
      ],
    );
    final controller = OpenDexController(
      deviceGateway: gateway,
      components: [
        FakeBootComponent('agent'),
        FakeBootComponent('companion'),
        FakeCatalogComponent(),
      ],
      reconnectAttempts: 2,
      reconnectDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();

    final result = await controller.reconnect();

    expect(result.isSuccess, isTrue);
    expect(controller.snapshot.recovery.phase, RecoveryPhase.recovered);
    expect(controller.snapshot.recovery.attempt, 2);
  });

  test('reconnect fails safely when no device is selected', () async {
    final controller = OpenDexController(deviceGateway: FakeDeviceGateway());
    addTearDown(controller.dispose);

    final result = await controller.reconnect();

    expect(result.isSuccess, isFalse);
    expect(controller.snapshot.recovery.phase, RecoveryPhase.failed);
    expect(
      controller.snapshot.recovery.error?.code,
      OpenDexErrorCode.connectionFailed,
    );
  });

  test('pairs, connects, and forgets a wireless device', () async {
    final wireless = FakeWirelessDeviceGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      wirelessDeviceGateway: wireless,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();

    final paired = await controller.pairWirelessDevice(
      host: '192.0.2.20',
      pairingPort: 37123,
      pairingCode: '123456',
    );
    final connected = await controller.connectWirelessDevice(
      host: '192.0.2.20',
      port: 38888,
    );

    expect(paired.isSuccess, isTrue);
    expect(connected, isA<CommandSuccess<DeviceSummary>>());
    expect(
      controller.snapshot.selectedDevice?.connectionKind,
      DeviceConnectionKind.wifi,
    );
    expect(wireless.pairingPort, 37123);

    final forgotten = await controller.forgetWirelessDevice(
      controller.snapshot.selectedDevice!.id,
    );

    expect(forgotten.isSuccess, isTrue);
    expect(controller.snapshot.selectedDevice, isNull);
    expect(controller.snapshot.devices, hasLength(1));
  });

  test('does not disable the Wi-Fi transport of the selected device', () async {
    final wireless = FakeWirelessDeviceGateway();
    final commands = FakeDeviceCommandGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      wirelessDeviceGateway: wireless,
      deviceCommandGateway: commands,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectWirelessDevice(host: '192.0.2.20', port: 38888);

    final blocked = await controller.setDeviceControl(
      DeviceControl.wifi,
      false,
    );

    expect(blocked, isA<CommandFailure<void>>());
    expect((blocked as CommandFailure<void>).error.capability, 'wifi-control');
    expect(commands.controls, isEmpty);

    await controller.selectDevice(FakeDeviceGateway.device.id);
    final allowed = await controller.setDeviceControl(
      DeviceControl.wifi,
      false,
    );

    expect(allowed.isSuccess, isTrue);
    expect(commands.controls, [(DeviceControl.wifi, false)]);
    expect(controller.snapshot.telemetry.wifiEnabled, isFalse);
  });

  test('opens a permission settings screen through its gateway', () async {
    final permissions = FakePermissionGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [
        FakeBootComponent('agent'),
        FakeBootComponent('companion'),
        FakeCatalogComponent(),
      ],
      permissionGateway: permissions,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();

    final result = await controller.openPermissionSettings('notifications');

    expect(result.isSuccess, isTrue);
    expect(permissions.opened, ['notifications']);
  });

  test(
    'routes notification actions and targets the owning app display',
    () async {
      final notifications = FakeNotificationGateway();
      final windows = FakeWindowGateway();
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          NotificationStateComponent(),
          FakeCatalogComponent(),
        ],
        windowGateway: windows,
        notificationGateway: notifications,
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();

      expect(
        (await controller.dismissNotification('notification-1')).isSuccess,
        isTrue,
      );
      expect(controller.snapshot.notifications, hasLength(1));
      expect(
        (await controller.activateNotification('notification-1')).isSuccess,
        isTrue,
      );
      expect(
        controller.snapshot.windows.single.application.packageName,
        'com.example.demo',
      );
      expect(notifications.dismissed, ['notification-1']);
      expect(notifications.activated, [('notification-1', 12)]);

      expect((await controller.dismissAllNotifications()).isSuccess, isTrue);
      expect(notifications.dismissAllCount, 1);
    },
  );

  test('rejects a stale notification without contacting Android', () async {
    final notifications = FakeNotificationGateway();
    final controller = OpenDexController(
      deviceGateway: FakeDeviceGateway(),
      components: [
        FakeBootComponent('agent'),
        NotificationStateComponent(),
        FakeCatalogComponent(),
      ],
      notificationGateway: notifications,
    );
    addTearDown(controller.dispose);
    await controller.discoverDevices();
    await controller.connectSelectedDevice();

    final result = await controller.dismissNotification('stale');

    expect(result, isA<CommandFailure<void>>());
    expect(notifications.dismissed, isEmpty);
  });

  test(
    'clipboard access requires a connected device and explicit opt-in',
    () async {
      final clipboard = FakeClipboardGateway();
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        clipboardGateway: clipboard,
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeBootComponent('applications'),
        ],
      );
      addTearDown(controller.dispose);
      expect(
        (await controller.setClipboardText('before connection')).isSuccess,
        isFalse,
      );
      expect((await controller.setClipboardSync(true)).isSuccess, isFalse);
      expect(clipboard.writes, 0);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      expect(
        (await controller.setClipboardText('before consent')).isSuccess,
        isFalse,
      );
      await controller.setClipboardSync(true);
      expect(
        (await controller.setClipboardText('shared text')).isSuccess,
        isTrue,
      );
      expect(controller.snapshot.clipboard.text, 'shared text');
      expect(
        (await controller.setClipboardText('x' * 65537)).isSuccess,
        isFalse,
      );
      expect(clipboard.writes, 1);
      await controller.disconnect();
      expect(controller.snapshot.clipboard.syncEnabled, isFalse);
      expect(
        (await controller.setClipboardText('after disconnect')).isSuccess,
        isFalse,
      );
      expect(clipboard.writes, 1);
    },
  );
  group('display mirror', () {
    Future<OpenDexController> connected(FakeDisplayMirrorGateway mirror) async {
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeCatalogComponent(),
        ],
        displayMirrorGateway: mirror,
        surfaceRetireDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      return controller;
    }

    test('starts, streams the phone surface, then stops', () async {
      final mirror = FakeDisplayMirrorGateway();
      final controller = await connected(mirror);
      mirror.startGate = Completer<void>();
      final start = controller.startDisplayMirror();
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.snapshot.displayMirror.status,
        DisplayMirrorStatus.starting,
      );
      mirror.startGate!.complete();
      expect(await start, isA<CommandSuccess<void>>());
      final state = controller.snapshot.displayMirror;
      expect(state.status, DisplayMirrorStatus.streaming);
      expect(state.surface?.textureId, 1);
      expect(state.surface?.pixelSize.height, 1170);
      expect(mirror.started, [FakeDeviceGateway.device.id]);

      // The surface leaves the snapshot before the texture is released, the
      // same retire order the windows use, so the desk never paints a freed
      // texture.
      mirror.onStop = (_) => expect(
        controller.snapshot.displayMirror.status,
        DisplayMirrorStatus.idle,
      );
      expect(await controller.stopDisplayMirror(), isA<CommandSuccess<void>>());
      expect(controller.snapshot.displayMirror.surface, isNull);
      expect(mirror.stopped, ['mirror-1']);
    });

    test(
      'a second start while streaming does not open a second stream',
      () async {
        final mirror = FakeDisplayMirrorGateway();
        final controller = await connected(mirror);
        await controller.startDisplayMirror();
        await controller.startDisplayMirror();
        expect(mirror.started, hasLength(1));
      },
    );

    test('a backend failure is reported on the state, not thrown', () async {
      final mirror = FakeDisplayMirrorGateway()
        ..failure = const BackendFailure(
          OpenDexError(
            code: OpenDexErrorCode.capabilityUnavailable,
            message: 'The phone refused the screen stream.',
            retryable: true,
            capability: 'display-mirror',
          ),
        );
      final controller = await connected(mirror);
      final result = await controller.startDisplayMirror();
      expect(result, isA<CommandFailure<void>>());
      final state = controller.snapshot.displayMirror;
      expect(state.status, DisplayMirrorStatus.failed);
      expect(state.error?.message, 'The phone refused the screen stream.');
      expect(state.surface, isNull);
      // Retry works from failed.
      mirror.failure = null;
      await controller.startDisplayMirror();
      expect(
        controller.snapshot.displayMirror.status,
        DisplayMirrorStatus.streaming,
      );
    });

    test(
      'a stream that dies is failed; one that ends cleanly is idle',
      () async {
        final mirror = FakeDisplayMirrorGateway();
        final controller = await connected(mirror);
        await controller.startDisplayMirror();
        mirror.emitExit('mirror-1', 21, details: 'server gone');
        final state = controller.snapshot.displayMirror;
        expect(state.status, DisplayMirrorStatus.failed);
        expect(state.error?.retryable, isTrue);
        expect(state.error?.technicalDetails, 'server gone');
        expect(state.surface, isNull);

        await controller.startDisplayMirror();
        mirror.emitExit('mirror-2', 0);
        expect(
          controller.snapshot.displayMirror.status,
          DisplayMirrorStatus.idle,
        );
        // Stopping after the backend already ended does not call the gateway.
        await controller.stopDisplayMirror();
        expect(mirror.stopped, isEmpty);
      },
    );

    test('a rotated phone swaps the surface in place', () async {
      final mirror = FakeDisplayMirrorGateway();
      final controller = await connected(mirror);
      await controller.startDisplayMirror();
      mirror.emitSurface(
        const MirrorBackendSession(
          id: 'mirror-1',
          surface: WindowSurface(
            textureId: 9,
            pixelSize: WindowPixelSize(width: 1170, height: 540),
          ),
        ),
      );
      final state = controller.snapshot.displayMirror;
      expect(state.status, DisplayMirrorStatus.streaming);
      expect(state.surface?.textureId, 9);
      expect(state.surface?.pixelSize.width, 1170);
      // A stale session's update is ignored.
      mirror.emitSurface(
        const MirrorBackendSession(
          id: 'mirror-0',
          surface: WindowSurface(
            textureId: 3,
            pixelSize: WindowPixelSize(width: 1, height: 1),
          ),
        ),
      );
      expect(controller.snapshot.displayMirror.surface?.textureId, 9);
    });

    test(
      'disconnecting stops the mirror with the rest of the runtime',
      () async {
        final mirror = FakeDisplayMirrorGateway();
        final controller = await connected(mirror);
        await controller.startDisplayMirror();
        await controller.disconnect();
        expect(mirror.stopped, ['mirror-1']);
        expect(
          controller.snapshot.displayMirror.status,
          DisplayMirrorStatus.idle,
        );
        expect(controller.snapshot.displayMirror.surface, isNull);
      },
    );

    test('without a mirror gateway the state says so', () async {
      final controller = OpenDexController(
        deviceGateway: FakeDeviceGateway(),
        components: [
          FakeBootComponent('agent'),
          FakeBootComponent('companion'),
          FakeCatalogComponent(),
        ],
      );
      addTearDown(controller.dispose);
      await controller.discoverDevices();
      await controller.connectSelectedDevice();
      final result = await controller.startDisplayMirror();
      expect(result, isA<CommandFailure<void>>());
      final state = controller.snapshot.displayMirror;
      expect(state.status, DisplayMirrorStatus.unavailable);
      expect(state.error?.capability, 'display-mirror');
    });

    test(
      'before the phone is linked, starting fails and stays retryable',
      () async {
        final mirror = FakeDisplayMirrorGateway();
        final controller = OpenDexController(
          deviceGateway: FakeDeviceGateway(),
          displayMirrorGateway: mirror,
        );
        addTearDown(controller.dispose);
        final result = await controller.startDisplayMirror();
        expect(result, isA<CommandFailure<void>>());
        expect(
          controller.snapshot.displayMirror.status,
          DisplayMirrorStatus.failed,
        );
        expect(controller.snapshot.displayMirror.error?.retryable, isTrue);
        expect(mirror.started, isEmpty);
      },
    );
  });
}

class FakeDeviceGateway implements DeviceGateway {
  FakeDeviceGateway({List<List<DeviceSummary>>? discoveries})
    : _discoveries = [...?discoveries];

  bool started = false;
  int disconnectCount = 0;
  final List<List<DeviceSummary>> _discoveries;

  static const device = DeviceSummary(
    id: 'device-1',
    name: 'Test phone',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
  );

  @override
  Future<void> start() async => started = true;

  @override
  Future<List<DeviceSummary>> discoverDevices() async =>
      _discoveries.isEmpty ? const [device] : _discoveries.removeAt(0);

  @override
  Future<DeviceSummary> prepareDevice(DeviceSummary device) async => device;

  @override
  Future<void> disconnectDevice(DeviceSummary device) async {
    disconnectCount++;
  }
}

class FakeBootComponent implements BootComponent {
  FakeBootComponent(this.stageId);

  int startCount = 0;
  int stopCount = 0;

  @override
  final String stageId;

  @override
  Future<void> start(DeviceSummary device) async => startCount++;

  @override
  Future<void> stop(DeviceSummary device) async => stopCount++;
}

class FailingBootComponent extends FakeBootComponent {
  FailingBootComponent(super.stageId);

  @override
  Future<void> start(DeviceSummary device) async {
    throw const BackendFailure(
      OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android agent could not start.',
        retryable: true,
      ),
    );
  }
}

class DisconnectingCompanion extends FakeBootComponent
    implements UserDisconnectProvider {
  DisconnectingCompanion({this.requestOnStart = false}) : super('companion');
  final bool requestOnStart;
  final requests = StreamController<void>();
  @override
  bool get userDisconnectRequested => requestOnStart;
  @override
  Stream<void> get userDisconnectRequests => requests.stream;
}

class FakeCatalogComponent extends FakeBootComponent
    implements ApplicationCatalogProvider {
  FakeCatalogComponent() : super('applications');

  @override
  List<AndroidApplication> get applications => const [
    AndroidApplication(packageName: 'com.example.demo', label: 'Demo'),
  ];
}

class NotificationStateComponent extends FakeBootComponent
    implements BackendStateProvider {
  NotificationStateComponent() : super('companion');

  @override
  BackendStateUpdate get currentUpdate => BackendStateUpdate(
    notificationStatus: LoadStatus.ready,
    notifications: [
      NotificationItem(
        id: 'notification-1',
        packageName: 'com.example.demo',
        title: 'Demo',
        body: 'Open me',
        timestamp: DateTime.utc(2026, 8, 25),
      ),
    ],
  );

  @override
  Stream<BackendStateUpdate> get updates => const Stream.empty();
}

class FakeWindowGateway
    implements
        WindowGateway,
        ResizableWindowGateway,
        WindowSurfaceUpdateGateway {
  final _exits = StreamController<WindowBackendExit>.broadcast();
  final _telemetry = StreamController<WindowBackendTelemetry>.broadcast(
    sync: true,
  );
  final _surfaces = StreamController<WindowBackendSession>.broadcast(
    sync: true,
  );
  final closed = <String>[];
  final pointers = <(String, WindowPointerSample)>[];
  final keys = <(String, WindowKeySample)>[];
  final resized = <(String, WindowPixelSize)>[];
  void Function(String sessionId)? onClose;
  Completer<void>? launchGate;
  int _sequence = 0;

  @override
  Stream<WindowBackendExit> get exits => _exits.stream;

  @override
  Stream<WindowBackendTelemetry> get telemetry => _telemetry.stream;

  @override
  Stream<WindowBackendSession> get surfaceUpdates => _surfaces.stream;

  void emitSurface(WindowBackendSession session) => _surfaces.add(session);

  void addTelemetry(
    String sessionId,
    double framesPerSecond, {
    double? presented,
  }) {
    _telemetry.add(
      WindowBackendTelemetry(
        sessionId: sessionId,
        producedFramesPerSecond: framesPerSecond,
        presentedFramesPerSecond: presented,
      ),
    );
  }

  void emitExit(String sessionId, int exitCode) {
    _exits.add(WindowBackendExit(sessionId: sessionId, exitCode: exitCode));
  }

  @override
  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  }) async {
    final sequence = ++_sequence;
    await launchGate?.future;
    return WindowBackendSession(
      id: sessionId ?? 'window-$sequence',
      displayId: 11 + sequence,
      surface: WindowSurface(
        textureId: sequence,
        pixelSize: const WindowPixelSize(width: 1280, height: 896),
      ),
    );
  }

  @override
  Future<void> close(String sessionId) async {
    onClose?.call(sessionId);
    closed.add(sessionId);
  }

  @override
  Future<WindowBackendSession> resizeSurface(
    String sessionId,
    WindowPixelSize pixelSize,
  ) async {
    resized.add((sessionId, pixelSize));
    return WindowBackendSession(
      id: sessionId,
      displayId: 100 + resized.length,
      surface: WindowSurface(
        textureId: 100 + resized.length,
        pixelSize: pixelSize,
      ),
    );
  }

  @override
  Future<void> sendPointer(
    String sessionId,
    WindowPointerSample sample,
  ) async => pointers.add((sessionId, sample));

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async =>
      keys.add((sessionId, sample));

  @override
  Future<void> dispose() async {
    await _exits.close();
    await _telemetry.close();
    await _surfaces.close();
  }
}

class FakeWirelessDeviceGateway implements WirelessDeviceGateway {
  int? pairingPort;

  @override
  Future<void> pair({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) async {
    this.pairingPort = pairingPort;
  }

  @override
  Future<DeviceSummary> connect({
    required String host,
    required int port,
  }) async => DeviceSummary(
    id: '$host:$port',
    name: 'Wireless phone',
    connectionKind: DeviceConnectionKind.wifi,
    status: DeviceStatus.authorized,
  );

  @override
  Future<void> forget(String deviceId) async {}
}

class FakeDeviceCommandGateway implements DeviceCommandGateway {
  final controls = <(DeviceControl, bool)>[];

  @override
  Future<void> setDeviceControl(DeviceControl control, bool enabled) async {
    controls.add((control, enabled));
  }

  @override
  Future<void> sendMediaAction(MediaAction action) async {}

  @override
  Future<void> setVolume(String stream, int value) async {}
}

class FakePermissionGateway implements PermissionGateway {
  final opened = <String>[];

  @override
  Future<void> openSettings(String capability) async => opened.add(capability);
}

class FakeNotificationGateway implements NotificationGateway {
  final dismissed = <String>[];
  final activated = <(String, int?)>[];
  int dismissAllCount = 0;

  @override
  Future<void> dismiss(String notificationId) async {
    dismissed.add(notificationId);
  }

  @override
  Future<void> activate(String notificationId, {int? displayId}) async {
    activated.add((notificationId, displayId));
  }

  @override
  Future<void> dismissAll() async {
    dismissAllCount++;
  }
}

class FakeClipboardGateway implements ClipboardGateway {
  @override
  ClipboardState clipboard = const ClipboardState(
    availability: ClipboardAvailability.available,
  );
  int writes = 0;

  @override
  void setSyncEnabled(bool enabled) {
    clipboard = ClipboardState(
      kind: clipboard.kind,
      text: clipboard.text,
      syncEnabled: enabled,
      availability: ClipboardAvailability.available,
    );
  }

  @override
  Future<void> writeText(String text) async {
    writes++;
    clipboard = ClipboardState(
      kind: text.isEmpty ? ClipboardKind.empty : ClipboardKind.text,
      text: text.isEmpty ? null : text,
      syncEnabled: clipboard.syncEnabled,
      availability: ClipboardAvailability.available,
    );
  }
}

class FakeDisplayMirrorGateway implements DisplayMirrorGateway {
  final _exits = StreamController<MirrorBackendExit>.broadcast(sync: true);
  final _surfaces = StreamController<MirrorBackendSession>.broadcast(
    sync: true,
  );
  final started = <String>[];
  final stopped = <String>[];
  BackendFailure? failure;
  Completer<void>? startGate;
  void Function(String sessionId)? onStop;
  int _sequence = 0;

  @override
  Stream<MirrorBackendExit> get exits => _exits.stream;

  @override
  Stream<MirrorBackendSession> get surfaceUpdates => _surfaces.stream;

  void emitExit(String sessionId, int exitCode, {String? details}) =>
      _exits.add(
        MirrorBackendExit(
          sessionId: sessionId,
          exitCode: exitCode,
          details: details,
        ),
      );

  void emitSurface(MirrorBackendSession session) => _surfaces.add(session);

  @override
  Future<MirrorBackendSession> start(DeviceSummary device) async {
    await startGate?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    started.add(device.id);
    final sequence = ++_sequence;
    return MirrorBackendSession(
      id: 'mirror-$sequence',
      surface: WindowSurface(
        textureId: sequence,
        pixelSize: const WindowPixelSize(width: 540, height: 1170),
      ),
    );
  }

  @override
  Future<void> stop(String sessionId) async {
    onStop?.call(sessionId);
    stopped.add(sessionId);
  }

  @override
  Future<void> dispose() async {
    await _exits.close();
    await _surfaces.close();
  }
}
