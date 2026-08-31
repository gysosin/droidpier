import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:open_dex_api/open_dex_api.dart';

import 'backend_ports.dart';

/// Owns short-lived discovery and pairing; advertisements are never trust.
class WirelessCoordinator {
  WirelessCoordinator({
    required this.gateway,
    required this.discovery,
    required this.onDiscovery,
    required this.onPairing,
    required this.onConnected,
    this.qrLifetime = const Duration(minutes: 2),
    this.resolveTimeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final WirelessDeviceGateway gateway;
  final WirelessDiscoveryGateway? discovery;
  final void Function(WirelessDiscoveryState) onDiscovery;
  final void Function(WirelessPairingState) onPairing;
  final void Function(DeviceSummary) onConnected;
  final Duration qrLifetime;
  final Duration resolveTimeout;
  final DateTime Function() clock;
  StreamSubscription<WirelessDiscoveryState>? _subscription;
  Timer? _expiry;
  int _epoch = 0;
  String? _qrName;
  String? _secret;
  bool _started = false;
  bool _startingQr = false;

  Future<VoidResult> start() async {
    if (_started) return const CommandSuccess(null);
    final source = discovery;
    if (source == null) {
      onDiscovery(
        const WirelessDiscoveryState(
          status: WirelessDiscoveryStatus.unavailable,
          message: 'Nearby discovery is unavailable. Use manual pairing.',
        ),
      );
      return const CommandSuccess(null);
    }
    _started = true;
    _subscription = source.updates.listen(_acceptDiscovery);
    try {
      await source.start();
      if (_started) _acceptDiscovery(source.current);
      return const CommandSuccess(null);
    } on Object {
      onDiscovery(
        const WirelessDiscoveryState(
          status: WirelessDiscoveryStatus.unavailable,
          message:
              'Local discovery could not start. Check network permissions or use manual pairing.',
        ),
      );
      return const CommandSuccess(null);
    }
  }

  void _acceptDiscovery(WirelessDiscoveryState state) {
    if (!_started) return;
    onDiscovery(state);
    final name = _qrName;
    final secret = _secret;
    if (name == null || secret == null) return;
    final matches = state.devices.where(
      (d) =>
          d.kind == WirelessServiceKind.pairing &&
          d.serviceName.split('._').first == name &&
          d.expiresAt.isAfter(clock()),
    );
    if (matches.isEmpty) return;
    final candidates = matches.toList()
      ..sort(
        (a, b) => (a.host.contains(':') ? 1 : 0).compareTo(
          b.host.contains(':') ? 1 : 0,
        ),
      );
    final device = candidates.first;
    _qrName = null;
    _secret = null;
    _expiry?.cancel();
    final epoch = _epoch;
    unawaited(_pair(device.host, device.port, secret, epoch, qr: true));
  }

  Future<VoidResult> startQr() async {
    // Serialize a rapid double-click so only one live secret can survive.
    if (_startingQr) return const CommandSuccess(null);
    _startingQr = true;
    try {
      await cancel();
      final epoch = _epoch;
      await start();
      if (epoch != _epoch) return _cancelled();
      if (gateway is! WirelessPairingGateway ||
          discovery == null ||
          discovery!.current.status == WirelessDiscoveryStatus.unavailable) {
        return _fail(
          const OpenDexError(
            code: OpenDexErrorCode.capabilityUnavailable,
            message:
                'QR pairing needs local discovery. Use manual pairing on this network.',
            wirelessReason: WirelessFailureReason.discoveryUnavailable,
          ),
        );
      }
      final random = Random.secure();
      String token(int length) => base64UrlEncode(
        List.generate(length, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      _qrName = 'studio-${token(12)}';
      _secret = token(24);
      onPairing(
        WirelessPairingState(
          phase: WirelessPairingPhase.waitingForScan,
          qrPayload: 'WIFI:T:ADB;S:$_qrName;P:$_secret;;',
          expiresAt: clock().add(qrLifetime),
        ),
      );
      _expiry = Timer(qrLifetime, () {
        if (_epoch != epoch) return;
        _epoch++;
        _qrName = null;
        _secret = null;
        onPairing(
          const WirelessPairingState(phase: WirelessPairingPhase.expired),
        );
      });
      return const CommandSuccess(null);
    } finally {
      _startingQr = false;
    }
  }

  Future<VoidResult> pairManual({
    required String host,
    required int port,
    required String code,
  }) async {
    await cancel();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return _fail(
        const OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Enter the six-digit pairing code shown on the phone.',
          wirelessReason: WirelessFailureReason.invalidInput,
        ),
      );
    }
    return _pair(host, port, code, _epoch);
  }

  Future<VoidResult> _pair(
    String host,
    int port,
    String secret,
    int epoch, {
    bool qr = false,
  }) async {
    onPairing(
      WirelessPairingState(phase: WirelessPairingPhase.pairing, host: host),
    );
    try {
      String? guid;
      final pairing = gateway;
      if (pairing is WirelessPairingGateway) {
        guid = await (pairing as WirelessPairingGateway).pairWithSecret(
          host: host,
          port: port,
          secret: secret,
        );
      } else {
        await gateway.pair(host: host, pairingPort: port, pairingCode: secret);
      }
      if (epoch != _epoch) return _cancelled();
      onPairing(
        WirelessPairingState(
          phase: WirelessPairingPhase.findingConnection,
          host: host,
        ),
      );
      final deadline = clock().add(resolveTimeout);
      WirelessAdvertisement? endpoint;
      while (_started && discovery != null && clock().isBefore(deadline)) {
        if (epoch != _epoch) return _cancelled();
        final matches = discovery!.current.devices.where((device) {
          if (device.kind != WirelessServiceKind.connection ||
              !device.expiresAt.isAfter(clock())) {
            return false;
          }
          final name = device.serviceName.split('._').first;
          if (guid != null && guid.isNotEmpty) {
            return name == guid ||
                name == 'adb-$guid' ||
                name.startsWith('$guid-') ||
                name.startsWith('adb-$guid-');
          }
          return !qr && device.host == host;
        }).toList();
        if (matches.isNotEmpty &&
            matches.map((d) => d.serviceName).toSet().length == 1) {
          matches.sort(
            (a, b) => (a.host.contains(':') ? 1 : 0).compareTo(
              b.host.contains(':') ? 1 : 0,
            ),
          );
          endpoint = matches.first;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (epoch != _epoch) return _cancelled();
      if (endpoint == null) {
        onPairing(
          WirelessPairingState(
            phase: WirelessPairingPhase.needsConnectionPort,
            host: host,
          ),
        );
        return const CommandSuccess(null);
      }
      final device = await gateway.connect(
        host: endpoint.host,
        port: endpoint.port,
      );
      if (epoch != _epoch) return _cancelled();
      onConnected(device);
      onPairing(
        WirelessPairingState(
          phase: WirelessPairingPhase.connected,
          device: device,
          host: endpoint.host,
        ),
      );
      return const CommandSuccess(null);
    } on BackendFailure catch (error) {
      if (epoch != _epoch) return _cancelled();
      return _fail(error.error, host: host);
    } on Object {
      if (epoch != _epoch) return _cancelled();
      return _fail(
        const OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message:
              'Wireless pairing failed unexpectedly. Retry or use the manual connection port.',
          wirelessReason: WirelessFailureReason.unexpectedResponse,
          retryable: true,
        ),
        host: host,
      );
    }
  }

  Future<CommandResult<DeviceSummary>> connect({
    required String host,
    required int port,
  }) async {
    await cancel();
    final epoch = _epoch;
    try {
      final device = await gateway.connect(host: host, port: port);
      if (epoch != _epoch) return CommandFailure(_cancelError);
      onConnected(device);
      onPairing(
        WirelessPairingState(
          phase: WirelessPairingPhase.connected,
          host: host,
          device: device,
        ),
      );
      return CommandSuccess(device);
    } on BackendFailure catch (failure) {
      if (epoch != _epoch) return CommandFailure(_cancelError);
      _fail(failure.error, host: host);
      return CommandFailure(failure.error);
    } on Object {
      const error = OpenDexError(
        code: OpenDexErrorCode.connectionFailed,
        message:
            'The wireless connection failed. Check the connection address and retry.',
        wirelessReason: WirelessFailureReason.unexpectedResponse,
        retryable: true,
      );
      if (epoch == _epoch) _fail(error, host: host);
      return const CommandFailure(error);
    }
  }

  Future<VoidResult> cancel() async {
    _epoch++;
    _expiry?.cancel();
    _expiry = null;
    _qrName = null;
    _secret = null;
    onPairing(const WirelessPairingState());
    final pairing = gateway;
    if (pairing is WirelessPairingGateway) {
      await (pairing as WirelessPairingGateway).cancelPending();
    }
    return const CommandSuccess(null);
  }

  Future<VoidResult> stop() async {
    _started = false;
    await cancel();
    await _subscription?.cancel();
    _subscription = null;
    await discovery?.stop();
    onDiscovery(const WirelessDiscoveryState());
    return const CommandSuccess(null);
  }

  VoidResult _fail(OpenDexError error, {String? host}) {
    onPairing(
      WirelessPairingState(
        phase: WirelessPairingPhase.failed,
        host: host,
        error: error,
      ),
    );
    return CommandFailure(error);
  }

  static const _cancelError = OpenDexError(
    code: OpenDexErrorCode.cancelled,
    message: 'Wireless operation cancelled.',
    wirelessReason: WirelessFailureReason.cancelled,
  );
  static VoidResult _cancelled() => const CommandFailure(_cancelError);
}
