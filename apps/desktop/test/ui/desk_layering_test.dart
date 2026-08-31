import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/desk.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The desk used to be the workspace's background, which put every app window
/// above the taskbar, tray and phone mirror — maximise an app and the taskbar
/// was gone until you moved the window. Every desktop keeps its taskbar on top.
void main() {
  testWidgets('the taskbar stays above a window that fills the workspace', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
            // Stands in for a maximised app window: opaque, and as large as
            // the workspace will let it be.
            workspace: const ColoredBox(
              key: Key('window'),
              color: Color(0xFF000000),
              child: SizedBox.expand(),
            ),
            windows: const <WorkspaceWindow>[],
            minimisedWindows: const <String>{},
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(TaskbarBar), findsOneWidget);

    // Painted position, not just presence: a taskbar behind the window is
    // still "found" by the finder and still useless.
    final Rect bar = tester.getRect(find.byType(TaskbarBar));
    final Rect window = tester.getRect(find.byKey(const Key('window')));
    expect(
      window.bottom,
      lessThanOrEqualTo(bar.top + 0.5),
      reason: 'the workspace must be inset by the taskbar, not run under it',
    );

    // And the Apps button must be reachable, not merely present: a taskbar
    // painted behind the window is still "found" and still useless.
    expect(
      tester.getRect(find.byTooltip('Your apps')).center.dy,
      greaterThan(window.bottom - 0.5),
    );
  });
}
