@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/command_palette.dart';
import 'package:open_android_dex/ui/shell/commands.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';

Future<void> _loadFonts() async {
  const Map<String, List<String>> families = <String, List<String>>{
    'Lucide': <String>['assets/icons/lucide.ttf'],
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

/// The command palette had no baseline.
///
/// It is the surface every shell action is reachable through, and nothing had
/// ever looked at it — which is how a screen goes unchecked while its tests
/// stay green. It groups by APPS / WINDOWS / DEVICE / SHELL, so the golden
/// carries one of each.
void main() {
  setUpAll(_loadFonts);

  const List<AndroidApplication> apps = <AndroidApplication>[
    AndroidApplication(packageName: 'com.android.chrome', label: 'Chrome'),
    AndroidApplication(packageName: 'com.spotify.music', label: 'Spotify'),
  ];

  final List<WindowSessionState> windows = <WindowSessionState>[
    const WindowSessionState(
      id: 'w1',
      application: AndroidApplication(
        packageName: 'com.google.maps',
        label: 'Maps',
      ),
      status: WindowSessionStatus.streaming,
    ),
  ];

  Future<void> shoot(
    WidgetTester tester, {
    required ThemeData theme,
    required String name,
  }) async {
    await tester.binding.setSurfaceSize(const Size(880, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CommandPalette(
            commands: buildCommands(
              applications: apps,
              windows: windows,
              shellEntries: <DexCommandEntry>[
                DexCommandEntry(title: 'Open settings', run: () {}),
                DexCommandEntry(title: 'Show design tokens', run: () {}),
                DexCommandEntry(title: 'Toggle the phone mirror', run: () {}),
              ],
              onLaunchApplication: (_) {},
              onFocusWindow: (_) {},
            ),
            onDismiss: () {},
          ),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(CommandPalette),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('command palette, dark', (WidgetTester tester) async {
    await shoot(tester, theme: DexTheme.dark(), name: 'command_palette_dark');
  });

  testWidgets('command palette, light', (WidgetTester tester) async {
    await shoot(tester, theme: DexTheme.light(), name: 'command_palette_light');
  });
}
