import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_switcher.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// Alt+Tab used to swap focus silently. With two windows that reads as a
/// glitch; with four it is unusable, because nothing says where you are in the
/// list. These cover the visible half.
void main() {
  Future<MockOpenDexFacade> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    // Driven from the stream, as `main.dart` does. Passing a snapshot once
    // means launching an app never reaches the shell, and the switcher would
    // have nothing to switch between.
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data ?? facade.snapshot,
                facade: facade,
                now: DateTime.utc(2026, 8, 25, 4),
              ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return facade;
  }

  Future<void> openTwoWindows(WidgetTester tester, MockOpenDexFacade f) async {
    final List<AndroidApplication> apps = f.snapshot.applications
        .where((AndroidApplication a) => !a.isSystemApp)
        .take(2)
        .toList();
    for (final AndroidApplication a in apps) {
      await f.launchApplication(a.packageName);
    }
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('Alt+Tab shows the switcher while Alt is held', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade f = await pumpShell(tester);
    await openTwoWindows(tester, f);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      find.byType(WindowSwitcher),
      findsOneWidget,
      reason: 'holding Alt must show what is about to receive focus',
    );

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      find.byType(WindowSwitcher),
      findsNothing,
      reason: 'releasing Alt commits and closes',
    );
  });

  testWidgets('Escape cancels the switch instead of committing it', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade f = await pumpShell(tester);
    await openTwoWindows(tester, f);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(WindowSwitcher), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(WindowSwitcher), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });

  testWidgets('one window alone never opens the switcher', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade f = await pumpShell(tester);
    final AndroidApplication only = f.snapshot.applications.firstWhere(
      (AndroidApplication a) => !a.isSystemApp,
    );
    await f.launchApplication(only.packageName);
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      find.byType(WindowSwitcher),
      findsNothing,
      reason: 'there is nothing to switch to',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });
}
