@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/settings/desk_settings.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

Future<void> _loadFonts() async {
  const Map<String, List<String>> families = <String, List<String>>{
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

  testWidgets('desk settings, dark', (WidgetTester tester) async {
    // Tall enough for the whole panel including About. At 760 the About group
    // fell below the fold, so the golden baselined a section it never showed.
    await tester.binding.setSurfaceSize(const Size(900, 1040));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: DeskSettings(
          snapEnabled: true,
          onSnapChanged: (_) {},
          themeMode: ThemeMode.dark,
          onThemeChanged: (_) {},
          wallpaperIndex: 0,
          onWallpaperChanged: (_) {},
          onDisconnect: () {},
          deviceLabel: 'Redmi Note 7 Pro',
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(DeskSettings),
      matchesGoldenFile('goldens/settings_dark.png'),
    );
  });
}
