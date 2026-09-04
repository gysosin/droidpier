@Tags(<String>['golden'])
library;

import 'package:open_android_dex/ui/desk/desk_icons.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

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

  testWidgets('desk icons with a real phone worth of apps', (
    WidgetTester tester,
  ) async {
    // The mock backend has three apps. A real phone reports dozens, and the
    // desk is where they all land unless something bounds them.
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const List<String> names = <String>[
      'Chrome',
      'Spotify',
      'YouTube',
      'Maps',
      'Gmail',
      'Photos',
      'Drive',
      'Calendar',
      'Keep',
      'Meet',
      'Files',
      'Camera',
      'Clock',
      'Contacts',
      'Messages',
      'Phone',
      'Settings',
      'Play Store',
      'Wallet',
      'Translate',
      'Podcasts',
      'News',
      'Fit',
      'Home',
      'Slides',
      'Docs',
      'Sheets',
      'Duo',
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DeskWallpaper(
            child: DeskIcons(
              applications: <AndroidApplication>[
                for (int i = 0; i < 77; i++)
                  AndroidApplication(
                    packageName: 'com.demo.app$i',
                    label: names[i % names.length],
                  ),
              ],
              onLaunch: (_) {},
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await expectLater(
      find.byType(DeskIcons),
      matchesGoldenFile('goldens/desk_icons_many.png'),
    );
  });
}
