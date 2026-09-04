@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/bench_backdrop.dart';
import 'package:open_android_dex/ui/connect/connection_commands.dart';
import 'package:open_android_dex/ui/connect/connection_screen.dart';

Future<void> _loadFonts() async {
  final String root =
      Platform.environment['FLUTTER_ROOT'] ??
      Directory('../../.tools/flutter').absolute.path;
  final File icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader l = FontLoader('MaterialIcons');
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await l.load();
  }
  const Map<String, List<String>> families = <String, List<String>>{
    'Lucide': <String>['assets/icons/lucide.ttf'],
    'InstrumentSans': <String>['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final MapEntry<String, List<String>> e in families.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String path in e.value) {
      final File f = File(path);
      if (f.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  /// A screen with something in every region: a USB phone and a paired Wi-Fi
  /// one on the left, and two heard advertisements on the right — one offering
  /// to pair, one offering a connection, one of them nameless.
  ///
  /// The QR tab is deliberately *not* the golden. Its content is a live
  /// payload and a countdown; baselining either would encode a secret and a
  /// timestamp into a PNG.
  final DateTime now = DateTime.utc(2026, 8, 31, 12);

  ConnectionCommands inert() => ConnectionCommands(
    startDiscovery: () async => null,
    stopDiscovery: () async => null,
    startQrPairing: () async => null,
    cancelPairing: () async => null,
    pair: ({
      required String host,
      required int pairingPort,
      required String pairingCode,
    }) async => null,
    connect: ({required String host, required int port}) async =>
        const CommandFailure<DeviceSummary>(
          OpenDexError(
            code: OpenDexErrorCode.connectionFailed,
            message: 'Nothing answered on that port.',
          ),
        ),
    disconnectWireless: (_) async => null,
  );

  for (final (String mode, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('connection screen, $mode', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: BenchBackdrop(
              child: Center(
                child: ConnectionScreen(
                  deviceStatus: LoadStatus.ready,
                  devices: const <DeviceSummary>[
                    DeviceSummary(
                      id: 'demo-usb-phone',
                      name: 'Redmi Note 7 Pro',
                      connectionKind: DeviceConnectionKind.usb,
                      status: DeviceStatus.authorized,
                      androidVersion: '13',
                    ),
                    DeviceSummary(
                      id: '192.0.2.42:41234',
                      name: 'Pixel 7a',
                      connectionKind: DeviceConnectionKind.wifi,
                      status: DeviceStatus.authorized,
                      androidVersion: '14',
                    ),
                  ],
                  discovery: WirelessDiscoveryState(
                    status: WirelessDiscoveryStatus.ready,
                    devices: <WirelessAdvertisement>[
                      WirelessAdvertisement(
                        serviceName: 'adb-tls-pairing-1',
                        kind: WirelessServiceKind.pairing,
                        host: '192.0.2.4',
                        port: 37105,
                        expiresAt: now.add(const Duration(minutes: 1)),
                      ),
                      WirelessAdvertisement(
                        serviceName: 'adb-tls-connect-1',
                        kind: WirelessServiceKind.connection,
                        host: '192.0.2.9',
                        port: 41234,
                        displayName: 'Galaxy S21',
                        expiresAt: now.add(const Duration(minutes: 1)),
                      ),
                    ],
                  ),
                  pairing: const WirelessPairingState(),
                  commands: inert(),
                  selectedId: 'demo-usb-phone',
                  onSelect: (_) {},
                  onConnectSelected: () {},
                  onRefreshDevices: () {},
                  onClose: () {},
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(
        find.byType(ConnectionScreen),
        matchesGoldenFile('goldens/connect_$mode.png'),
      );
    });
  }
}
