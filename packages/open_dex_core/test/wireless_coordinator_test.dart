import 'dart:async';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_core/src/wireless_coordinator.dart';
import 'package:test/test.dart';

void main() {
  late _Gateway gateway;
  late _Discovery discovery;
  late WirelessCoordinator coordinator;
  late WirelessPairingState pairing;
  late List<DeviceSummary> connected;
  setUp(() {
    gateway = _Gateway();
    discovery = _Discovery();
    connected = [];
    pairing = const WirelessPairingState();
    coordinator = WirelessCoordinator(
      gateway: gateway,
      discovery: discovery,
      onDiscovery: (_) {},
      onPairing: (s) => pairing = s,
      onConnected: connected.add,
      resolveTimeout: const Duration(milliseconds: 10),
      qrLifetime: const Duration(milliseconds: 300),
    );
  });
  tearDown(() async {
    await coordinator.stop();
    await discovery.controller.close();
  });
  test('unrelated nearby phones never trigger pairing or connection', () async {
    await coordinator.start();
    discovery.send([record('other', WirelessServiceKind.pairing)]);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.secrets, isEmpty);
    expect(connected, isEmpty);
  });
  test(
    'QR matches only its random service and disposes its secret before pairing',
    () async {
      await coordinator.startQr();
      final payload = pairing.qrPayload!;
      final name = RegExp(r';S:([^;]+);').firstMatch(payload)!.group(1)!;
      discovery.send([record('unrelated', WirelessServiceKind.pairing)]);
      expect(gateway.secrets, isEmpty);
      discovery.send([
        record(name, WirelessServiceKind.pairing),
        record('adb-synthetic-guid', WirelessServiceKind.connection),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.secrets, hasLength(1));
      expect(pairing.qrPayload, isNull);
      expect(pairing.phase, WirelessPairingPhase.connected);
      expect(connected, hasLength(1));
    },
  );
  test(
    'cancelled in-flight pairing cannot connect or change the idle state',
    () async {
      gateway.block = Completer<String?>();
      final pending = coordinator.pairManual(
        host: '192.0.2.1',
        port: 12345,
        code: '012345',
      );
      await Future<void>.delayed(Duration.zero);
      await coordinator.cancel();
      gateway.block!.complete('synthetic-guid');
      expect(await pending, isA<CommandFailure<void>>());
      expect(pairing.phase, WirelessPairingPhase.idle);
      expect(connected, isEmpty);
    },
  );
  test(
    'paired phone without discovery asks for its separate connection port',
    () async {
      expect(
        (await coordinator.pairManual(
          host: '192.0.2.1',
          port: 12345,
          code: '012345',
        )).isSuccess,
        isTrue,
      );
      expect(pairing.phase, WirelessPairingPhase.needsConnectionPort);
      expect(gateway.secrets.single, '012345');
    },
  );
  test('QR expiry and regeneration discard the previous session', () async {
    await coordinator.startQr();
    final previous = pairing.qrPayload;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(pairing.phase, WirelessPairingPhase.expired);
    expect(pairing.qrPayload, isNull);
    await coordinator.startQr();
    expect(pairing.qrPayload, isNot(previous));
  });
  test('expired discovery records cannot be paired', () async {
    await coordinator.startQr();
    final name = RegExp(
      r';S:([^;]+);',
    ).firstMatch(pairing.qrPayload!)!.group(1)!;
    discovery.send([
      WirelessAdvertisement(
        serviceName: name,
        kind: WirelessServiceKind.pairing,
        host: '192.0.2.1',
        port: 12345,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    ]);
    expect(gateway.secrets, isEmpty);
  });
}

WirelessAdvertisement record(
  String name,
  WirelessServiceKind kind,
) => WirelessAdvertisement(
  serviceName:
      '$name._adb-tls-${kind == WirelessServiceKind.pairing ? 'pairing' : 'connect'}._tcp.local',
  kind: kind,
  host: '192.0.2.1',
  port: 12345,
  expiresAt: DateTime.now().add(const Duration(seconds: 30)),
);

class _Discovery implements WirelessDiscoveryGateway {
  final controller = StreamController<WirelessDiscoveryState>.broadcast(
    sync: true,
  );
  @override
  WirelessDiscoveryState current = const WirelessDiscoveryState(
    status: WirelessDiscoveryStatus.ready,
  );
  @override
  Stream<WirelessDiscoveryState> get updates => controller.stream;
  void send(List<WirelessAdvertisement> devices) {
    current = WirelessDiscoveryState(
      status: WirelessDiscoveryStatus.ready,
      devices: devices,
    );
    controller.add(current);
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

class _Gateway implements WirelessDeviceGateway, WirelessPairingGateway {
  final secrets = <String>[];
  Completer<String?>? block;
  @override
  Future<String?> pairWithSecret({
    required String host,
    required int port,
    required String secret,
  }) async {
    secrets.add(secret);
    return block != null ? await block!.future : 'synthetic-guid';
  }

  @override
  Future<void> cancelPending() async {}
  @override
  Future<void> pair({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) async {}
  @override
  Future<DeviceSummary> connect({
    required String host,
    required int port,
  }) async => DeviceSummary(
    id: '$host:$port',
    name: 'Synthetic Android',
    connectionKind: DeviceConnectionKind.wifi,
    status: DeviceStatus.authorized,
  );
  @override
  Future<void> forget(String deviceId) async {}
}
