// Device check for the agent's icon resolution: boots the real agent and
// catalog components against the attached phone, writes each app's icon as a
// PNG, and prints how many apps carried one. Stop the desktop app first; two
// agents on one phone fight over the port.
//
// dart run tool/catalog_probe.dart <adb> <agent-jar> <out-dir> [package ...]
import 'dart:io';
import 'dart:math';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';

Future<void> main(List<String> args) async {
  final adb = AdbClient(executable: args[0]);
  final out = Directory(args[2])..createSync(recursive: true);
  final wanted = args.skip(3).toSet();
  final devices = await AdbDeviceGateway(adb).discoverDevices();
  final device = devices.firstWhere(
    (d) => d.status == DeviceStatus.authorized,
    orElse: () => throw StateError('no authorized device: $devices'),
  );
  final agent = AgentBootComponent(
    adb: adb,
    sessionToken: List.generate(
      32,
      (_) => Random.secure().nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    agentJarPath: args[1],
  );
  final catalog = ApplicationCatalogBootComponent(agent: agent);
  try {
    await agent.start(device);
    await catalog.start(device);
    var withIcon = 0;
    for (final app in catalog.applications) {
      final icon = app.iconPng;
      if (icon == null) continue;
      withIcon++;
      if (wanted.isEmpty || wanted.contains(app.packageName)) {
        File('${out.path}/${app.packageName}.png').writeAsBytesSync(icon);
      }
    }
    stdout.writeln(
      'apps ${catalog.applications.length}, with icon $withIcon, '
      'written to ${out.path}',
    );
  } finally {
    await catalog.stop(device);
    await agent.stop(device);
  }
  exit(0);
}
