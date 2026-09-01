import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';

/// The per-window Portrait / Landscape control.
void main() {
  const Size workspace = Size(1400, 900);

  WorkspaceWindow makeWindow({
    required WindowGeometry geometry,
    WindowDisplayState state = WindowDisplayState.normal,
  }) => WorkspaceWindow(
    session: WindowSessionState(
      id: 'w1',
      application: const AndroidApplication(
        packageName: 'com.google.android.youtube',
        label: 'YouTube',
      ),
      status: WindowSessionStatus.streaming,
      geometry: geometry,
      isFocused: true,
    ),
    geometry: geometry,
    zOrder: 1,
    displayState: state,
    previewBuilder: (BuildContext _) => const ColoredBox(color: Colors.black),
  );

  late List<(String, WindowGeometry)> moves;
  late List<(String, WindowDisplayState)> states;

  WorkspaceIntents intents() {
    moves = <(String, WindowGeometry)>[];
    states = <(String, WindowDisplayState)>[];
    return WorkspaceIntents(
      focus: (_) {},
      raise: (_) {},
      move: (String id, WindowGeometry g) => moves.add((id, g)),
      setDisplayState: (String id, WindowDisplayState s) => states.add((id, s)),
      close: (_) {},
      retry: (_) {},
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required WindowGeometry geometry,
    WindowDisplayState state = WindowDisplayState.normal,
  }) async {
    await tester.binding.setSurfaceSize(workspace);
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
                  window: makeWindow(geometry: geometry, state: state),
                  intents: intents(),
                  workspaceSize: workspace,
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

  const WindowGeometry landscape = WindowGeometry(
    x: 100,
    y: 80,
    width: 800,
    height: 500,
  );

  testWidgets('a landscape window offers a Portrait control', (
    WidgetTester tester,
  ) async {
    await pump(tester, geometry: landscape);
    expect(find.byTooltip('Portrait YouTube'), findsOneWidget);
    expect(find.byTooltip('Landscape YouTube'), findsNothing);
  });

  testWidgets('a portrait window offers a Landscape control', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      geometry: const WindowGeometry(x: 100, y: 40, width: 420, height: 760),
    );
    expect(find.byTooltip('Landscape YouTube'), findsOneWidget);
  });

  testWidgets('pressing it sends a rotated geometry', (
    WidgetTester tester,
  ) async {
    await pump(tester, geometry: landscape);
    await tester.tap(find.byTooltip('Portrait YouTube'));
    await tester.pump();

    expect(moves, hasLength(1));
    final WindowGeometry out = moves.single.$2;
    expect(
      out.height,
      greaterThan(out.width),
      reason: 'a Portrait press should produce a portrait window',
    );
  });

  testWidgets('rotating a maximised window leaves maximise first', (
    WidgetTester tester,
  ) async {
    // A window still flagged maximised but no longer filling the desk would
    // confuse every later Restore.
    await pump(
      tester,
      geometry: landscape,
      state: WindowDisplayState.maximised,
    );
    await tester.tap(find.byTooltip('Portrait YouTube'));
    await tester.pump();

    expect(states, <(String, WindowDisplayState)>[
      ('w1', WindowDisplayState.normal),
    ]);
    expect(moves, hasLength(1));
  });

  testWidgets('a normal window is not needlessly told to become normal', (
    WidgetTester tester,
  ) async {
    await pump(tester, geometry: landscape);
    await tester.tap(find.byTooltip('Portrait YouTube'));
    await tester.pump();
    expect(states, isEmpty);
  });

  testWidgets('the context menu offers it too', (WidgetTester tester) async {
    await pump(tester, geometry: landscape);
    await tester.tapAt(tester.getCenter(find.text('YouTube')), buttons: 2);
    await tester.pumpAndSettle();
    expect(find.text('Portrait'), findsOneWidget);
  });
}
