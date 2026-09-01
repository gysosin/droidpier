import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/shell/shortcut_sheet.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The keyboard cheat sheet.
///
/// Shortcuts were invisible: they existed only in a chain of `if`s that no user
/// could read. This sheet is the door to them, so the tests care most about the
/// ways in — and about the one way it must NOT open, which is while somebody is
/// typing a question mark into a search box.
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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
          now: DateTime.utc(2026, 9, 1, 22),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('Ctrl+/ opens the cheat sheet', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(find.byType(ShortcutSheet), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(find.byType(ShortcutSheet), findsOneWidget);
  });

  testWidgets('F1 opens it too', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await settle(tester);
    expect(find.byType(ShortcutSheet), findsOneWidget);
  });

  testWidgets('it lists shortcuts from the registry, not its own strings', (
    WidgetTester tester,
  ) async {
    // Both halves of a registry entry must appear: the human label and the
    // stroke rendered from the same data. If either were typed into the sheet
    // by hand there would be two sources of truth, and one of them would rot.
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await settle(tester);

    expect(find.text('Toggle the launcher'), findsOneWidget);
    expect(find.text('Ctrl+Space'), findsOneWidget);
    expect(find.text('Switch window'), findsOneWidget);
    expect(find.text('Alt+Tab'), findsOneWidget);
  });

  testWidgets('Escape closes it', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await settle(tester);
    expect(find.byType(ShortcutSheet), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(
      find.byType(ShortcutSheet),
      findsNothing,
      reason: 'a surface you cannot leave is a trap',
    );
  });

  // The bare `?` binding is covered in shell_shortcuts_test.dart, not here.
  //
  // `LogicalKeyboardKey.question` cannot be simulated: it has no physical key
  // of its own, and no platform keycode map the test harness ships knows it —
  // android and linux both assert. Hardware produces it as Shift+/ and the
  // product path is fine; only the simulator cannot express it. Since the
  // registry is pure data, the guard is asserted directly there instead, which
  // is a stronger test than a key press would have been anyway.
}
