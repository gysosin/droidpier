import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/desk.dart';
import 'package:open_android_dex/ui/desk/desk_widgets.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The desk's right-hand column.
///
/// Four widgets were written for the desk — a clock, now playing, phone status
/// and notifications — and then never placed on it. All 514 lines were
/// referenced by nothing: no import, no test, no instantiation anywhere.
/// Meanwhile the desk ran a search bar, a column of icons and a clock across
/// an otherwise empty screen, and a plan cited these widgets' existence as
/// evidence that "the desk already hosts widgets", which it did not.
void main() {
  Future<void> pumpDesk(WidgetTester tester, Size size) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Desk(
            snapshot: facade.snapshot,
            now: DateTime.utc(2026, 8, 25, 10),
            onOpenLauncher: () {},
            onWebSearch: (_) {},
            onMediaAction: (_) {},
            onFocusWindow: (_) {},
            onCloseWindow: (_) {},
            onNavKey: (_) {},
            onToggleControl: (_, _) {},
            onToggleClipboardSync: (_) {},
            onSetVolume: (_, _) {},
            onOpenPermissions: () {},
            onDismissNotification: (_) async {},
            onActivateNotification: (_) async {},
            onDismissAllNotifications: () async {},
            onOpenSettings: () {},
            onToggleFullscreen: () {},
            fullscreenActive: false,
            onLaunchApplication: (_) {},
            workspace: const SizedBox.expand(),
            windows: const <WorkspaceWindow>[],
            minimisedWindows: const <String>{},
          currentWorkspace: 1,
          onSelectWorkspace: (_) {},
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('a wide desk carries the phone and notification widgets', (
    WidgetTester tester,
  ) async {
    await pumpDesk(tester, const Size(1600, 1000));
    expect(find.byType(PhoneWidget), findsOneWidget);
    expect(find.byType(NotificationsWidget), findsOneWidget);
  });

  testWidgets('a laptop screen still gets the column', (
    WidgetTester tester,
  ) async {
    // The threshold was set at 760 and the desk gets the window height less
    // the 72px taskbar, so 1280x800 left 691 and 1366x768 left 659 — the
    // column never appeared on a laptop at all, which is most of them.
    await pumpDesk(tester, const Size(1280, 800));
    expect(find.byType(PhoneWidget), findsOneWidget);
  });

  testWidgets('a narrow desk keeps its icons and drops the column', (
    WidgetTester tester,
  ) async {
    // The column goes first. Icons and the search bar are what the desk is
    // for; a status card squeezed against them is worse than none.
    await pumpDesk(tester, const Size(900, 700));
    expect(find.byType(PhoneWidget), findsNothing);
    expect(find.byType(NotificationsWidget), findsNothing);
  });

  testWidgets('the desk does not grow a second clock', (
    WidgetTester tester,
  ) async {
    // A carded ClockWidget is among the four, and the desk already has a large
    // bare analog clock in that corner. Two clocks is not composition.
    await pumpDesk(tester, const Size(1600, 1000));
    expect(find.byType(ClockWidget), findsNothing);
  });

  testWidgets('the column does not overflow the desk', (
    WidgetTester tester,
  ) async {
    await pumpDesk(tester, const Size(1600, 1000));
    expect(tester.takeException(), isNull);
  });
}
