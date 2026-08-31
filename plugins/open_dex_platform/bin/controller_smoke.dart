import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'usage: dart run bin/controller_smoke.dart AGENT_JAR COMPANION_APK SCRCPY_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  final adb = AdbClient(executable: Platform.environment['ADB_PATH'] ?? 'adb');
  final token = SessionToken.generate();
  final agent = AgentBootComponent(
    adb: adb,
    sessionToken: token,
    agentJarPath: arguments[0],
  );
  final companion = CompanionBootComponent(
    adb: adb,
    sessionToken: token,
    companionApkPath: arguments[1],
  );
  final clipboard = AgentClipboardBootComponent(agent: agent);
  final runtime = Directory(arguments[2]).absolute.path;
  final commandGateway = AgentCommandGateway(agent);
  final controller = OpenDexController(
    deviceGateway: AdbDeviceGateway(adb),
    components: [
      agent,
      companion,
      ApplicationCatalogBootComponent(agent: agent),
      clipboard,
    ],
    windowGateway: ScrcpyWindowGateway(
      executable: '$runtime/scrcpy',
      serverPath: '$runtime/scrcpy-server',
      adbExecutable: adb.executable,
    ),
    deviceCommandGateway: commandGateway,
    clipboardGateway: clipboard,
  );
  try {
    final discovery = await controller.discoverDevices();
    if (discovery case CommandFailure<List<DeviceSummary>>(:final error)) {
      throw StateError(
        'device discovery failed: ${error.code.name} ${error.technicalDetails ?? error.message}',
      );
    }
    final connection = await controller.connectSelectedDevice();
    if (connection case CommandFailure<void>(:final error)) {
      throw StateError(
        'controller boot failed: ${error.code.name} ${error.technicalDetails ?? error.message}',
      );
    }
    await controller.states
        .firstWhere(
          (state) =>
              state.telemetry.batteryPercentage != null &&
              state.permissions.status == LoadStatus.ready,
        )
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => controller.snapshot,
        );
    stdout.writeln(
      'boot=${controller.snapshot.boot.phase.name} '
      'applications=${controller.snapshot.applications.length} '
      'battery=${controller.snapshot.telemetry.batteryPercentage} '
      'notificationPermission=${controller.snapshot.permissions.grants['notifications']?.name} '
      'notifications=${controller.snapshot.notifications.length} '
      'media=${controller.snapshot.media.status.name} '
      'wifi=${controller.snapshot.telemetry.wifiEnabled} '
      'bluetooth=${controller.snapshot.telemetry.bluetoothEnabled} '
      'rotationLock=${controller.snapshot.telemetry.rotationLocked} '
      'volumeStreams=${controller.snapshot.telemetry.volume.length} '
      'clipboardAdvertised=${agent.capabilities.contains('clipboard.get') && agent.capabilities.contains('clipboard.set')}',
    );

    final telemetry = controller.snapshot.telemetry;
    final music = telemetry.volume['music'];
    if (music != null) {
      _requireSuccess(
        await controller.setVolume('music', music.current),
        'same-state music volume',
      );
    }
    for (final (control, value) in <(DeviceControl, bool?)>[
      (DeviceControl.wifi, telemetry.wifiEnabled),
      (DeviceControl.bluetooth, telemetry.bluetoothEnabled),
      (DeviceControl.rotationLock, telemetry.rotationLocked),
    ]) {
      if (value != null) {
        _requireSuccess(
          await controller.setDeviceControl(control, value),
          'same-state ${control.name}',
        );
      }
    }
    _requireSuccess(
      await controller.setClipboardSync(false),
      'clipboard sync off',
    );
    stdout.writeln(
      'controls=same-state-ok clipboardSync=false personalClipboardRead=false',
    );

    if (telemetry.wifiEnabled == true &&
        controller.snapshot.selectedDevice?.connectionKind ==
            DeviceConnectionKind.usb) {
      final deviceId = controller.snapshot.selectedDevice!.id;
      _requireSuccess(
        await controller.setDeviceControl(DeviceControl.wifi, false),
        'USB Wi-Fi off',
      );
      try {
        if (!await _waitForWifi(adb, deviceId, enabled: false)) {
          throw StateError('Android did not report Wi-Fi disabled over USB');
        }
      } finally {
        _requireSuccess(
          await controller.setDeviceControl(DeviceControl.wifi, true),
          'USB Wi-Fi restore',
        );
      }
      if (!await _waitForWifi(adb, deviceId, enabled: true)) {
        throw StateError('Android did not report Wi-Fi restored over USB');
      }
      stdout.writeln('usbWifi=off-verified-on-restored');
    }

    final reconnect = await controller.reconnect();
    if (reconnect case CommandFailure<void>(:final error)) {
      throw StateError(
        'controller reconnect failed: ${error.code.name} ${error.technicalDetails ?? error.message}',
      );
    }
    stdout.writeln(
      'recovery=${controller.snapshot.recovery.phase.name} '
      'attempt=${controller.snapshot.recovery.attempt} '
      'applications=${controller.snapshot.applications.length}',
    );

    const packageName = 'com.android.settings';
    final launch = await controller.launchApplication(packageName);
    if (launch case CommandSuccess<String>(value: final sessionId)) {
      stdout.writeln('window=$sessionId status=streaming');
      await Future<void>.delayed(const Duration(seconds: 5));
      await controller.closeWindow(sessionId);
      stdout.writeln('window=$sessionId status=closed');
    } else {
      throw StateError('application launch failed');
    }
  } finally {
    await controller.dispose();
  }
}

Future<bool> _waitForWifi(
  AdbClient adb,
  String deviceId, {
  required bool enabled,
}) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    final status = (await adb.shell(deviceId, const [
      'cmd',
      'wifi',
      'status',
    ])).toLowerCase();
    if (status.contains(enabled ? 'wifi is enabled' : 'wifi is disabled')) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void _requireSuccess(VoidResult result, String operation) {
  if (result case CommandFailure<void>(:final error)) {
    throw StateError(
      '$operation failed: ${error.code.name} '
      '${error.technicalDetails ?? error.message}',
    );
  }
}
