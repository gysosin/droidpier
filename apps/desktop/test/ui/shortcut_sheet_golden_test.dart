@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/shortcut_sheet.dart';
import 'package:open_android_dex/ui/shell/shortcuts.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

Future<void> _loadFonts() async {
  // MaterialIcons too, or the close button bakes in as a tofu box — which is
  // precisely how a missing glyph once shipped past a passing golden here.
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

/// The real registry, with inert callbacks — the sheet renders labels and
/// strokes, never invokes anything.
ShellShortcutHooks _hooks() => ShellShortcutHooks(
  openPalette: () {},
  isPaletteOpen: () => false,
  closePalette: () {},
  openSheet: () {},
  isSheetOpen: () => true,
  closeSheet: () {},
  keyboardIsFree: () => true,
  toggleDiagnostics: () {},
  toggleHealthHud: () {},
  toggleDrawer: () {},
  toggleFullscreen: () {},
  cycleFocus: () {},
  cycleFocusBack: () {},
  isFullscreen: () => false,
  exitFullscreen: () {},
  isDiagnosticsOpen: () => false,
  closeDiagnostics: () {},
  isSwitcherOpen: () => false,
  cancelSwitch: () {},
  isDeskSurfaceOpen: () => false,
  closeDeskSurfaces: () {},
  isConnectOpen: () => false,
  closeConnect: () {},
  previousWorkspace: () {},
  nextWorkspace: () {},
);

void main() {
  setUpAll(_loadFonts);

  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('shortcut sheet, $name', (WidgetTester tester) async {
      // Sized to the panel the shell gives it. A single column overflowed this
      // box and hid three rows below an invisible scroll, which is why the
      // sheet lays out in two columns — the golden must keep that honest.
      await tester.binding.setSurfaceSize(const Size(880, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: ShortcutSheet(
              shortcuts: buildShortcuts(_hooks()),
              onClose: () {},
            ),
          ),
        ),
      );
      // Twice, deliberately: Entrance resolves its stagger during a pump, so
      // the controller only advances on the frame after.
      await tester.pump();
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // Presence is not visibility — a fully transparent panel would otherwise
      // be baselined as correct.
      final Opacity fade = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Toggle the launcher'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade.opacity, greaterThan(0.99), reason: 'entrance unfinished');

      // Every registry entry reaches the sheet: nothing clipped, nothing lost.
      expect(find.byType(ShortcutSheet), findsOneWidget);
      expect(find.text('Close the connection screen'), findsOneWidget);

      await expectLater(
        find.byType(ShortcutSheet),
        matchesGoldenFile('goldens/shortcut_sheet_$name.png'),
      );
    });
  }
}
