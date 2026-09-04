@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/design/token_sheet.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

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

/// The specimen sheet gets its own baseline.
///
/// It is the one surface whose job is to be wrong when something else is, so
/// a change to any token shows up here as a golden diff — which is the point.
void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester tester, {
    required ThemeData theme,
    required String name,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: TokenSheet(onClose: () {}),
          ),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(TokenSheet),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('design tokens, dark', (WidgetTester tester) async {
    await shoot(tester, theme: DexTheme.dark(), name: 'tokens_dark');
  });

  testWidgets('design tokens, light', (WidgetTester tester) async {
    await shoot(tester, theme: DexTheme.light(), name: 'tokens_light');
  });
}
