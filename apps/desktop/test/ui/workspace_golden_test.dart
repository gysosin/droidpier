@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/bench_backdrop.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';

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

  testWidgets('two overlapping windows, one focused', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AndroidApplication app(String l) =>
        AndroidApplication(packageName: 'com.example.$l', label: l);

    WorkspaceWindow w(
      String label, {
      required int z,
      required WindowGeometry g,
      bool focused = false,
      WindowSessionStatus status = WindowSessionStatus.streaming,
      bool withSurface = true,
    }) => WorkspaceWindow(
      session: WindowSessionState(
        id: label,
        application: app(label),
        status: status,
        isFocused: focused,
      ),
      geometry: g,
      zOrder: z,
      previewBuilder: withSurface
          ? mockSurface(app(label), DexColors.dark)
          : null,
      presentedFramesPerSecond: withSurface ? 60 : null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: BenchBackdrop(
            child: Workspace(
              windows: <WorkspaceWindow>[
                w(
                  'Maps',
                  z: 1,
                  g: const WindowGeometry(
                    x: 60,
                    y: 60,
                    width: 620,
                    height: 460,
                  ),
                ),
                w(
                  'Spotify',
                  z: 2,
                  focused: true,
                  g: const WindowGeometry(
                    x: 430,
                    y: 240,
                    width: 620,
                    height: 460,
                  ),
                ),
              ],
              intents: WorkspaceIntents(
                focus: (_) {},
                raise: (_) {},
                move: (_, _) {},
                setDisplayState: (_, _) {},
                close: (_) {},
                retry: (_) {},
                fullscreen: (_) {},
              ),
              emptyChild: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(Workspace),
      matchesGoldenFile('goldens/workspace_two_windows_dark.png'),
    );
  });
}
