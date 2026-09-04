@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The failed boot had no golden at all, which is how its error box went from
/// a code name to a rendered adb transcript and back without anyone seeing it.
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

  Future<void> pump(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const BootScreen(
          boot: BootState(
            phase: BootPhase.failed,
            message: 'The Android companion could not start.',
            error: OpenDexError(
              code: OpenDexErrorCode.deploymentFailed,
              message: 'The Android companion could not start.',
              technicalDetails: 'INSTALL_FAILED_USER_RESTRICTED',
            ),
          ),
          onConnect: _noop,
          onRetry: _noop,
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('boot screen, failed, dark', (WidgetTester tester) async {
    await pump(tester, DexTheme.dark());
    await expectLater(
      find.byType(BootScreen),
      matchesGoldenFile('goldens/boot_failed_dark.png'),
    );
  });

  testWidgets('boot screen, connecting, two phones attached, dark', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: const BootScreen(
          boot: BootState(
            phase: BootPhase.awaitingHandshakes,
            message: 'Waiting for the phone to answer',
          ),
          onConnect: _noop,
          onRetry: _noop,
          device: DeviceSummary(
            id: 'serial-1',
            name: 'Pixel 7a',
            connectionKind: DeviceConnectionKind.wifi,
            status: DeviceStatus.authorized,
            androidVersion: '14',
          ),
          deviceCount: 2,
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(BootScreen),
      matchesGoldenFile('goldens/boot_two_phones_dark.png'),
    );
  });

  testWidgets('boot screen, failed, light', (WidgetTester tester) async {
    await pump(tester, DexTheme.light());
    await expectLater(
      find.byType(BootScreen),
      matchesGoldenFile('goldens/boot_failed_light.png'),
    );
  });
}

void _noop() {}
