@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Golden coverage for the boot screen.
///
/// Real font files are loaded from `assets/fonts/` so the goldens show the
/// actual type system rather than the test harness's placeholder face. This is
/// also how UI review happens without a device.
Future<void> _loadFonts() async {
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
  for (final MapEntry<String, List<String>> entry in families.entries) {
    final FontLoader loader = FontLoader(entry.key);
    for (final String path in entry.value) {
      final File file = File(path);
      if (file.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

Widget _harness(BootState boot, ThemeData theme) {
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: BootScreen(boot: boot, onConnect: () {}, onRetry: () {}),
  );
}

void main() {
  setUpAll(_loadFonts);

  const BootState connecting = BootState(
    phase: BootPhase.awaitingHandshakes,
    message: 'Waiting for the phone to answer',
    stages: <BootStage>[
      BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
      BootStage(id: 'device', label: 'Device', status: StageStatus.complete),
      BootStage(
        id: 'agent',
        label: 'Agent :3698',
        status: StageStatus.active,
        detail: 'Handshake sent',
      ),
      BootStage(id: 'companion', label: 'Companion :3699'),
      BootStage(id: 'applications', label: 'Applications'),
    ],
  );

  testWidgets('boot screen, connecting, dark', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_harness(connecting, DexTheme.dark()));
    // Entrance staggers with Future.delayed, which resolves *during* a pump,
    // so the controller only advances on the frame after. One pump leaves the
    // screen at opacity 0 — and --update-goldens will happily baseline that.
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(BootScreen),
      matchesGoldenFile('goldens/boot_connecting_dark.png'),
    );
  });

  testWidgets('boot screen, connecting, light', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_harness(connecting, DexTheme.light()));
    // Entrance staggers with Future.delayed, which resolves *during* a pump,
    // so the controller only advances on the frame after. One pump leaves the
    // screen at opacity 0 — and --update-goldens will happily baseline that.
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(BootScreen),
      matchesGoldenFile('goldens/boot_connecting_light.png'),
    );
  });
}
