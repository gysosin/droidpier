import 'models.dart';
import 'result.dart';

enum WirelessServiceKind { pairing, connection }

enum WirelessDiscoveryStatus { idle, searching, ready, unavailable }

/// An advertisement is a discovery hint, never proof of identity or trust.
class WirelessAdvertisement {
  const WirelessAdvertisement({
    required this.serviceName,
    required this.kind,
    required this.host,
    required this.port,
    required this.expiresAt,
    this.displayName,
  });

  final String serviceName;
  final WirelessServiceKind kind;
  final String host;
  final int port;
  final DateTime expiresAt;
  final String? displayName;
  String get id => '$serviceName|${kind.name}|$host';
}

class WirelessDiscoveryState {
  const WirelessDiscoveryState({
    this.status = WirelessDiscoveryStatus.idle,
    this.devices = const [],
    this.message,
  });

  final WirelessDiscoveryStatus status;
  final List<WirelessAdvertisement> devices;
  final String? message;
}

enum WirelessPairingPhase {
  idle,
  waitingForScan,
  pairing,
  findingConnection,
  needsConnectionPort,
  connected,
  failed,
  expired,
}

/// QR payloads are ephemeral secrets. Never log, persist or export this state.
class WirelessPairingState {
  const WirelessPairingState({
    this.phase = WirelessPairingPhase.idle,
    this.qrPayload,
    this.expiresAt,
    this.host,
    this.device,
    this.error,
  });

  final WirelessPairingPhase phase;
  final String? qrPayload;
  final DateTime? expiresAt;
  final String? host;
  final DeviceSummary? device;
  final OpenDexError? error;
}

enum WirelessFailureReason {
  invalidInput,
  unreachable,
  rejected,
  authorization,
  discoveryUnavailable,
  unexpectedResponse,
  timeout,
  cancelled,
}
