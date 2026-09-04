// Temporary generator for `assets/branding/desktop-preview.png`.
//
// Renders the real `AppShell` against `MockOpenDexFacade` — the same harness the
// golden tests use — and writes the composited result to the branding asset.
// Everything on screen is the actual UI driven by the mock's synthetic data.
@Tags(<String>['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
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

  testWidgets('capture the connected desk', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);

    final GlobalKey shot = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: shot,
          child: AppShell(
            snapshot: facade.snapshot,
            facade: facade,
            now: DateTime.utc(2026, 8, 24, 22),
          ),
        ),
      ),
    );

    // Two pumps, deliberately — `Entrance` resolves its stagger during a pump,
    // so the controller only advances on the frame after. `pumpAndSettle` never
    // returns here: the Link Rail trace repeats forever by design.
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Presence is not visibility. A fully transparent desk would otherwise be
    // captured and shipped as the product's preview image.
    expect(find.text('Search the web or apps…'), findsOneWidget);
    final Opacity fade = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Search the web or apps…'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(fade.opacity, greaterThan(0.99), reason: 'entrance did not finish');

    final RenderRepaintBoundary boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    late Uint8List png;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      png = data!.buffer.asUint8List();
      image.dispose();
    });

    final File out = File('assets/branding/desktop-preview.png');
    out.writeAsBytesSync(png);
    // ignore: avoid_print
    print('wrote ${out.path}: ${png.length} bytes');
  });
}
