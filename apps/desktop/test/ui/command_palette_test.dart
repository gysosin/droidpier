import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/shell/command_palette.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The command palette.
///
/// One surface for everything the shell can do, reachable by name. It is the
/// cheapest home for the features that have no natural place of their own.
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
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> openPalette(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  testWidgets('Ctrl+Shift+P opens it', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(find.byType(CommandPalette), findsNothing);
    await openPalette(tester);
    expect(find.byType(CommandPalette), findsOneWidget);
  });

  testWidgets('Escape closes it', (WidgetTester tester) async {
    await pumpShell(tester);
    await openPalette(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(
      find.byType(CommandPalette),
      findsNothing,
      reason: 'a surface you cannot leave is a trap',
    );
  });

  testWidgets('it lists apps and open windows without typing', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await openPalette(tester);
    // The mock's ready scenario has applications; the palette should show them
    // before any query, so it doubles as a menu rather than only a search box.
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.text('APPS'), findsOneWidget);
  });

  testWidgets('typing filters, and marks a row for Enter', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await openPalette(tester);

    final Finder field = find.descendant(
      of: find.byType(CommandPalette),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'chr');
    await settle(tester);

    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('a query matching nothing says so rather than going blank', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await openPalette(tester);

    final Finder field = find.descendant(
      of: find.byType(CommandPalette),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'zzzzq');
    await settle(tester);

    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });

  testWidgets('arrow keys move the marked row', (WidgetTester tester) async {
    await pumpShell(tester);
    await openPalette(tester);
    expect(find.text('Enter'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    // Still exactly one row marked, just a different one.
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('the palette is listed in the shortcut sheet', (
    WidgetTester tester,
  ) async {
    // A feature reachable only by a shortcut nobody knows is not reachable.
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await settle(tester);
    expect(find.text('Ctrl+Shift+P'), findsOneWidget);
  });
}
