// Device check for opening a web address on the phone: resolves the phone's
// browser, opens the address on a new display through the real window
// gateway, and counts the frames that arrive. Stop the desktop app first.
//
// dart run tool/url_probe.dart <adb> <scrcpy-server> <ffmpeg> <url> [seconds]
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

import 'probe_support.dart';

/// Writes one line and waits for it to leave.
///
/// To a file or a pipe Dart's stdout buffers ~64 KB, so a probe that stalls
/// looks like a probe that printed nothing. The flush must be awaited: a
/// second write while one is in flight throws "StreamSink is bound to a
/// stream", which then reads exactly like the pipeline hanging.
Future<void> log(Object? message) async {
  stdout.writeln(message);
  await stdout.flush();
}

Future<void> main(List<String> args) async {
  final adb = AdbClient(executable: args[0]);
  final url = args[3];
  final seconds = args.length > 4 ? int.parse(args[4]) : 4;
  final devices = await AdbDeviceGateway(adb).discoverDevices();
  final device = devices.firstWhere(
    (d) => d.status == DeviceStatus.authorized,
    orElse: () => throw StateError('no authorized device: $devices'),
  );
  final host = CountingTextureHost();
  final gateway = DirectScrcpyWindowGateway(
    serverStarter: ScrcpyServerLauncher(adb: adb),
    decoderStarter: const SystemH264DecoderStarter(),
    serverJarPath: args[1],
    ffmpegExecutable: args[2],
    textureHost: host,
    adb: adb,
  );
  final watch = Stopwatch()..start();
  try {
    // A bare package name launches the app the ordinary way instead, which
    // is how this tool tells a fault in the address path from a fault in the
    // window pipeline underneath it.
    final bool isUrl = url.contains('://');
    final packageName = isUrl ? await gateway.resolveBrowser(device, url) : url;
    await log('${isUrl ? 'browser' : 'app'}: ${packageName ?? 'none'}');
    if (packageName == null) return;
    final application = AndroidApplication(
      packageName: packageName,
      label: packageName,
    );
    final session = isUrl
        ? await gateway.launchUrl(device, application, url)
        : await gateway.launch(device, application);
    final surface = session.surface!;
    await log(
      'window on display ${session.displayId}: '
      '${surface.pixelSize.width}x${surface.pixelSize.height}, first frame '
      'after ${watch.elapsedMilliseconds} ms',
    );
    final before = host.framesFor(surface.textureId);
    final t0 = watch.elapsedMilliseconds;
    await Future<void>.delayed(Duration(seconds: seconds));
    final after = host.framesFor(surface.textureId);
    final dt = (watch.elapsedMilliseconds - t0) / 1000;
    await log(
      'frames ${after - before} in ${dt.toStringAsFixed(1)} s = '
      '${((after - before) / dt).toStringAsFixed(1)} fps',
    );
    final tasks = await adb.shell(device.id, const ['am', 'stack', 'list']);
    await log('browser task: ${taskLine(tasks, packageName)}');
    await gateway.close(session.id);
    await log('closed cleanly');
  } on BackendFailure catch (f) {
    await log('FAILED ${f.error.message} | ${f.error.technicalDetails}');
  } finally {
    await gateway.dispose();
  }
  exit(0);
}

/// The stack-list line naming the browser's task and display, for the eye.
String taskLine(String stackList, String packageName) {
  String? root;
  for (final line in stackList.split('\n')) {
    if (line.contains('RootTask id=')) root = line.trim();
    if (line.contains('$packageName/') && root != null) return root;
  }
  return 'not found';
}
