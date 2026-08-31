import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 3 && arguments.first == '--pair-only') {
    await _pairOnly(arguments[1], arguments[2]);
    return;
  }
  if (arguments.length != 6) {
    stderr.writeln(
      'usage: dart run bin/wireless_controller_smoke.dart '
      'HOST PAIRING_PORT CONNECT_PORT AGENT_JAR COMPANION_APK SCRCPY_DIRECTORY\n'
      '   or: dart run bin/wireless_controller_smoke.dart '
      '--pair-only HOST PAIRING_PORT\n'
      '   or: dart run bin/wireless_controller_smoke.dart '
      '--connect-only HOST CONNECT_PORT AGENT_JAR COMPANION_APK SCRCPY_DIRECTORY',
    );
    exitCode = 64;
    return;
  }

  final connectOnly = arguments.first == '--connect-only';
  final host = connectOnly ? arguments[1] : arguments[0];
  final pairingPort = connectOnly ? null : int.tryParse(arguments[1]);
  final connectPort = int.tryParse(arguments[2]);
  if ((!connectOnly && pairingPort == null) || connectPort == null) {
    stderr.writeln('pairing and connection ports must be integers');
    exitCode = 64;
    return;
  }
  String? pairingCode;
  if (!connectOnly) {
    stderr.write('Pairing code: ');
    pairingCode = stdin.readLineSync()?.trim() ?? '';
  }

  final adb = AdbClient(executable: Platform.environment['ADB_PATH'] ?? 'adb');
  final gateway = AdbDeviceGateway(adb);
  final token = SessionToken.generate();
  final agent = AgentBootComponent(
    adb: adb,
    sessionToken: token,
    agentJarPath: arguments[3],
  );
  final companion = CompanionBootComponent(
    adb: adb,
    sessionToken: token,
    companionApkPath: arguments[4],
  );
  final clipboard = AgentClipboardBootComponent(agent: agent);
  final runtime = Directory(arguments[5]).absolute.path;
  final controller = OpenDexController(
    deviceGateway: gateway,
    wirelessDeviceGateway: gateway,
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
    deviceCommandGateway: AgentCommandGateway(agent),
    clipboardGateway: clipboard,
  );
  String? wirelessDeviceId;
  try {
    if (!connectOnly) {
      _requireSuccess(
        await controller.pairWirelessDevice(
          host: host,
          pairingPort: pairingPort!,
          pairingCode: pairingCode!,
        ),
        'wireless pairing',
      );
    }
    final connection = await controller.connectWirelessDevice(
      host: host,
      port: connectPort,
    );
    if (connection case CommandSuccess<DeviceSummary>(value: final device)) {
      wirelessDeviceId = device.id;
    } else if (connection case CommandFailure<DeviceSummary>(:final error)) {
      throw StateError(
        'wireless connection failed: ${error.code.name} '
        '${error.technicalDetails ?? error.message}',
      );
    }
    _requireSuccess(
      await controller.connectSelectedDevice(),
      'wireless controller boot',
    );
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
      'transport=wifi boot=${controller.snapshot.boot.phase.name} '
      'applications=${controller.snapshot.applications.length}',
    );

    final wifiOff = await controller.setDeviceControl(
      DeviceControl.wifi,
      false,
    );
    if (wifiOff case CommandFailure<void>(:final error)
        when error.capability == 'wifi-control') {
      stdout.writeln('wifiOff=blocked capability=wifi-control');
    } else {
      throw StateError('Wi-Fi off was not blocked on wireless transport');
    }

    const packageName = 'com.android.settings';
    final launch = await controller.launchApplication(packageName);
    if (launch case CommandSuccess<String>(value: final sessionId)) {
      stdout.writeln('window=$sessionId status=streaming');
      await Future<void>.delayed(const Duration(seconds: 5));
      _requireSuccess(await controller.closeWindow(sessionId), 'close window');
      stdout.writeln('window=$sessionId status=closed');
    } else if (launch case CommandFailure<String>(:final error)) {
      throw StateError(
        'application launch failed: ${error.code.name} '
        '${error.technicalDetails ?? error.message}',
      );
    }

    final connectedDeviceId = wirelessDeviceId;
    if (connectedDeviceId == null) {
      throw StateError('wireless device identifier was not retained');
    }
    _requireSuccess(
      await controller.forgetWirelessDevice(connectedDeviceId),
      'forget wireless device',
    );
    wirelessDeviceId = null;
    stdout.writeln('wirelessDevice=forgotten cleanup=complete');
  } finally {
    final cleanupDeviceId = wirelessDeviceId;
    if (cleanupDeviceId != null) {
      try {
        final result = await controller.forgetWirelessDevice(cleanupDeviceId);
        if (result case CommandFailure<void>()) {
          await adb.disconnectWireless(cleanupDeviceId);
        }
      } on Object {
        try {
          await adb.disconnectWireless(cleanupDeviceId);
        } on Object {
          // Preserve the original failure while still attempting cleanup.
        }
      }
    }
    await controller.dispose();
  }
}

Future<void> _pairOnly(String host, String pairingPortArgument) async {
  final pairingPort = int.tryParse(pairingPortArgument);
  if (pairingPort == null) {
    stderr.writeln('pairing port must be an integer');
    exitCode = 64;
    return;
  }
  stderr.write('Pairing code: ');
  final pairingCode = stdin.readLineSync()?.trim() ?? '';
  final adb = AdbClient(executable: Platform.environment['ADB_PATH'] ?? 'adb');
  final gateway = AdbDeviceGateway(adb);
  final controller = OpenDexController(
    deviceGateway: gateway,
    wirelessDeviceGateway: gateway,
  );
  try {
    _requireSuccess(
      await controller.pairWirelessDevice(
        host: host,
        pairingPort: pairingPort,
        pairingCode: pairingCode,
      ),
      'wireless pairing',
    );
    stdout.writeln('wirelessPairing=complete secretLogged=false');
  } finally {
    await controller.dispose();
  }
}

void _requireSuccess(VoidResult result, String operation) {
  if (result case CommandFailure<void>(:final error)) {
    throw StateError(
      '$operation failed: ${error.code.name} '
      '${error.technicalDetails ?? error.message}',
    );
  }
}
