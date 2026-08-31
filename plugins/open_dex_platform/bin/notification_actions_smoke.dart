import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || !File(arguments.first).existsSync()) {
    stderr.writeln('usage: dart run bin/notification_actions_smoke.dart APK');
    exitCode = 64;
    return;
  }

  final adb = AdbClient(executable: Platform.environment['ADB_PATH'] ?? 'adb');
  final devices = await adb.listDevices();
  final authorized = devices.where(
    (device) => device.status == DeviceStatus.authorized,
  );
  if (authorized.length != 1) {
    throw StateError('Exactly one authorized Android device is required.');
  }
  final device = authorized.single;
  final companion = CompanionBootComponent(
    adb: adb,
    sessionToken: SessionToken.generate(),
    companionApkPath: arguments.first,
  );
  String? notificationId;

  try {
    await companion.start(device);
    if (companion.currentUpdate.permissions?.grants['notifications'] !=
        PermissionGrant.granted) {
      throw StateError('Notification-listener access is not granted.');
    }

    const title = 'DroidPier verification';
    await adb.shell(device.id, const [
      'cmd',
      'notification',
      'post',
      '--title',
      title,
      '--content-intent',
      'activity',
      '-a',
      'android.settings.SETTINGS',
      'open-dex-verification',
      'Synthetic notification action test',
    ]);
    final update = await companion.updates
        .firstWhere(
          (state) =>
              state.notifications?.any((item) => item.title == title) == true,
        )
        .timeout(const Duration(seconds: 10));
    notificationId = update.notifications!
        .singleWhere((item) => item.title == title)
        .id;

    await companion.activate(notificationId);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await adb.shell(device.id, const ['input', 'keyevent', 'KEYCODE_BACK']);

    await companion.dismiss(notificationId);
    await companion.updates
        .firstWhere(
          (state) =>
              state.notifications?.any((item) => item.id == notificationId) ==
              false,
        )
        .timeout(const Duration(seconds: 10));
    notificationId = null;

    stdout.writeln(
      'notificationActions=activate,dismiss syntheticOnly=true cleanup=ok',
    );
  } finally {
    if (notificationId != null) {
      try {
        await companion.dismiss(notificationId);
      } on Object {
        // Best effort: never leave the synthetic test notification behind.
      }
    }
    await companion.stop(device);
  }
}
