@Tags(<String>['golden'])
library;

import 'package:open_android_dex/ui/workspace/window_switcher.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';

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

  testWidgets('window switcher', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AndroidApplication app(String label) =>
        AndroidApplication(packageName: 'com.demo.$label', label: label);

    WorkspaceWindow win(String label, int z, {bool minimised = false}) =>
        WorkspaceWindow(
          session: WindowSessionState(
            id: label,
            application: app(label),
            status: WindowSessionStatus.streaming,
            isFocused: z == 3,
          ),
          geometry: const WindowGeometry(x: 0, y: 0, width: 400, height: 300),
          zOrder: z,
          displayState: minimised
              ? WindowDisplayState.minimised
              : WindowDisplayState.normal,
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DeskWallpaper(
            child: WindowSwitcher(
              windows: <WorkspaceWindow>[
                win('Maps', 3),
                win('Camera', 2),
                win('Files', 1, minimised: true),
              ],
              selected: 1,
              onPick: (_) {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await expectLater(
      find.byType(WindowSwitcher),
      matchesGoldenFile('goldens/window_switcher_dark.png'),
    );
  });
}
