@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
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

  for (final (String mode, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('app shell, connected desk, $mode', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      final MockOpenDexFacade facade = MockOpenDexFacade(
        scenario: MockScenario.ready,
      );
      addTearDown(facade.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: AppShell(
            snapshot: facade.snapshot,
            facade: facade,
            now: DateTime.utc(2026, 8, 24, 22),
          ),
        ),
      );
      // Two pumps, deliberately — not pumpAndSettle.
      //
      // `Entrance` schedules its stagger with Future.delayed, which resolves
      // *during* a pump, so the controller only begins advancing on the frame
      // after. And pumpAndSettle can never return here: the Link Rail trace
      // repeats forever by design, so there is no settled state to wait for.
      await tester.pump();
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      // The desk is a real desktop now: search bars, app icons, a bare clock
      // top-right, and the dock.
      expect(find.text('Search Google'), findsOneWidget);
      // Presence is not visibility: assert the entrance actually finished, or a
      // fully transparent screen would pass this test.
      final Opacity fade = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Search Google'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(
        fade.opacity,
        greaterThan(0.99),
        reason: 'entrance did not finish',
      );
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/shell_desk_$mode.png'),
      );

      // The launcher opens as a window on the desk, not as a change of place.
      await tester.tap(find.byTooltip('Your apps'));
      await tester.pump();
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      // The drawer opened: its search field is present (the old 'Your apps'
      // header was removed in the floating-launcher redesign). The desk itself
      // now carries the two search bars, so three text fields are on screen —
      // the drawer's is the one whose hint is 'Search apps…'. Two fields are on
      // screen: the desk's Google bar and the drawer's search.
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.text('Search apps…'), findsOneWidget);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/shell_launcher_$mode.png'),
      );
    });
  }
}
