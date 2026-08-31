import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:open_dex_api/open_dex_api.dart';

import 'process_executor.dart';

class AdbException implements Exception {
  const AdbException({
    required this.operation,
    required this.message,
    this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
  });

  final String operation;
  final String message;
  final int? exitCode;
  final bool timedOut;
  final bool cancelled;

  @override
  String toString() => 'AdbException($operation): $message';
}

class AdbClient {
  AdbClient({
    this.executable = 'adb',
    ProcessExecutor? executor,
    this.timeout = const Duration(seconds: 15),
    this.installTimeout = const Duration(seconds: 60),
  }) : _executor = executor ?? const SystemProcessExecutor();

  final String executable;
  final Duration timeout;
  final Duration installTimeout;
  final ProcessExecutor _executor;

  Future<void> startServer() async {
    await _checked('start server', const ['start-server']);
  }

  Future<List<DeviceSummary>> listDevices() async {
    final output = await _checked('list devices', const ['devices', '-l']);
    return parseDevices(output.stdout);
  }

  Future<String> shell(String deviceId, List<String> command) async {
    _validateDeviceId(deviceId);
    if (command.isEmpty) {
      throw const AdbException(
        operation: 'shell',
        message: 'A shell command is required.',
      );
    }
    final output = await _checked('device shell', [
      '-s',
      deviceId,
      'shell',
      ...command,
    ]);
    return output.stdout.trimRight();
  }

  Future<void> push(
    String deviceId,
    String localPath,
    String remotePath,
  ) async {
    _validateDeviceId(deviceId);
    await _checked('push artifact', [
      '-s',
      deviceId,
      'push',
      localPath,
      remotePath,
    ]);
  }

  Future<void> stopServiceIfRunning(String deviceId, String component) async {
    try {
      await shell(deviceId, ['am', 'stopservice', '-n', component]);
    } on AdbException catch (error) {
      // Android 13 and some OEM builds return 255 for an already stopped service.
      // Only that exact benign outcome is idempotent; permission failures matter.
      if (!error.timedOut &&
          RegExp(
            r'(^|\n)(Service not stopped: was not running\.|Service stopped)(\r?\n|$)',
          ).hasMatch(error.message)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> install(String deviceId, String apkPath) async {
    _validateDeviceId(deviceId);
    try {
      await _checked('install companion', [
        '-s',
        deviceId,
        'install',
        '-r',
        apkPath,
      ], operationTimeout: installTimeout);
    } on AdbException catch (error) {
      if (error.message.contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE') ||
          error.message.contains('signatures do not match')) {
        throw AdbException(
          operation: 'install companion',
          message:
              'A companion signed with a different key is already installed. '
              'To switch from a development build, uninstall the old companion '
              'yourself in Android Settings, then reconnect. This removes its '
              'local settings and requires granting notification access again. '
              'DroidPier will not uninstall it automatically.',
          exitCode: error.exitCode,
        );
      }
      rethrow;
    }
  }

  Future<void> reverse(
    String deviceId, {
    required int devicePort,
    required int hostPort,
  }) async {
    _validateDeviceId(deviceId);
    _validatePort(devicePort);
    _validatePort(hostPort);
    await _checked('create reverse tunnel', [
      '-s',
      deviceId,
      'reverse',
      'tcp:$devicePort',
      'tcp:$hostPort',
    ]);
  }

  Future<void> removeReverse(String deviceId, int devicePort) async {
    _validateDeviceId(deviceId);
    _validatePort(devicePort);
    await _checked('remove reverse tunnel', [
      '-s',
      deviceId,
      'reverse',
      '--remove',
      'tcp:$devicePort',
    ]);
  }

  Future<void> reverseAbstract(
    String deviceId, {
    required String deviceSocket,
    required int hostPort,
  }) async {
    _validateDeviceId(deviceId);
    _validateAbstractSocket(deviceSocket);
    _validatePort(hostPort);
    await _checked('create reverse tunnel', [
      '-s',
      deviceId,
      'reverse',
      'localabstract:$deviceSocket',
      'tcp:$hostPort',
    ]);
  }

  Future<void> removeReverseByName(String deviceId, String deviceSocket) async {
    _validateDeviceId(deviceId);
    _validateAbstractSocket(deviceSocket);
    await _checked('remove reverse tunnel', [
      '-s',
      deviceId,
      'reverse',
      '--remove',
      'localabstract:$deviceSocket',
    ]);
  }

  Future<void> connectWireless(
    String address, {
    ProcessCancellation? cancellation,
  }) async {
    _validateWireless(address);
    final output = await _checked(
      'connect wireless device',
      ['connect', address],
      operationTimeout: const Duration(seconds: 30),
      cancellation: cancellation,
    );
    if (!RegExp(
      r'(^|\n)(already )?connected to ',
      caseSensitive: false,
    ).hasMatch(output.stdout.trim())) {
      throw AdbException(
        operation: 'connect wireless device',
        message: output.stdout.trim(),
      );
    }
  }

  Future<void> pairWireless(String address, String pairingCode) async {
    if (!_pairingCode.hasMatch(pairingCode)) {
      throw const AdbException(
        operation: 'pair wireless device',
        message: 'The pairing code must contain six digits.',
      );
    }
    await pairWirelessSecret(address, pairingCode);
  }

  Future<String?> pairWirelessSecret(
    String address,
    String secret, {
    ProcessCancellation? cancellation,
  }) async {
    _validateWireless(address);
    if (secret.isEmpty ||
        secret.length > 256 ||
        secret.contains(RegExp(r'[\x00-\x20;:]'))) {
      throw const AdbException(
        operation: 'pair wireless device',
        message: 'The pairing secret is invalid.',
      );
    }
    final output = await _checked(
      'pair wireless device',
      ['pair', address],
      input: '$secret\n',
      operationTimeout: const Duration(seconds: 30),
      cancellation: cancellation,
    );
    if (!RegExp(r'(^|\n|Enter pairing code: )Successfully paired(?: to |\s|$)')
        .hasMatch(output.stdout.trim())) {
      throw AdbException(
        operation: 'pair wireless device',
        message: output.stdout.replaceAll(secret, '[redacted]').trim(),
      );
    }
    return RegExp(r'\[guid=([^\]\s]+)\]').firstMatch(output.stdout)?.group(1);
  }

  Future<void> disconnectWireless(String address) async {
    _validateWireless(address);
    await _checked('disconnect wireless device', ['disconnect', address]);
  }

  static void _validateWireless(String address) {
    if (!_wirelessAddress.hasMatch(address) ||
        int.parse(address.split(':').last) < 1 ||
        int.parse(address.split(':').last) > 65535) {
      throw const AdbException(
        operation: 'connect wireless device',
        message: 'Wireless address must use a valid host:port format.',
      );
    }
  }

  /// Reuse only a byte-identical installed APK; package/version alone is not enough.
  Future<bool> installIfNeeded(
    String deviceId,
    String apkPath,
    String packageName,
  ) async {
    try {
      final paths = await shell(deviceId, ['pm', 'path', packageName]);
      final candidates = paths
          .split('\n')
          .where((p) => p.startsWith('package:'));
      if (candidates.length == 1) {
        final remote = candidates.single.substring(8).trim();
        if (RegExp(r'^/data/app/[A-Za-z0-9_./=+~-]+\.apk$').hasMatch(remote)) {
          final sum = await shell(deviceId, ['sha256sum', remote]);
          final expected = await sha256.bind(File(apkPath).openRead()).first;
          if (sum.split(RegExp(r'\s+')).first == expected.toString()) {
            return false;
          }
        }
      }
    } on AdbException {
      // Unsupported checksum commands or unreadable package paths require normal installation.
    }
    await install(deviceId, apkPath);
    return true;
  }

  Future<ProcessOutput> _checked(
    String operation,
    List<String> arguments, {
    Duration? operationTimeout,
    String? input,
    ProcessCancellation? cancellation,
  }) async {
    final executor = _executor;
    final output = executor is CancellableProcessExecutor
        ? await (executor as CancellableProcessExecutor).runCancellable(
            executable,
            arguments,
            timeout: operationTimeout ?? timeout,
            input: input,
            cancellation: cancellation,
          )
        : await executor.run(
            executable,
            arguments,
            timeout: operationTimeout ?? timeout,
            input: input,
          );
    if (!output.succeeded) {
      final rawDiagnostic = output.stderr.trim().isNotEmpty
          ? output.stderr.trim()
          : output.stdout.trim();
      final diagnostic = input == null
          ? rawDiagnostic
          : rawDiagnostic.replaceAll(input.trim(), '[redacted]');
      throw AdbException(
        operation: operation,
        message: output.timedOut
            ? 'The operation timed out.'
            : diagnostic.isEmpty
            ? 'ADB exited without an error message.'
            : diagnostic,
        exitCode: output.exitCode,
        timedOut: output.timedOut,
        cancelled: output.cancelled,
      );
    }
    return output;
  }

  static List<DeviceSummary> parseDevices(String output) {
    final devices = <DeviceSummary>[];
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('List of devices')) {
        continue;
      }
      final fields = line.split(RegExp(r'\s+'));
      if (fields.length < 2) {
        continue;
      }
      final id = fields.first;
      final status = switch (fields[1]) {
        'device' => DeviceStatus.authorized,
        'unauthorized' => DeviceStatus.unauthorized,
        _ => DeviceStatus.offline,
      };
      final attributes = <String, String>{};
      for (final field in fields.skip(2)) {
        final separator = field.indexOf(':');
        if (separator > 0 && separator < field.length - 1) {
          attributes[field.substring(0, separator)] = field.substring(
            separator + 1,
          );
        }
      }
      final model = attributes['model']?.replaceAll('_', ' ');
      devices.add(
        DeviceSummary(
          id: id,
          name:
              model ??
              (id.contains(':')
                  ? 'Android device over Wi-Fi'
                  : 'Android device'),
          model: attributes['device'],
          connectionKind: id.contains(':')
              ? DeviceConnectionKind.wifi
              : DeviceConnectionKind.usb,
          status: status,
        ),
      );
    }
    return devices;
  }

  static void _validateDeviceId(String value) {
    if (value.isEmpty || value.contains(RegExp(r'[\x00-\x20]'))) {
      throw const AdbException(
        operation: 'select device',
        message: 'The device identifier is invalid.',
      );
    }
  }

  static void _validatePort(int value) {
    if (value < 1 || value > 65535) {
      throw const AdbException(
        operation: 'configure port',
        message: 'Port must be between 1 and 65535.',
      );
    }
  }

  static void _validateAbstractSocket(String value) {
    if (!_abstractSocket.hasMatch(value)) {
      throw const AdbException(
        operation: 'configure reverse socket',
        message: 'The Android abstract socket name is invalid.',
      );
    }
  }

  static final _wirelessAddress = RegExp(
    r'^(?:\[[0-9a-fA-F:]+(?:%[A-Za-z0-9_.-]+)?\]|[A-Za-z0-9.-]+):[0-9]{1,5}$',
  );
  static final _pairingCode = RegExp(r'^\d{6}$');
  static final _abstractSocket = RegExp(r'^[A-Za-z0-9._-]{1,108}$');
}
