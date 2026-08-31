import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run bin/scrcpy_smoke.dart SCRCPY_DIRECTORY');
    exitCode = 64;
    return;
  }
  final runtime = Directory(arguments.single).absolute;
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

  final gateway = ScrcpyWindowGateway(
    executable: '${runtime.path}/scrcpy',
    serverPath: '${runtime.path}/scrcpy-server',
    adbExecutable: adb.executable,
  );
  final exits = <WindowBackendExit>[];
  final telemetry = <WindowBackendTelemetry>[];
  final exitSubscription = gateway.exits.listen(exits.add);
  final telemetrySubscription = gateway.telemetry.listen(telemetry.add);
  try {
    final session = await gateway.launch(
      authorized.single,
      const AndroidApplication(
        packageName: 'com.android.settings',
        label: 'Settings',
      ),
    );
    stdout.writeln('scrcpySession=${session.id} started=true');
    await Future<void>.delayed(const Duration(seconds: 5));
    if (exits.any((event) => event.sessionId == session.id)) {
      throw StateError('scrcpy exited before the smoke interval completed');
    }
    final sessionTelemetry = telemetry.where(
      (event) => event.sessionId == session.id,
    );
    if (sessionTelemetry.isEmpty) {
      throw StateError('scrcpy did not publish an FPS sample');
    }
    stdout.writeln(
      'scrcpySession=${session.id} '
      'produced_fps=${sessionTelemetry.last.producedFramesPerSecond} '
      'presented_fps=${sessionTelemetry.last.presentedFramesPerSecond}',
    );
    await gateway.close(session.id);
    stdout.writeln('scrcpySession=${session.id} closed=true');
  } finally {
    await exitSubscription.cancel();
    await telemetrySubscription.cancel();
    await gateway.dispose();
  }
}
