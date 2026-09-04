import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/phone_mirror.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The phone mirror has to be openable.
///
/// 511 lines, two goldens, and a place in the frame-cost contract — and
/// nothing in `lib/` ever built it. Its own doc said it belonged docked
/// bottom-right above the taskbar; nothing put it there. Worse, the rule that
/// panels must not blur over live video was asserted *through* this widget, so
/// the product's most expensive mistake was guarded by dead code.
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
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
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the phone mirror opens from the command palette', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(find.byType(PhoneMirror), findsNothing);

    // Through the command palette, which is how every shell action is
    // reachable without hunting for a control.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final Finder entry = find.textContaining('phone mirror');
    expect(entry, findsOneWidget, reason: 'the palette must offer a door');
    await tester.tap(entry);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(PhoneMirror), findsOneWidget);
  });
}
