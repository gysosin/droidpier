@Tags(<String>['golden'])
library;

import 'package:open_android_dex/ui/desk/phone_mirror.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<void> pump(WidgetTester tester, {required bool overVideo}) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DeskWallpaper(
            child: Center(
              child: PhoneMirror(
                snapshot: facade.snapshot,
                now: DateTime.utc(2026, 8, 25, 14, 30),
                onClose: () {},
                onLaunch: (_) {},
                overVideo: overVideo,
              ),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('phone mirror, blurred over the wallpaper', (
    WidgetTester tester,
  ) async {
    await pump(tester, overVideo: false);
    await expectLater(
      find.byType(PhoneMirror),
      matchesGoldenFile('goldens/phone_mirror_blurred.png'),
    );
  });

  testWidgets('phone mirror, flat fill while a window streams', (
    WidgetTester tester,
  ) async {
    // Must still read as a surface, not as a flat tint — that is the whole
    // question the compensation in GlassPanel._fill is answering.
    await pump(tester, overVideo: true);
    await expectLater(
      find.byType(PhoneMirror),
      matchesGoldenFile('goldens/phone_mirror_flat.png'),
    );
  });
}
