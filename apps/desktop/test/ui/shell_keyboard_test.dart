import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/diagnostics/stream_diagnostics.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Desktop keyboard behaviour.
///
/// A desktop environment is expected to open its launcher from the keyboard and
/// close whatever is open with Escape. Asserting it here rather than trusting
/// that the intent is wired.
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('typing in the launcher search is not stolen by a window', (
    WidgetTester tester,
  ) async {
    // Forwarding keys to the focused Android window is a global handler, so it
    // sees every keystroke before our own fields do. If its guards are wrong
    // the drawer's search box silently stops accepting letters the moment an
    // app is open — which is exactly the kind of break that no one writes a
    // test for until it ships.
    await pumpShell(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The desk itself now carries two search bars, so target the drawer's own
    // field by its hint rather than "the only text field on screen".
    final Finder search = find.ancestor(
      of: find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"),
      matching: find.byType(TextField),
    );
    expect(search, findsOneWidget, reason: 'the drawer should be open');
    await tester.enterText(search, 'map');
    await tester.pump();
    expect(find.text('map'), findsOneWidget);
  });

  testWidgets('Ctrl+Space opens and closes the launcher', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsNothing);
  });

  testWidgets('the desk clock ticks on its own', (WidgetTester tester) async {
    // No `now`, so the shell runs its own clock — the product path.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(snapshot: facade.snapshot, facade: facade),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The real assertion: the desk shows the wall clock, not the time some
    // snapshot happened to arrive. Nothing else in this test moves it.
    String render(DateTime n) {
      final int h = n.hour % 12 == 0 ? 12 : n.hour % 12;
      final String ap = n.hour < 12 ? 'AM' : 'PM';
      return '$h:${n.minute.toString().padLeft(2, '0')} $ap';
    }

    /// Accepts this minute or the next.
    ///
    /// The clock is rendered when the widget builds and checked a moment
    /// later. Comparing against a single fresh `DateTime.now()` failed
    /// whenever the minute rolled over in between — a real race that flaked
    /// this test twice, not a fault in the product.
    void expectShowsClock() {
      final DateTime n = DateTime.now();
      final bool shown =
          find.text(render(n)).evaluate().isNotEmpty ||
          find
              .text(render(n.subtract(const Duration(minutes: 1))))
              .evaluate()
              .isNotEmpty;
      expect(
        shown,
        isTrue,
        reason: 'the desk clock should read ${render(n)} or the minute before',
      );
    }

    expectShowsClock();

    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    // Still correct after the timer fires — and reaching teardown without a
    // "Timer is still pending" failure proves the ticker is cancelled.
    expectShowsClock();
  });

  testWidgets('every surface has a door from the desk', (
    WidgetTester tester,
  ) async {
    // Two screens have already been orphaned by refactors — the phone list and
    // the permission panel each rendered in the stack with nothing able to open
    // them, and every test stayed green. This walks the paths a person uses.
    await pumpShell(tester);

    Future<void> settle() async {
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    // Launcher, from the dock.
    await tester.tap(find.byTooltip('Your apps'));
    await settle();
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    // Settings, from the tray gear. The reference tray carries no volume /
    // controls / notifications buttons; Settings is the single hub now, and it
    // holds the doors to permissions and the phone list.
    await tester.tap(find.byTooltip('Settings'));
    await settle();
    expect(find.text('Window Snapping'), findsOneWidget);
    // The two phone-link tiles: Manage Phones, then Permissions.
    expect(find.text('Manage Phones…'), findsOneWidget);
    expect(find.text('Permissions…'), findsOneWidget);

    // Permissions, from Settings (scroll it into view first — the panel scrolls).
    await tester.ensureVisible(
      find.text('Permissions…'),
    );
    await settle();
    await tester.tap(find.text('Permissions…'));
    await settle();
    expect(find.text('What the desk can use'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    // Phone list, from Settings.
    await tester.tap(find.byTooltip('Settings'));
    await settle();
    await tester.ensureVisible(
      find.text('Manage Phones…'),
    );
    await settle();
    await tester.tap(find.text('Manage Phones…'));
    await settle();
    // One surface now: the phone list and the three ways to add one over
    // Wi-Fi, rather than a dialog that opens a second dialog.
    expect(find.text('Connect a phone'), findsOneWidget);
    expect(find.text('Add over Wi-Fi'), findsOneWidget);

    // And back out of it without connecting — Escape must reach it, and one
    // press must be enough because there is only one layer.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(
      find.text('Connect a phone'),
      findsNothing,
      reason: 'no screen is a dead end',
    );
  });

  testWidgets('Alt+Tab does nothing with fewer than two windows', (
    WidgetTester tester,
  ) async {
    // The mock desk has no windows open. Alt+Tab must be inert rather than
    // throwing or focusing something that is not there.
    await pumpShell(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the launcher', (WidgetTester tester) async {
    await pumpShell(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)…"),
      findsNothing,
      reason: 'a surface you cannot leave is a trap',
    );
  });

  testWidgets('Escape closes diagnostics before it closes the launcher', (
    WidgetTester tester,
  ) async {
    // The Escape ladder, at the one rung a person can actually reach twice.
    //
    // Escape is not one binding: with several layers up it peels exactly one,
    // in a fixed order. Most rungs cannot be observed together, because
    // entering fullscreen deliberately clears the drawer, settings and
    // diagnostics (see _toggleFullscreen). The launcher and diagnostics are the
    // pair that genuinely coexist — neither toggle clears the other — and the
    // ladder ranks diagnostics above the launcher.
    //
    // Every other Escape test opens a single layer, so none of them can tell
    // this order from any other. Flattening the ladder into a map, which cannot
    // express order at all, would leave the suite green.
    await pumpShell(tester);

    Future<void> settle() async {
      await tester.pump();
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    // Launcher up.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle();
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)\u2026"), findsOneWidget);

    // Diagnostics over the top of it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle();
    expect(
      find.byType(StreamDiagnostics),
      findsOneWidget,
      reason: 'both layers should now be up',
    );
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)\u2026"), findsOneWidget);

    // One Escape takes the higher rung only.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(
      find.byType(StreamDiagnostics),
      findsNothing,
      reason: 'the first Escape belongs to diagnostics',
    );
    expect(
      find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)\u2026"),
      findsOneWidget,
      reason: 'the launcher is a lower rung and must survive the first Escape',
    );

    // The second Escape takes the next rung down.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(find.text("Search phone apps (e.g. 'wa' for WhatsApp, or app name)\u2026"), findsNothing);
  });
}
