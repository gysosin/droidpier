import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run bin/companion_smoke.dart PATH_TO_APK');
    exitCode = 64;
    return;
  }
  final apk = File(arguments.single);
  if (!apk.existsSync()) {
    stderr.writeln('companion APK does not exist');
    exitCode = 66;
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
  final server = CompanionWebSocketServer(sessionToken: token);
  StreamSubscription<ProtocolEnvelope>? subscription;
  StreamSubscription<ProtocolException>? errorSubscription;
  const packageName = 'io.github.shrey113.openandroiddex.companion';
  final received = <String>{};
  final ready = Completer<void>();
  try {
    final hostPort = await server.start();
    subscription = server.messages.listen((message) {
      received.add(message.type);
      if (received.containsAll(const [
            'companion.hello',
            'battery.update',
            'permissions.update',
          ]) &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    errorSubscription = server.errors.listen(
      (error) => stderr.writeln('protocol error: ${error.message}'),
    );
    await adb.install(device.id, apk.absolute.path);
    await adb.reverse(device.id, devicePort: 3699, hostPort: hostPort);
    await adb.shell(device.id, const ['am', 'force-stop', packageName]);
    await adb.shell(device.id, [
      'am',
      'start-foreground-service',
      '-n',
      '$packageName/.CompanionService',
      '--es',
      'session_token',
      token,
    ]);
    try {
      await ready.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      stderr.writeln(
        'companion timeout; received=${received.toList()..sort()}',
      );
      rethrow;
    }
    stdout.writeln(
      'companionAuthenticated=${server.isAuthenticated} '
      'device=${device.name} messages=${received.toList()..sort()}',
    );
  } finally {
    await subscription?.cancel();
    await errorSubscription?.cancel();
    try {
      await adb.shell(device.id, const ['am', 'force-stop', packageName]);
    } on AdbException {
      // Cleanup is best effort and does not hide the primary test result.
    }
    try {
      await adb.removeReverse(device.id, 3699);
    } on AdbException {
      // The mapping may already be absent after transport shutdown.
    }
    await server.close();
  }
}
