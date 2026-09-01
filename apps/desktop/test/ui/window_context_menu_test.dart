import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';

/// The window title bar's right-click menu.
///
/// Every entry must map to something WorkspaceIntents can actually do. The
/// roadmap also asked for "always on top" and "move to workspace"; neither has
/// an API behind it, so neither appears — not even disabled.
void main() {
  const Size workspace = Size(1200, 800);

  WorkspaceWindow makeWindow({
    WindowDisplayState state = WindowDisplayState.normal,
  }) => WorkspaceWindow(
    session: const WindowSessionState(
      id: 'w1',
      application: AndroidApplication(
        packageName: 'com.example.app',
        label: 'Example',
      ),
      status: WindowSessionStatus.streaming,
      geometry: WindowGeometry(x: 40, y: 40, width: 400, height: 300),
      isFocused: true,
    ),
    geometry: const WindowGeometry(x: 40, y: 40, width: 400, height: 300),
    zOrder: 1,
    displayState: state,
    previewBuilder: (BuildContext _) => const ColoredBox(color: Colors.black),
  );

  /// Records what the menu asked for, so each entry can be checked against the
  /// intent it claims to perform.
  ({
    List<(String, WindowGeometry)> moves,
    List<(String, WindowDisplayState)> states,
    List<String> closed,
    WorkspaceIntents intents,
  })
  recorder({ValueChanged<String>? fullscreen}) {
    final List<(String, WindowGeometry)> moves = <(String, WindowGeometry)>[];
    final List<(String, WindowDisplayState)> states =
        <(String, WindowDisplayState)>[];
    final List<String> closed = <String>[];
    return (
      moves: moves,
      states: states,
      closed: closed,
      intents: WorkspaceIntents(
        focus: (_) {},
        raise: (_) {},
        move: (String id, WindowGeometry g) => moves.add((id, g)),
        setDisplayState: (String id, WindowDisplayState s) =>
            states.add((id, s)),
        close: closed.add,
        retry: (_) {},
        fullscreen: fullscreen,
      ),
    );
  }

  Future<void> pumpWindow(
    WidgetTester tester,
    WorkspaceIntents intents, {
    WindowDisplayState state = WindowDisplayState.normal,
    VoidCallback? onCloseOthers,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: workspace.width,
            height: workspace.height,
            child: Stack(
              children: <Widget>[
                AppWindow(
                  window: makeWindow(state: state),
                  intents: intents,
                  workspaceSize: workspace,
                  onCloseOthers: onCloseOthers,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Right-clicks the draggable label region, which is where the menu is
  /// attached — deliberately not over the window buttons.
  Future<void> rightClickTitleBar(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.text('Example')),
      buttons: 2,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('snapping entries come from WindowSnap, labels and all', (
    WidgetTester tester,
  ) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);

    // The labels are WindowSnap's own, not new strings written here.
    expect(find.text('Left half'), findsOneWidget);
    expect(find.text('Top right quarter'), findsOneWidget);

    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();

    expect(r.moves, hasLength(1));
    expect(r.moves.single.$1, 'w1');
    expect(r.moves.single.$2.width, WindowSnap.left.geometryIn(workspace).width);
    expect(r.moves.single.$2.x, WindowSnap.left.geometryIn(workspace).x);
  });

  testWidgets('Maximise names the action, not the current state', (
    WidgetTester tester,
  ) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    expect(find.text('Maximise'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    final r2 = recorder();
    await pumpWindow(tester, r2.intents, state: WindowDisplayState.maximised);
    await rightClickTitleBar(tester);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Maximise'), findsNothing);
  });

  testWidgets('Minimise sends the minimised display state', (
    WidgetTester tester,
  ) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    await tester.tap(find.text('Minimise'));
    await tester.pumpAndSettle();

    expect(r.states, <(String, WindowDisplayState)>[
      ('w1', WindowDisplayState.minimised),
    ]);
  });

  testWidgets('Close closes this window', (WidgetTester tester) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(r.closed, <String>['w1']);
  });

  testWidgets('Fullscreen is absent, not disabled, when unsupported', (
    WidgetTester tester,
  ) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    expect(
      find.text('Fullscreen'),
      findsNothing,
      reason: 'a control that does nothing is worse than no control',
    );
  });

  testWidgets('Fullscreen appears when the host supports it', (
    WidgetTester tester,
  ) async {
    final List<String> entered = <String>[];
    final r = recorder(fullscreen: entered.add);
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    await tester.tap(find.text('Fullscreen'));
    await tester.pumpAndSettle();
    expect(entered, <String>['w1']);
  });

  testWidgets('Close others only appears when there are others', (
    WidgetTester tester,
  ) async {
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    expect(find.text('Close others'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    bool called = false;
    final r2 = recorder();
    await pumpWindow(tester, r2.intents, onCloseOthers: () => called = true);
    await rightClickTitleBar(tester);
    await tester.tap(find.text('Close others'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });

  testWidgets('nothing offers always-on-top or move-to-workspace', (
    WidgetTester tester,
  ) async {
    // Both were asked for and both were cut: there is no always-on-top in the
    // window API and workspaces do not exist. If either ever appears here
    // without an intent behind it, this fails.
    final r = recorder();
    await pumpWindow(tester, r.intents);
    await rightClickTitleBar(tester);
    expect(find.textContaining('always on top', findRichText: true), findsNothing);
    expect(find.textContaining('Always on top'), findsNothing);
    expect(find.textContaining('workspace'), findsNothing);
    expect(find.textContaining('Workspace'), findsNothing);
  });
}
