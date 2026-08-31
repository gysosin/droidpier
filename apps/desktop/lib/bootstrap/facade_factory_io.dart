import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

import 'linux_texture_host.dart';
import 'runtime_resources.dart';
import 'window_backend_selection.dart';

OpenDexFacade createFacade() => _createFacade();

OpenDexFacade createBenchmarkFacade({
  required List<AndroidApplication> additionalApplications,
  required Future<void> Function(DeviceSummary device, int displayId)
  onDisplayCreated,
}) => _createFacade(
  additionalApplications: additionalApplications,
  onDisplayCreated: onDisplayCreated,
);

OpenDexFacade _createFacade({
  List<AndroidApplication> additionalApplications = const [],
  Future<void> Function(DeviceSummary device, int displayId)? onDisplayCreated,
}) {
  final scenario = _scenarioFromEnvironment();
  if (scenario != null) return MockOpenDexFacade(scenario: scenario);

  final scrcpyDirectory = _scrcpyDirectory();
  final adb = AdbClient(executable: _adbExecutable(scrcpyDirectory));
  final token = SessionToken.generate();
  final agent = AgentBootComponent(
    adb: adb,
    sessionToken: token,
    agentJarPath: _artifactPath(
      environmentKey: 'OPEN_DEX_AGENT_JAR',
      repositoryPath: 'android/agent/build/outputs/open-dex-agent.jar',
    ),
  );
  final companion = CompanionBootComponent(
    adb: adb,
    sessionToken: token,
    companionApkPath: _artifactPath(
      environmentKey: 'OPEN_DEX_COMPANION_APK',
      repositoryPath:
          'android/companion/build/outputs/apk/debug/companion-debug.apk',
    ),
  );
  final clipboard = AgentClipboardBootComponent(agent: agent);
  final commands = AgentCommandGateway(agent);
  final applicationCatalog = ApplicationCatalogBootComponent(agent: agent);
  const textureHost = LinuxTextureHost();
  final ffmpegExecutable = _ffmpegExecutable();
  final WindowGateway windowGateway = switch (resolveWindowBackend(
    Platform.environment,
    linux: Platform.isLinux,
  )) {
    WindowBackendSelection.legacy => EmbeddedScrcpyWindowGateway(
      executable: '$scrcpyDirectory/${_runtimeExecutableName('scrcpy')}',
      serverPath: '$scrcpyDirectory/scrcpy-server',
      ffmpegExecutable: ffmpegExecutable,
      adb: adb,
      textureHost: textureHost,
      onDisplayCreated: onDisplayCreated,
    ),
    WindowBackendSelection.direct => DirectScrcpyWindowGateway(
      serverStarter: ScrcpyServerLauncher(adb: adb),
      decoderStarter: const SystemH264DecoderStarter(),
      serverJarPath: '$scrcpyDirectory/scrcpy-server',
      ffmpegExecutable: ffmpegExecutable,
      textureHost: textureHost,
      // Lets the gateway read the phone's natural orientation once so a new
      // window opens upright rather than rotated inside a landscape display.
      adb: adb,
      onDisplayCreated: onDisplayCreated,
    ),
  };
  return OpenDexController(
    deviceGateway: AdbDeviceGateway(adb),
    wirelessDiscoveryGateway: MdnsWirelessDiscovery(),
    components: [
      agent,
      companion,
      if (additionalApplications.isEmpty)
        applicationCatalog
      else
        _AugmentedApplicationCatalog(
          delegate: applicationCatalog,
          additionalApplications: additionalApplications,
        ),
      clipboard,
    ],
    windowGateway: windowGateway,
    deviceCommandGateway: commands,
    permissionGateway: commands,
    notificationGateway: companion,
    clipboardGateway: clipboard,
  );
}

class _AugmentedApplicationCatalog
    implements BootComponent, ApplicationCatalogProvider {
  _AugmentedApplicationCatalog({
    required this.delegate,
    required this.additionalApplications,
  });

  final ApplicationCatalogBootComponent delegate;
  final List<AndroidApplication> additionalApplications;
  List<AndroidApplication> _applications = const [];

  @override
  String get stageId => delegate.stageId;

  @override
  List<AndroidApplication> get applications => _applications;

  @override
  Future<void> start(DeviceSummary device) async {
    await delegate.start(device);
    final merged = <String, AndroidApplication>{
      for (final application in delegate.applications)
        application.packageName: application,
      for (final application in additionalApplications)
        application.packageName: application,
    };
    _applications = List.unmodifiable(merged.values);
  }

  @override
  Future<void> stop(DeviceSummary device) async {
    _applications = const [];
    await delegate.stop(device);
  }
}

String _adbExecutable(String scrcpyDirectory) {
  final override = Platform.environment['ADB_PATH'];
  if (override != null && override.trim().isNotEmpty) {
    return File(override).absolute.path;
  }

  final packaged = findRuntimeFile(
    'resources/scrcpy/${_runtimeExecutableName('adb')}',
  );
  if (packaged != null) return packaged.path;
  final sourceTreeAdb = File(
    '$scrcpyDirectory/${_runtimeExecutableName('adb')}',
  );
  return sourceTreeAdb.existsSync() ? sourceTreeAdb.path : 'adb';
}

MockScenario? _scenarioFromEnvironment() {
  const name = String.fromEnvironment('OPEN_DEX_SCENARIO');
  if (name.isEmpty) return null;
  for (final scenario in MockScenario.values) {
    if (scenario.name == name) return scenario;
  }
  return MockScenario.disconnected;
}

String _artifactPath({
  required String environmentKey,
  required String repositoryPath,
}) {
  final override = Platform.environment[environmentKey];
  if (override != null && override.trim().isNotEmpty) {
    return File(override).absolute.path;
  }

  final packagedPath = switch (environmentKey) {
    'OPEN_DEX_AGENT_JAR' => 'resources/android/open-dex-agent.jar',
    'OPEN_DEX_COMPANION_APK' => 'resources/android/companion.apk',
    _ => null,
  };
  if (packagedPath != null) {
    final candidate = findRuntimeFile(packagedPath);
    if (candidate != null) return candidate.path;
  }

  for (final directory in _ancestorDirectories()) {
    final candidate = File('${directory.path}/$repositoryPath');
    if (candidate.existsSync()) return candidate.path;
  }
  return File(repositoryPath).absolute.path;
}

String _scrcpyDirectory() {
  final override = Platform.environment['OPEN_DEX_SCRCPY_DIR'];
  if (override != null && override.trim().isNotEmpty) {
    return Directory(override).absolute.path;
  }

  final packaged = findRuntimeDirectory(
    'resources/scrcpy',
    requiredFiles: [_runtimeExecutableName('scrcpy'), 'scrcpy-server'],
  );
  if (packaged != null) return packaged.path;

  for (final directory in _ancestorDirectories()) {
    final candidate = Directory('${directory.path}/.tools/scrcpy-v4.1');
    if (File('${candidate.path}/scrcpy').existsSync()) return candidate.path;
  }
  return Directory('scrcpy-v4.1').absolute.path;
}

Iterable<Directory> _ancestorDirectories() sync* {
  final seen = <String>{};
  for (final start in [
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ]) {
    var directory = start.absolute;
    while (seen.add(directory.path)) {
      yield directory;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
}

String _ffmpegExecutable() {
  final override = Platform.environment['OPEN_DEX_FFMPEG'];
  if (override != null && override.trim().isNotEmpty) {
    return File(override).absolute.path;
  }
  final packaged = findRuntimeFile(
    'resources/ffmpeg/${_runtimeExecutableName('ffmpeg')}',
  );
  if (packaged != null) return packaged.path;
  final fromPath = findExecutableOnPath(_runtimeExecutableName('ffmpeg'));
  if (fromPath != null) return fromPath.path;
  for (final path in const ['/usr/bin/ffmpeg', '/usr/local/bin/ffmpeg']) {
    if (File(path).existsSync()) return path;
  }
  return '/usr/bin/ffmpeg';
}

String _runtimeExecutableName(String baseName) =>
    Platform.isWindows ? '$baseName.exe' : baseName;
