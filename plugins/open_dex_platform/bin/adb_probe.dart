import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

Future<void> main() async {
  final client = AdbClient(
    executable: Platform.environment['ADB_PATH'] ?? 'adb',
  );
  try {
    await client.startServer();
    final devices = await client.listDevices();
    stdout.writeln('devices=${devices.length}');
    for (final device in devices) {
      final prepared = device.status == DeviceStatus.authorized
          ? await AdbDeviceGateway(client).prepareDevice(device)
          : device;
      stdout.writeln(
        'kind=${device.connectionKind.name} status=${device.status.name} '
        'name=${device.name} model=${device.model ?? 'unknown'} '
        'android=${prepared.androidVersion ?? 'unknown'}',
      );
    }
  } on AdbException catch (error) {
    stderr.writeln('${error.operation}: ${error.message}');
    exitCode = 1;
  }
}
