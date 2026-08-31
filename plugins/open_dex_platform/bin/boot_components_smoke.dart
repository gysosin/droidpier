import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run bin/boot_components_smoke.dart AGENT_JAR COMPANION_APK',
    );
    exitCode = 64;
    return;
  }
  final adb = AdbClient(executable: Platform.environment['ADB_PATH'] ?? 'adb');
  final devices = await adb.listDevices();
  final authorized = devices
      .where((device) => device.status == DeviceStatus.authorized)
      .toList();
  if (authorized.length != 1) {
    stderr.writeln('expected exactly one authorized Android device');
    exitCode = 1;
    return;
  }

  final device = authorized.single;
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
  final catalog = ApplicationCatalogBootComponent(agent: agent);
  final commands = AgentCommandGateway(agent);
  try {
    await agent.start(device);
    await companion.start(device);
    await catalog.start(device);
    if (companion.currentUpdate.telemetry?.batteryPercentage == null ||
        companion.currentUpdate.permissions?.status != LoadStatus.ready) {
      await companion.updates
          .firstWhere(
            (update) =>
                update.telemetry?.batteryPercentage != null &&
                update.permissions?.status == LoadStatus.ready,
          )
          .timeout(const Duration(seconds: 3));
    }
    final volumeOutput = await adb.shell(device.id, const [
      'cmd',
      'media_session',
      'volume',
      '--stream',
      '3',
      '--get',
    ]);
    final volumeMatch = RegExp(r'volume is (\d+)').firstMatch(volumeOutput);
    final volume = int.tryParse(volumeMatch?.group(1) ?? '');
    if (volume != null) await commands.setVolume('music', volume);
    final rotation = await adb.shell(device.id, const [
      'settings',
      'get',
      'system',
      'accelerometer_rotation',
    ]);
    await commands.setDeviceControl(
      DeviceControl.rotationLock,
      rotation.trim() == '0',
    );
    await commands.openSettings('notifications');
    await adb.shell(device.id, const ['input', 'keyevent', 'BACK']);
    stdout.writeln(
      'device=${device.name} agent=${agent.capabilities.toList()..sort()} '
      'companion=${companion.capabilities.toList()..sort()} '
      'applications=${catalog.applications.length} '
      'battery=${companion.currentUpdate.telemetry?.batteryPercentage} '
      'notificationPermission=${companion.currentUpdate.permissions?.grants['notifications']?.name} '
      'volumeRoundTrip=${volume ?? 'unavailable'} rotationRoundTrip=true '
      'permissionSettingsRoundTrip=true',
    );
  } finally {
    await catalog.stop(device);
    await companion.stop(device);
    await agent.stop(device);
  }
}
