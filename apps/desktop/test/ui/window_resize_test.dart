import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';

/// Windows once could not be resized by dragging their chrome. These drag
/// every supported edge and corner to a size that is not a
/// preset, and assert the geometry that reaches `intents.move` — which is what
/// the shell forwards to `facade.moveWindow`.
void main() {
  group('backend throttle', _throttleTests);

  const Size workspace = Size(1200, 800);
  const WindowGeometry start = WindowGeometry(
    x: 300,
    y: 200,
    width: 500,
    height: 400,
  );

  late List<WindowGeometry> moves;

  Future<void> pump(WidgetTester tester) async {
    moves = <WindowGeometry>[];
    tester.view.physicalSize = workspace;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Geometry is echoed back, exactly as `AppShell` does: it updates its
    // local copy on `move` so the frame tracks the pointer, and the backend
    // confirms. Recording moves without feeding them back would let a
    // multi-step drag silently apply every delta to the original rect, which
    // is the opposite of the bug worth catching.
    WindowGeometry current = start;

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

  /// Drags from a point in workspace coordinates by [delta].
  Future<void> dragFrom(WidgetTester tester, Offset from, Offset delta) async {
    final TestGesture g = await tester.startGesture(from);
    // Several steps: a single jump can be read as a fling and, more
    // importantly, one delta would hide an accumulation bug.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(delta / 4);
    }
    await g.up();
    await tester.pump();
  }

  WindowGeometry last() => moves.last;

  testWidgets('the right edge is grabbable and widens the window', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width, start.y + start.height / 2),
      const Offset(120, 0),
    );
    expect(moves, isNotEmpty, reason: 'the edge must be hit-testable at all');
    expect(last().width, closeTo(start.width + 120, 1));
    expect(last().height, closeTo(start.height, 1));
    expect(last().x, closeTo(start.x, 1));
  });

  testWidgets('the left edge moves the origin and keeps the right edge still', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x, start.y + start.height / 2),
      const Offset(-60, 0),
    );
    expect(moves, isNotEmpty);
    expect(last().x, closeTo(start.x - 60, 1));
    expect(last().width, closeTo(start.width + 60, 1));
    expect(
      last().x + last().width,
      closeTo(start.x + start.width, 1),
      reason: 'dragging the left edge must not move the right one',
    );
  });

  testWidgets('the bottom edge is grabbable and lengthens the window', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width / 2, start.y + start.height),
      const Offset(0, 90),
    );
    expect(moves, isNotEmpty);
    expect(last().height, closeTo(start.height + 90, 1));
    expect(last().width, closeTo(start.width, 1));
  });

  testWidgets('the top edge moves the origin and keeps the bottom still', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width / 2, start.y),
      const Offset(0, -50),
    );
    expect(moves, isNotEmpty);
    expect(last().y, closeTo(start.y - 50, 1));
    expect(last().height, closeTo(start.height + 50, 1));
    expect(last().y + last().height, closeTo(start.y + start.height, 1));
  });

  testWidgets('the bottom-right corner resizes both axes at once', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width, start.y + start.height),
      const Offset(77, 43),
    );
    expect(moves, isNotEmpty);
    expect(last().width, closeTo(start.width + 77, 1));
    expect(last().height, closeTo(start.height + 43, 1));
  });

  testWidgets('the top-left corner resizes and moves the origin', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(tester, Offset(start.x, start.y), const Offset(-35, -25));
    expect(moves, isNotEmpty);
    expect(last().x, closeTo(start.x - 35, 1));
    expect(last().y, closeTo(start.y - 25, 1));
    expect(last().width, closeTo(start.width + 35, 1));
    expect(last().height, closeTo(start.height + 25, 1));
  });

  testWidgets('the top-right corner keeps the left edge and the bottom still', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width, start.y),
      const Offset(40, -30),
    );
    expect(moves, isNotEmpty);
    expect(last().x, closeTo(start.x, 1));
    expect(last().width, closeTo(start.width + 40, 1));
    expect(last().y, closeTo(start.y - 30, 1));
    expect(last().y + last().height, closeTo(start.y + start.height, 1));
  });

  testWidgets('the bottom-left corner keeps the right edge and the top still', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x, start.y + start.height),
      const Offset(-45, 55),
    );
    expect(moves, isNotEmpty);
    expect(last().x, closeTo(start.x - 45, 1));
    expect(last().width, closeTo(start.width + 45, 1));
    expect(last().y, closeTo(start.y, 1));
    expect(last().height, closeTo(start.height + 55, 1));
  });

  testWidgets('the frame tracks the pointer through the drag, not just at the '
      'end', (WidgetTester tester) async {
    // Every step must produce geometry, and the frame must be *at* that
    // geometry in the same frame. `AnimatedPositioned` used to retarget a
    // 180 ms curve on each echo, so the window chased the pointer instead of
    // following it — which is a large part of what reads as lag.
    await pump(tester);
    final Offset from = Offset(
      start.x + start.width,
      start.y + start.height / 2,
    );
    final TestGesture g = await tester.startGesture(from);
    final List<double> frameWidths = <double>[];
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(25, 0));
      await tester.pump();
      frameWidths.add(tester.getSize(find.byType(AppWindow)).width);
    }
    await g.up();
    await tester.pump();

    expect(
      moves.length,
      greaterThanOrEqualTo(4),
      reason: 'each pointer move must report geometry, not only the release',
    );
    // Strictly increasing: a trailing animation would repeat or lag a value.
    for (int i = 1; i < frameWidths.length; i++) {
      expect(
        frameWidths[i],
        greaterThan(frameWidths[i - 1]),
        reason: 'the frame must widen on every step, not catch up later',
      );
    }
    expect(
      frameWidths.last,
      closeTo(start.width + 100, 1),
      reason: 'and it must be at the final size immediately on release',
    );
  });

  testWidgets('a window cannot be shrunk below its minimum', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await dragFrom(
      tester,
      Offset(start.x + start.width, start.y + start.height),
      const Offset(-900, -900),
    );
    expect(moves, isNotEmpty);
    expect(
      last().width,
      greaterThanOrEqualTo(WorkspaceGeometry.minimum.width - 0.5),
    );
    expect(
      last().height,
      greaterThanOrEqualTo(WorkspaceGeometry.minimum.height - 0.5),
    );
  });

  testWidgets('the title bar buttons still win over the resize edge', (
    WidgetTester tester,
  ) async {
    // The handles were moved below the window precisely because, painted on
    // top, they swallowed clicks on close. Whatever the fix, that must not
    // come back.
    await pump(tester);
    final Finder close = find.byTooltip('Close Maps');
    expect(close, findsOneWidget);
    await tester.tapAt(tester.getCenter(close));
    await tester.pump();
    expect(
      moves,
      isEmpty,
      reason: 'pressing a title-bar button must not resize the window',
    );
  });
}

/// The shell forwards geometry to the backend on a throttle while the frame
/// tracks the pointer immediately. Every `moveWindow` makes the controller
/// publish a snapshot, which rebuilds the whole shell — desk, widgets, taskbar
/// and every BackdropFilter behind them. At pointer rate that was sixty to a
/// hundred full-tree repaints a second on top of a live video texture.
void _throttleTests() {
  testWidgets('a drag does not send one backend move per pointer event', (
    WidgetTester tester,
  ) async {
    final List<String> sent = <String>[];
    final _CountingFacade facade = _CountingFacade(sent: sent);
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
                now: DateTime.utc(2026, 8, 25, 11),
              ),
        ),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // A window has to exist before there is a title bar to drag.
    await facade.launchApplication(
      facade.snapshot.applications
          .firstWhere((AndroidApplication a) => !a.isSystemApp)
          .packageName,
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    final Finder frame = find.byType(AppWindow);
    expect(frame, findsOneWidget, reason: 'the launch should open one window');
    sent.clear();

    // Thirty pointer moves inside a single throttle window.
    final Offset from = tester.getCenter(find.byType(AppWindow));
    final TestGesture g = await tester.startGesture(
      Offset(from.dx, tester.getTopLeft(frame).dy + 10),
    );
    for (int i = 0; i < 30; i++) {
      await g.moveBy(const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 1));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      sent.length,
      lessThan(10),
      reason: 'thirty pointer events must not become thirty backend commands',
    );
    expect(
      sent,
      isNotEmpty,
      reason: 'but the final position must still reach the backend',
    );
  });
}

/// Counts `moveWindow` calls and otherwise behaves like the mock.
class _CountingFacade extends MockOpenDexFacade {
  _CountingFacade({required this.sent}) : super(scenario: MockScenario.ready);

  final List<String> sent;

  @override
  Future<VoidResult> moveWindow(String sessionId, WindowGeometry geometry) {
    sent.add(sessionId);
    return super.moveWindow(sessionId, geometry);
  }
}
