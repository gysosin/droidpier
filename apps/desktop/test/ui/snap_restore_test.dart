import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';

/// Dragging a snapped window back off its edge.
///
/// Snapping replaced a window's geometry outright and nothing remembered what
/// it had been, so a window that had once been snapped to a half kept that
/// half-screen size for the rest of its life however far it was dragged. This
/// covers the way back.
void main() {
  const Size workspace = Size(1200, 800);
  const WindowGeometry free = WindowGeometry(
    x: 300,
    y: 200,
    width: 500,
    height: 400,
  );

  late List<WindowGeometry> moves;
  late WindowGeometry current;

  Future<void> pump(WidgetTester tester) async {
    moves = <WindowGeometry>[];
    current = free;
    tester.view.physicalSize = workspace;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Workspace(
              windows: <WorkspaceWindow>[
                WorkspaceWindow(
                  session: const WindowSessionState(
                    id: 'w',
                    application: AndroidApplication(
                      packageName: 'com.demo.maps',
                      label: 'Maps',
                    ),
                    status: WindowSessionStatus.streaming,
                    isFocused: true,
                  ),
                  geometry: current,
                  zOrder: 1,
                ),
              ],
              intents: WorkspaceIntents(
                focus: (_) {},
                raise: (_) {},
                move: (String _, WindowGeometry g) {
                  moves.add(g);
                  setState(() => current = g);
                },
                setDisplayState: (_, _) {},
                close: (_) {},
                retry: (_) {},
              ),
              emptyChild: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// The title bar sits at the top of the frame, which is where a move drag
  /// has to start.
  Offset titleBarOf(WindowGeometry g) => Offset(g.x + g.width / 2, g.y + 12);

  Future<void> dragBy(WidgetTester tester, Offset from, Offset delta) async {
    final TestGesture g = await tester.startGesture(from);
    for (int i = 0; i < 4; i++) {
      await g.moveBy(delta / 4);
      await tester.pump();
    }
    await g.up();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('a window dragged off a snap gets its old size back', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // Snap it by dragging the title bar into the right edge, which is how a
    // person does it. Ends at x=1190, inside the 24px edge zone, and at y=400
    // so it is the right half rather than a corner.
    await dragBy(tester, titleBarOf(free), const Offset(640, 188));

    final WindowGeometry right = WindowSnap.right.geometryIn(workspace);
    expect(
      current.width,
      closeTo(right.width, 1),
      reason: 'the drag should have snapped it to the right half',
    );

    moves.clear();

    // Now drag it back toward the middle of the desk.
    await dragBy(tester, titleBarOf(current), const Offset(-400, 300));

    expect(moves, isNotEmpty);
    expect(
      moves.last.width,
      closeTo(free.width, 1),
      reason: 'the pre-snap width should come back, not the half-screen width',
    );
    expect(moves.last.height, closeTo(free.height, 1));
  });

  testWidgets('a window never snapped keeps its size while dragged', (
    WidgetTester tester,
  ) async {
    // The restore must not fire for an ordinary drag.
    await pump(tester);
    await dragBy(tester, titleBarOf(free), const Offset(-120, 40));

    expect(moves, isNotEmpty);
    expect(moves.last.width, closeTo(free.width, 1));
    expect(moves.last.height, closeTo(free.height, 1));
  });
}
