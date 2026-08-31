import 'dart:async';
import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run bin/agent_smoke.dart PATH_TO_AGENT_JAR');
    exitCode = 64;
    return;
  }

  final artifact = File(arguments.single);
  if (!artifact.existsSync()) {
    stderr.writeln('agent artifact does not exist');
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
  final server = AgentTcpServer(sessionToken: token);
  Process? process;
  const remotePath = '/data/local/tmp/open-dex-agent.jar';
  try {
    final hostPort = await server.start();
    await adb.reverse(device.id, devicePort: 3698, hostPort: hostPort);
    await adb.push(device.id, artifact.absolute.path, remotePath);
    process = await Process.start(adb.executable, [
      '-s',
      device.id,
      'shell',
      'CLASSPATH=$remotePath',
      'app_process',
      '/',
      'io.github.shrey113.openandroiddex.agent.Main',
      '--token',
      token,
      '--port',
      '3698',
    ], runInShell: false);
    final stderrLog = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final hello = await server.messages
        .firstWhere((message) => message.type == 'agent.hello')
        .timeout(const Duration(seconds: 10));
    stdout.writeln(
      'agent=${hello.type} authenticated=${server.isAuthenticated} '
      'device=${device.name} capabilities=${hello.data['capabilities']}',
    );
    server.send(
      ProtocolEnvelope(
        id: 'smoke-ping',
        type: 'ping',
        timestamp: DateTime.now().toUtc(),
      ),
    );
    final pong = await server.messages
        .firstWhere((message) => message.type == 'pong')
        .timeout(const Duration(seconds: 5));
    stdout.writeln('roundTrip=${pong.type} replyTo=${pong.data['replyTo']}');
    server.send(
      ProtocolEnvelope(
        id: 'smoke-apps',
        type: 'apps.list',
        timestamp: DateTime.now().toUtc(),
      ),
    );
    final catalog = await server.messages
        .firstWhere((message) => message.type == 'apps.result')
        .timeout(const Duration(seconds: 15));
    final applications = ApplicationCatalogBootComponent.parseApplications(
      catalog.data['applications'],
    );
    final resolvedLabels = applications
        .where((application) => application.label != application.packageName)
        .length;
    final icons = applications
        .where((application) => application.iconPng?.isNotEmpty ?? false)
        .length;
    stdout.writeln(
      'applications=${applications.length} '
      'resolvedLabels=$resolvedLabels icons=$icons',
    );
    if (applications.isEmpty || resolvedLabels == 0 || icons == 0) {
      throw StateError('Android application metadata was not resolved');
    }
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 3));
    final diagnostic = (await stderrLog).trim();
    if (diagnostic.isNotEmpty) stderr.writeln(diagnostic);
  } finally {
    process?.kill();
    await _stopRemoteAgent(adb, device.id);
    try {
      await adb.removeReverse(device.id, 3698);
    } on AdbException {
      // The mapping may already be absent after transport shutdown.
    }
    try {
      await adb.shell(device.id, const ['rm', '-f', remotePath]);
    } on AdbException {
      // Cleanup is best effort and never hides the primary test result.
    }
    await server.close();
  }
}

Future<void> _stopRemoteAgent(AdbClient adb, String deviceId) async {
  try {
    final processes = await adb.shell(deviceId, const [
      'ps',
      '-A',
      '-o',
      'PID,ARGS',
    ]);
    for (final line in processes.split('\n')) {
      if (!line.contains('io.github.shrey113.openandroiddex.agent.Main')) {
        continue;
      }
      final fields = line.trim().split(RegExp(r'\s+'));
      final pid = int.tryParse(fields.first);
      if (pid != null) {
        await adb.shell(deviceId, ['kill', pid.toString()]);
      }
    }
  } on AdbException {
    // The adb shell process normally tears down the remote process itself.
  }
}
