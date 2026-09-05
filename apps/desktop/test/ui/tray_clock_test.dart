import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The tray has one door to the control centre — the status cluster — and
/// it shows when that door is open. The clock is a clock: it opens nothing.
void main() {
  Future<int> pumpTray(
    WidgetTester tester, {
    bool controlsOpen = false,
    bool notificationsOpen = false,
  }) async {
    int opened = 0;
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SystemTray(
              now: DateTime(2026, 9, 5, 10, 8),
              telemetry: facade.snapshot.telemetry,
              onOpenControls: () => opened++,
              onOpenNotifications: () {},
              notificationCount: 0,
              onOpenSettings: () {},
              onToggleFullscreen: () {},
              fullscreenActive: false,
              controlsOpen: controlsOpen,
              notificationsOpen: notificationsOpen,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Read back through the closure so a caller sees the count after taps.
    return opened;
  }

  testWidgets('the clock opens nothing; the status cluster opens controls', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SystemTray(
              now: DateTime(2026, 9, 5, 10, 8),
              telemetry: facade.snapshot.telemetry,
              onOpenControls: () => opened++,
              onOpenNotifications: () {},
              notificationCount: 0,
              onOpenSettings: () {},
              onToggleFullscreen: () {},
              fullscreenActive: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('10:08 am'));
    await tester.pump();
    expect(opened, 0, reason: 'the clock is a readout, not a door');

    await tester.tap(find.byTooltip('Control panel'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('the cluster says so while the control centre is open', (
    WidgetTester tester,
  ) async {
    // The cluster's own label carries the state; read it off the widget,
    // which does not depend on whether a semantics tree is being built.
    Finder labelled(String label) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == label,
    );
    await pumpTray(tester);
    expect(labelled('Control panel, open'), findsNothing);
    expect(labelled('Control panel'), findsOneWidget);
    await pumpTray(tester, controlsOpen: true);
    expect(labelled('Control panel, open'), findsOneWidget);
  });
}
