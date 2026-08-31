import 'package:open_dex_api/open_dex_api.dart';

import 'process_executor.dart';

class AdbException implements Exception {
  const AdbException({
    required this.operation,
    required this.message,
    this.exitCode,
    this.timedOut = false,
  });

  final String operation;
  final String message;
  final int? exitCode;
  final bool timedOut;

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

  Future<void> connectWireless(String address) async {
    if (!_wirelessAddress.hasMatch(address)) {
      throw const AdbException(
        operation: 'connect wireless device',
        message: 'Wireless address must use host:port format.',
      );
    }
    await _checked('connect wireless device', ['connect', address]);
  }

  Future<void> pairWireless(String address, String pairingCode) async {
    if (!_wirelessAddress.hasMatch(address)) {
      throw const AdbException(
        operation: 'pair wireless device',
        message: 'Wireless address must use host:port format.',
      );
    }
    if (!_pairingCode.hasMatch(pairingCode)) {
      throw const AdbException(
        operation: 'pair wireless device',
        message: 'The pairing code must contain six digits.',
      );
    }
    await _checked('pair wireless device', [
      'pair',
      address,
    ], input: '$pairingCode\n');
  }

  Future<void> disconnectWireless(String address) async {
    if (!_wirelessAddress.hasMatch(address)) {
      throw const AdbException(
        operation: 'disconnect wireless device',
        message: 'Wireless address must use host:port format.',
      );
    }
    await _checked('disconnect wireless device', ['disconnect', address]);
  }

  Future<ProcessOutput> _checked(
    String operation,
    List<String> arguments, {
    Duration? operationTimeout,
    String? input,
  }) async {
    final output = await _executor.run(
      executable,
      arguments,
      timeout: operationTimeout ?? timeout,
      input: input,
    );
    if (!output.succeeded) {
      final diagnostic = output.stderr.trim().isNotEmpty
          ? output.stderr.trim()
          : output.stdout.trim();
      throw AdbException(
        operation: operation,
        message: output.timedOut
            ? 'The operation timed out.'
            : diagnostic.isEmpty
            ? 'ADB exited without an error message.'
            : diagnostic,
        exitCode: output.exitCode,
        timedOut: output.timedOut,
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
    r'^(?:\[[0-9a-fA-F:]+\]|[A-Za-z0-9.-]+):[0-9]{1,5}$',
  );
  static final _pairingCode = RegExp(r'^\d{6}$');
  static final _abstractSocket = RegExp(r'^[A-Za-z0-9._-]{1,108}$');
}
