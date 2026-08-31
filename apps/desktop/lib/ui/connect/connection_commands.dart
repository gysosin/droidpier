import 'package:open_dex_api/open_dex_api.dart';

/// Every command the connection screen is allowed to issue, bound once.
///
/// The screen never holds an [OpenDexFacade]. It holds this, which is the only
/// place the wireless half of the contract is called from — so the surface has
/// no route to ADB, a socket, or a platform channel, and a test can drive the
/// same widget with recorded calls instead of a device.
///
/// Every command that can fail returns the facade's own [OpenDexError] rather
/// than a bool or a thrown object. The screen shows [OpenDexError.message] and
/// nothing else: [OpenDexError.technicalDetails] is for logs and must never
/// reach the tree.
class ConnectionCommands {
  const ConnectionCommands({
    required this.startDiscovery,
    required this.stopDiscovery,
    required this.startQrPairing,
    required this.cancelPairing,
    required this.pair,
    required this.connect,
    required this.disconnectWireless,
  });

  /// Binds to the real contract. The one seam between this surface and the
  /// backend.
  factory ConnectionCommands.forFacade(OpenDexFacade facade) {
    return ConnectionCommands(
      startDiscovery: () async =>
          errorOf(await facade.startWirelessDiscovery()),
      stopDiscovery: () async => errorOf(await facade.stopWirelessDiscovery()),
      startQrPairing: () async => errorOf(await facade.startQrPairing()),
      cancelPairing: () async => errorOf(await facade.cancelWirelessPairing()),
      pair:
          ({
            required String host,
            required int pairingPort,
            required String pairingCode,
          }) async => errorOf(
            await facade.pairWirelessDevice(
              host: host,
              pairingPort: pairingPort,
              pairingCode: pairingCode,
            ),
          ),
      connect: ({required String host, required int port}) =>
          facade.connectWirelessDevice(host: host, port: port),
      disconnectWireless: (String deviceId) async =>
          errorOf(await facade.forgetWirelessDevice(deviceId)),
    );
  }

  /// Begins listening for advertisements. Started when the screen opens.
  final Future<OpenDexError?> Function() startDiscovery;

  /// Stops listening. Also cancels any pairing in flight, per the contract.
  final Future<OpenDexError?> Function() stopDiscovery;

  /// Asks the backend for a pairing QR payload. The payload itself arrives on
  /// the snapshot, lives only while the phase is `waitingForScan`, and is never
  /// copied out of it.
  final Future<OpenDexError?> Function() startQrPairing;

  /// Abandons whatever pairing is in flight.
  final Future<OpenDexError?> Function() cancelPairing;

  /// Manual pairing with the address, port and one-time code the phone shows.
  ///
  /// Completes only after the backend has *also* attempted the follow-on
  /// connection, so a success here can leave the snapshot at `connected`,
  /// `needsConnectionPort`, or `failed`. The screen reads the phase rather than
  /// assuming a second step is always required.
  final Future<OpenDexError?> Function({
    required String host,
    required int pairingPort,
    required String pairingCode,
  })
  pair;

  /// Brings up the debugging transport on the separately advertised port.
  ///
  /// Success is an authorized ADB transport, not a DroidPier session: the phone
  /// still has to be selected and connected through the normal commands.
  final Future<CommandResult<DeviceSummary>> Function({
    required String host,
    required int port,
  })
  connect;

  /// Drops this computer's wireless transport to a device. Presented as
  /// "Disconnect", because it does not revoke the pairing the phone holds.
  final Future<OpenDexError?> Function(String deviceId) disconnectWireless;

  /// The typed failure inside a result, or null when it succeeded.
  static OpenDexError? errorOf(VoidResult result) => switch (result) {
    CommandSuccess<void>() => null,
    CommandFailure<void>(:final OpenDexError error) => error,
  };
}
