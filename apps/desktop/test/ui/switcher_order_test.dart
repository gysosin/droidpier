import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/window_switcher.dart';

/// Alt+Tab order, and what it commits.
void main() {
  Future<MockOpenDexFacade> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
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
                now: DateTime.utc(2026, 9, 2, 4),
              ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return facade;
  }

  Future<List<String>> openWindows(
    WidgetTester tester,
    MockOpenDexFacade f,
    int count,
  ) async {
    final List<AndroidApplication> apps = f.snapshot.applications
        .where((AndroidApplication a) => !a.isSystemApp)
        .take(count)
        .toList();
    for (final AndroidApplication a in apps) {
      await f.launchApplication(a.packageName);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
    return apps.map((AndroidApplication a) => a.label).toList();
  }

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the order does not shift while Alt is held', (
    WidgetTester tester,
  ) async {
    // Every rebuild used to re-sort the list the highlight indexes into, and
    // the shell rebuilds on every telemetry snapshot — which during streaming
    // is constant. The highlight could move under the person's hand, and
    // releasing Alt could focus a window they never selected.
    final MockOpenDexFacade f = await pumpShell(tester);
    await openWindows(tester, f, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    expect(find.byType(WindowSwitcher), findsOneWidget);

    final List<String> before = tester
        .widgetList<WindowSwitcher>(find.byType(WindowSwitcher))
        .first
        .windows
        .map((WorkspaceWindow w) => w.id)
        .toList();

    // Snapshots keep arriving while the key is down.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final List<String> after = tester
        .widgetList<WindowSwitcher>(find.byType(WindowSwitcher))
        .first
        .windows
        .map((WorkspaceWindow w) => w.id)
        .toList();

    expect(after, before, reason: 'the list must be frozen while Alt is held');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle(tester);
  });

  testWidgets('Alt+Shift+Tab moves the other way', (WidgetTester tester) async {
    final MockOpenDexFacade f = await pumpShell(tester);
    await openWindows(tester, f, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    final int forward = tester
        .widget<WindowSwitcher>(find.byType(WindowSwitcher))
        .selected;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);
    final int back = tester
        .widget<WindowSwitcher>(find.byType(WindowSwitcher))
        .selected;

    expect(
      back,
      isNot(forward),
      reason: 'Alt+Shift+Tab should move the selection, not be swallowed',
    );

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle(tester);
  });

  testWidgets('it appears in the shortcut sheet', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await settle(tester);
    expect(find.text('Alt+Shift+Tab'), findsOneWidget);
  });
}
