import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Restoring a minimised window from the taskbar must persist.
///
/// The shell re-reads every window's displayState from the backend on each
/// rebuild, and fps telemetry triggers rebuilds constantly. A taskbar restore
/// that only flips local state — without telling the backend — is undone by the
/// very next snapshot: the window reappears for a frame and snaps shut. Alt-Tab
/// restore always told the backend; the taskbar path did not, and that is the
/// gap this guards.
void main() {
  testWidgets('a taskbar restore survives the next backend snapshot', (
    WidgetTester tester,
  ) async {
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
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> snap) =>
              AppShell(
                snapshot: snap.data!,
                facade: facade,
                now: DateTime.utc(2026, 8, 25, 22),
              ),
        ),
      ),
    );
    await tester.pump();

    await facade.launchApplication('com.google.android.youtube');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final String id = facade.snapshot.windows.single.id;

    // Minimise it — the taskbar entry becomes a Restore affordance.
    await facade.setWindowDisplayState(id, WindowDisplayState.minimised);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final Finder restore = find.bySemanticsLabel(
      RegExp(r'^Restore YouTube'),
    );
    expect(restore, findsOneWidget, reason: 'a minimised window shows Restore');

    // Click it, then let the backend echo a fresh snapshot back — the moment
    // the broken version snapped the window shut again.
    await tester.tap(restore);
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      facade.snapshot.windows.single.displayState,
      WindowDisplayState.normal,
      reason: 'restore must reach the backend, not just local state',
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Restore YouTube')),
      findsNothing,
      reason: 'the window is no longer minimised, so no Restore affordance',
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Focus YouTube')),
      findsOneWidget,
      reason: 'a restored window offers Focus, and it stayed restored',
    );
  });
}
