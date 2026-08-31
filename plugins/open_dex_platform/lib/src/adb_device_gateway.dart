import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import 'adb_client.dart';

class AdbDeviceGateway implements DeviceGateway, WirelessDeviceGateway {
  AdbDeviceGateway(this._adb);

  final AdbClient _adb;

  @override
  Future<void> start() => _translate(_adb.startServer);

  @override
  Future<List<DeviceSummary>> discoverDevices() => _translate(_adb.listDevices);

  @override
  Future<DeviceSummary> prepareDevice(DeviceSummary device) async {
    try {
      final androidVersion = await _adb.shell(device.id, const [
        'getprop',
        'ro.build.version.release',
      ]);
      return DeviceSummary(
        id: device.id,
        name: device.name,
        connectionKind: device.connectionKind,
        status: device.status,
        androidVersion: androidVersion.isEmpty ? null : androidVersion,
        model: device.model,
      );
    } on AdbException catch (error) {
      throw BackendFailure(_mapError(error));
    }
  }

  @override
  Future<void> disconnectDevice(DeviceSummary device) async {
    for (final port in const [3698, 3699]) {
      try {
        await _adb.removeReverse(device.id, port);
      } on AdbException {
        // Reverse mappings may already be absent after a cable disconnect.
      }
    }
  }

  @override
  Future<void> pair({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) => _translate(
    () => _adb.pairWireless(_wirelessEndpoint(host, pairingPort), pairingCode),
  );

  @override
  Future<DeviceSummary> connect({
    required String host,
    required int port,
  }) async {
    final address = _wirelessEndpoint(host, port);
    await _translate(() => _adb.connectWireless(address));
    final devices = await _translate(_adb.listDevices);
    final matches = devices.where((device) => device.id == address);
    if (matches.isEmpty || matches.single.status != DeviceStatus.authorized) {
      throw const BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'ADB paired but could not connect to the wireless device.',
          retryable: true,
          capability: 'wireless-connection',
        ),
      );
    }
    return matches.single;
  }

  @override
  Future<void> forget(String deviceId) =>
      _translate(() => _adb.disconnectWireless(deviceId));

  static Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AdbException catch (error) {
      throw BackendFailure(_mapError(error));
    }
  }

  static OpenDexError _mapError(AdbException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('unauthorized')) {
      return OpenDexError(
        code: OpenDexErrorCode.deviceUnauthorized,
        message: 'Authorize USB debugging on the Android device.',
        retryable: true,
        technicalDetails: error.toString(),
      );
    }
    if (lower.contains('offline') || lower.contains('no devices')) {
      return OpenDexError(
        code: OpenDexErrorCode.deviceOffline,
        message: 'The Android device is offline.',
        retryable: true,
        technicalDetails: error.toString(),
      );
    }
    if (error.operation.contains('wireless device')) {
      final message = switch (error.operation) {
        final operation when operation.startsWith('pair') =>
          'ADB could not pair with the wireless device.',
        final operation when operation.startsWith('disconnect') =>
          'ADB could not forget the wireless device.',
        _ => 'ADB could not connect to the wireless device.',
      };
      return OpenDexError(
        code: OpenDexErrorCode.connectionFailed,
        message: message,
        retryable: true,
        capability: 'wireless-connection',
        technicalDetails: error.toString(),
      );
    }
    return OpenDexError(
      code: error.timedOut
          ? OpenDexErrorCode.timeout
          : OpenDexErrorCode.adbUnavailable,
      message: error.timedOut
          ? 'ADB did not respond in time.'
          : 'DroidPier could not communicate with ADB.',
      retryable: true,
      technicalDetails: error.toString(),
    );
  }

  static String _wirelessEndpoint(String host, int port) {
    if (port < 1 || port > 65535) {
      throw const BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Wireless debugging requires a valid port.',
          capability: 'wireless-connection',
        ),
      );
    }
    final normalized = host.trim();
    if (normalized.contains(':') &&
        !normalized.startsWith('[') &&
        !normalized.endsWith(']')) {
      return '[$normalized]:$port';
    }
    return '$normalized:$port';
  }
}
