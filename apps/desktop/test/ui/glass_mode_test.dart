import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Turning the frosted glass off.
///
/// Two reasons someone wants this, and neither is taste: a BackdropFilter is
/// expensive on a weak GPU, and heavy translucency is hard to read. Off must
/// mean no BackdropFilter anywhere, not a smaller blur radius.
void main() {
  Finder blurs() => find.byType(BackdropFilter);

  Future<void> pumpShell(WidgetTester tester, {required bool glass}) async {
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
          glassEnabled: glass,
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('glass on: the desk blurs', (WidgetTester tester) async {
    await pumpShell(tester, glass: true);
    expect(
      blurs(),
      findsWidgets,
      reason: 'the desk is a glass design by default',
    );
  });

  testWidgets('glass off: nothing on the desk blurs at all', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, glass: false);
    expect(
      blurs(),
      findsNothing,
      reason: 'off must remove the BackdropFilter, not merely soften it',
    );
  });

  testWidgets('glass off survives opening the launcher', (
    WidgetTester tester,
  ) async {
    // The drawer paints its own scrim blur independently of the desk scope, so
    // it is the surface most likely to ignore the preference.
    await pumpShell(tester, glass: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsOneWidget);
    expect(blurs(), findsNothing);
  });
}
