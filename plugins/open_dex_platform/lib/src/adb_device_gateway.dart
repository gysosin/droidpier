import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import 'adb_client.dart';
import 'process_executor.dart';

class AdbDeviceGateway
    implements DeviceGateway, WirelessDeviceGateway, WirelessPairingGateway {
  AdbDeviceGateway(this._adb);
  final AdbClient _adb;
  final _pending = <ProcessCancellation>{};

  @override
  Future<void> start() => _translate(_adb.startServer);
  @override
  Future<List<DeviceSummary>> discoverDevices() => _translate(_adb.listDevices);
  @override
  Future<DeviceSummary> prepareDevice(DeviceSummary device) async {
    final version = await _translate(
      () =>
          _adb.shell(device.id, const ['getprop', 'ro.build.version.release']),
    );
    return DeviceSummary(
      id: device.id,
      name: device.name,
      connectionKind: device.connectionKind,
      status: device.status,
      androidVersion: version.isEmpty ? null : version,
      model: device.model,
    );
  }

  @override
  Future<void> disconnectDevice(DeviceSummary device) async {
    for (final port in const [3698, 3699]) {
      try {
        await _adb.removeReverse(device.id, port);
      } on AdbException {
        /* Already absent. */
      }
    }
  }

  @override
  Future<void> pair({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) => _translate(
    () => _adb.pairWireless(_endpoint(host, pairingPort), pairingCode),
  );

  @override
  Future<String?> pairWithSecret({
    required String host,
    required int port,
    required String secret,
  }) async {
    final cancellation = ProcessCancellation();
    _pending.add(cancellation);
    try {
      return await _translate(
        () => _adb.pairWirelessSecret(
          _endpoint(host, port),
          secret,
          cancellation: cancellation,
        ),
      );
    } finally {
      _pending.remove(cancellation);
    }
  }

  @override
  Future<void> cancelPending() async {
    for (final pending in _pending.toList()) {
      pending.cancel();
    }
  }

  @override
  Future<DeviceSummary> connect({
    required String host,
    required int port,
  }) async {
    final address = _endpoint(host, port);
    final cancellation = ProcessCancellation();
    _pending.add(cancellation);
    try {
      await _translate(
        () => _adb.connectWireless(address, cancellation: cancellation),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!cancellation.isCancelled && DateTime.now().isBefore(deadline)) {
        final devices = await _translate(_adb.listDevices);
        if (cancellation.isCancelled) break;
        final matches = devices.where((device) => device.id == address);
        if (matches.isNotEmpty &&
            matches.first.status == DeviceStatus.authorized) {
          return matches.first;
        }
        if (matches.isNotEmpty &&
            matches.first.status == DeviceStatus.unauthorized) {
          throw const BackendFailure(
            OpenDexError(
              code: OpenDexErrorCode.deviceUnauthorized,
              message: 'This computer is not authorized. Pair this phone again in Wireless debugging.',
              wirelessReason: WirelessFailureReason.authorization,
              retryable: true,
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw BackendFailure(
        OpenDexError(
          code: cancellation.isCancelled
              ? OpenDexErrorCode.cancelled
              : OpenDexErrorCode.timeout,
          message: cancellation.isCancelled ? 'Wireless operation cancelled.' : 'The phone did not become available. Check its connection port.',
          wirelessReason: cancellation.isCancelled
              ? WirelessFailureReason.cancelled
              : WirelessFailureReason.timeout,
          retryable: !cancellation.isCancelled,
        ),
      );
    } finally {
      _pending.remove(cancellation);
    }
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
    if (error.operation.contains('wireless device')) {
      final WirelessFailureReason reason;
      final String message;
      if (error.cancelled) {
        reason = WirelessFailureReason.cancelled;
        message = 'Wireless operation cancelled.';
      } else if (error.timedOut) {
        reason = WirelessFailureReason.timeout;
        message = 'The phone did not respond in time. Keep its pairing screen open and check the address and port.';
      } else if (lower.contains('six digits') ||
          lower.contains('invalid') ||
          lower.contains('format')) {
        reason = WirelessFailureReason.invalidInput;
        message = 'Check the phone address, port, and six-digit pairing code.';
      } else if (lower.contains('password') ||
          lower.contains('pairing code') ||
          lower.contains('authentication')) {
        reason = WirelessFailureReason.rejected;
        message = 'Pairing was rejected or the connection dropped. Check the current code and keep the pairing screen open.';
      } else if (lower.contains('unauthorized')) {
        reason = WirelessFailureReason.authorization;
        message = 'This computer is not authorized. Pair the phone again.';
      } else if (lower.contains('connect') ||
          lower.contains('resolve') ||
          lower.contains('refused') ||
          lower.contains('route') ||
          lower.contains('pairing client')) {
        reason = WirelessFailureReason.unreachable;
        message = 'Could not reach that endpoint. Check the address, pairing versus connection port, and that both devices share a trusted network.';
      } else {
        reason = WirelessFailureReason.unexpectedResponse;
        message = 'ADB returned an unexpected pairing or connection response. Retry with the current phone details.';
      }
      return OpenDexError(
        code: error.cancelled
            ? OpenDexErrorCode.cancelled
            : error.timedOut
            ? OpenDexErrorCode.timeout
            : OpenDexErrorCode.connectionFailed,
        message: message,
        retryable: !error.cancelled,
        capability: 'wireless-connection',
        wirelessReason: reason,
        technicalDetails:
            'operation=${error.operation}; exit=${error.exitCode}; reason=${reason.name}',
      );
    }
    if (lower.contains('unauthorized')) {
      return const OpenDexError(
        code: OpenDexErrorCode.deviceUnauthorized,
        message: 'Authorize USB debugging on the Android device.',
        retryable: true,
      );
    }
    if (lower.contains('offline') || lower.contains('no devices')) {
      return const OpenDexError(
        code: OpenDexErrorCode.deviceOffline,
        message: 'The Android device is offline.',
        retryable: true,
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
      technicalDetails: 'operation=${error.operation}; exit=${error.exitCode}',
    );
  }

  static String _endpoint(String host, int port) {
    if (port < 1 || port > 65535 || host.trim().isEmpty) {
      throw const BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Wireless debugging requires a valid address and port.',
          wirelessReason: WirelessFailureReason.invalidInput,
        ),
      );
    }
    final normalized = host.trim();
    if (normalized.contains(':') && !normalized.startsWith('[')) {
      return '[$normalized]:$port';
    }
    return '$normalized:$port';
  }
}
