import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/design/token_sheet.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_accent.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/theme/wallpapers.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The token specimen sheet.
///
/// Its whole value is that it reads the tokens rather than restating them, so
/// a value that drifts shows up here beside the ones it should match. A sheet
/// that hardcodes its own copy of the palette proves nothing, so these tests
/// check that what it renders is driven by the real token lists.
void main() {
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(body: TokenSheet(onClose: () {})),
      ),
    );
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('every accent and wallpaper is on the sheet', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    // findsWidgets, not findsOneWidget: "Slate" is legitimately both an
    // accent and a wallpaper, and the sheet shows both.
    for (final DexAccent a in kAccents) {
      expect(find.text(a.name), findsWidgets, reason: '${a.name} is missing');
    }
    for (final DexWallpaperChoice w in kWallpaperChoices) {
      expect(find.text(w.name), findsWidgets, reason: '${w.name} is missing');
    }
  });

  testWidgets('every semantic role is named with its value', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    for (final String role in <String>[
      'bg',
      'surface',
      'raised',
      'line',
      'text',
      'muted',
      'signal',
      'trace',
      'warn',
      'fault',
    ]) {
      expect(find.text(role), findsOneWidget, reason: '$role is missing');
    }
    // A swatch without its value cannot be used to check anything.
    expect(find.textContaining('#0B1120'), findsOneWidget);
  });

  testWidgets('the sheet is reachable from the shell', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 24, 22),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await tester.tap(find.text('Show design tokens'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(TokenSheet), findsOneWidget);

    // And it must close on Escape, like every other surface.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(TokenSheet), findsNothing);
  });
}
