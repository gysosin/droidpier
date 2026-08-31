@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/bench_backdrop.dart';
import 'package:open_android_dex/ui/wireless/wireless_pairing_dialog.dart';

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

  for (final (String mode, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('wireless pairing, $mode', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: BenchBackdrop(
              child: Center(
                child: WirelessPairingDialog(
                  devices: const <DeviceSummary>[
                    DeviceSummary(
                      id: '192.168.1.42:5555',
                      name: 'Pixel 7a',
                      connectionKind: DeviceConnectionKind.wifi,
                      status: DeviceStatus.authorized,
                      androidVersion: '14',
                    ),
                  ],
                  onPair: ({
                    required String host,
                    required String pairingCode,
                    required int pairingPort,
                  }) async => true,
                  onConnect: ({
                    required String host,
                    required int port,
                  }) async => null,
                  onForget: (_) async => true,
                  onClose: () {},
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
        find.byType(WirelessPairingDialog),
        matchesGoldenFile('goldens/wireless_$mode.png'),
      );
    });
  }
}
