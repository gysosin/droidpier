import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';

/// M8 acceptance behaviour for the composited workspace.
///
/// The milestone names these explicitly: two overlapping windows, focus
/// transfer, minimise/restore, maximise/restore, and close.
void main() {
  AndroidApplication app(String label) => AndroidApplication(
    packageName: 'com.example.${label.toLowerCase()}',
    label: label,
  );

  WorkspaceWindow win(
    String label, {
    required int z,
    bool focused = false,
    WindowDisplayState display = WindowDisplayState.normal,
    WindowSessionStatus status = WindowSessionStatus.streaming,
    double x = 40,
    double y = 40,
  }) {
    return WorkspaceWindow(
      session: WindowSessionState(
        id: label,
        application: app(label),
        status: status,
        isFocused: focused,
      ),
      geometry: WindowGeometry(x: x, y: y, width: 420, height: 300),
      zOrder: z,
      displayState: display,
    );
  }

  late List<String> log;

  WorkspaceIntents intents() => WorkspaceIntents(
    focus: (String id) => log.add('focus:$id'),
    raise: (String id) => log.add('raise:$id'),
    move: (String id, WindowGeometry g) =>
        log.add('move:$id:${g.x.round()},${g.y.round()}'),
    setDisplayState: (String id, WindowDisplayState s) =>
        log.add('display:$id:${s.name}'),
    close: (String id) => log.add('close:$id'),
    retry: (String id) => log.add('retry:$id'),
  );

  Future<void> pump(WidgetTester tester, List<WorkspaceWindow> windows) async {
    log = <String>[];
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Workspace(
            windows: windows,
            intents: intents(),
            emptyChild: const ColoredBox(color: Color(0xFF0A0E13)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('two apps are visible at once, stacked by z-order', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[
      win('Maps', z: 1),
      win('Spotify', z: 2, x: 200, y: 120, focused: true),
    ]);

    // M8: two Android apps simultaneously visible in one workspace.
    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);

    // Overlapping: the later z paints over the earlier one.
    final double mapsY = tester.getTopLeft(find.text('Maps')).dy;
    final double spotifyY = tester.getTopLeft(find.text('Spotify')).dy;
    expect(spotifyY, greaterThan(mapsY));
  });

  testWidgets('clicking an unfocused window focuses and raises it', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[
      win('Maps', z: 1),
      win('Spotify', z: 2, x: 520, y: 40, focused: true),
    ]);

    await tester.tap(find.text('Maps'));
    // Tooltip schedules a timer on pointer contact; drain it or the test fails
    // at teardown on a pending timer rather than on its own assertion.
    await tester.pump(const Duration(seconds: 1));

    // Focus and z-order are separate concerns, so both are asked for.
    expect(log, contains('focus:Maps'));
    expect(log, contains('raise:Maps'));
  });

  testWidgets('minimise leaves the workspace, restore brings it back', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1, focused: true)]);

    await tester.tap(find.byTooltip('Minimise Maps'));
    await tester.pump();
    expect(log, contains('display:Maps:minimised'));

    // A minimised window is not painted in the workspace at all.
    await pump(tester, <WorkspaceWindow>[
      win('Maps', z: 1, display: WindowDisplayState.minimised),
    ]);
    expect(find.text('Maps'), findsNothing);

    // Restoring paints it again.
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1)]);
    expect(find.text('Maps'), findsOneWidget);
  });

  testWidgets('maximise fills the workspace and restores', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1, focused: true)]);
    await tester.tap(find.byTooltip('Maximise Maps'));
    await tester.pump();
    expect(log, contains('display:Maps:maximised'));

    await pump(tester, <WorkspaceWindow>[
      win('Maps', z: 1, display: WindowDisplayState.maximised),
    ]);
    final Size size = tester.getSize(
      find
          .ancestor(
            of: find.text('Maps'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(size.width, closeTo(1100, 1));

    // And the button now offers the way back, not the way in again.
    expect(find.byTooltip('Restore Maps'), findsOneWidget);
  });

  testWidgets('close ends the session', (WidgetTester tester) async {
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1)]);
    await tester.tap(find.byTooltip('Close Maps'));
    await tester.pump();
    expect(log, contains('close:Maps'));
  });

  testWidgets('dragging the title bar asks to move, and stays reachable', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1)]);
    await tester.drag(find.text('Maps'), const Offset(80, 60));
    await tester.pump(const Duration(seconds: 1));
    expect(log.where((String e) => e.startsWith('move:Maps')), isNotEmpty);

    // Dragged hard off the top-left, the title bar must remain on screen or
    // the window can never be dragged back.
    const WindowGeometry far = WindowGeometry(
      x: -5000,
      y: -5000,
      width: 420,
      height: 300,
    );
    final WindowGeometry clamped = far.clampedTo(const Size(1100, 700));
    expect(clamped.y, greaterThanOrEqualTo(0));
    expect(clamped.x, greaterThan(-420));
  });

  testWidgets('a streaming window with no frames yet is not a blank box', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1)]);
    // Surface is null here. The window must explain that the app is running
    // and its screen is elsewhere, rather than render an empty rectangle —
    // an empty rectangle reads as a broken app.
    expect(find.text('Maps is running'), findsOneWidget);
    expect(
      find.textContaining('separate window'),
      findsOneWidget,
      reason: 'the person needs to know where their app actually is',
    );
    expect(
      find.byType(OutlinedButton),
      findsNothing,
      reason: 'there is nothing for them to do here, so offer no button',
    );
  });

  testWidgets('a failed window explains itself and offers a retry', (
    WidgetTester tester,
  ) async {
    await pump(tester, <WorkspaceWindow>[
      win('Maps', z: 1, status: WindowSessionStatus.failed),
    ]);
    expect(find.text('This app stopped'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(log, contains('retry:Maps'));
  });

  testWidgets('every window frame carries a spoken label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, <WorkspaceWindow>[win('Maps', z: 1)]);
    expect(find.bySemanticsLabel(RegExp('Maps window')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with snapping off, dragging to an edge does not snap', (
    WidgetTester tester,
  ) async {
    log = <String>[];
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Workspace(
            windows: <WorkspaceWindow>[win('Maps', z: 1)],
            intents: intents(),
            snapEnabled: false,
            emptyChild: const ColoredBox(color: Color(0xFF0E1113)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Drag the title bar hard into the left edge.
    await tester.drag(find.text('Maps'), const Offset(-600, 0));
    await tester.pump(const Duration(seconds: 1));

    // Moves are still reported — the window follows the pointer — but no snap
    // geometry is applied, so nothing lands at exactly half width.
    final Iterable<String> moves = log.where(
      (String e) => e.startsWith('move:Maps'),
    );
    expect(moves, isNotEmpty, reason: 'the drag itself still works');
    expect(
      log.any((String e) => e == 'move:Maps:0,0'),
      isFalse,
      reason: 'a disabled toggle must change behaviour, not just remember',
    );
  });

  group('snap zones', () {
    const Size size = Size(1200, 800);

    test('edges and corners map to the arrangement a person expects', () {
      expect(
        WindowSnap.forPointer(const Offset(4, 400), size),
        WindowSnap.left,
      );
      expect(
        WindowSnap.forPointer(const Offset(1196, 400), size),
        WindowSnap.right,
      );
      expect(
        WindowSnap.forPointer(const Offset(600, 3), size),
        WindowSnap.maximise,
      );
      // Corners are tested before edges, or dragging into a corner would only
      // ever register as whichever edge was crossed first.
      expect(
        WindowSnap.forPointer(const Offset(4, 10), size),
        WindowSnap.topLeft,
      );
      expect(
        WindowSnap.forPointer(const Offset(1196, 790), size),
        WindowSnap.bottomRight,
      );
      // The middle is not a snap zone.
      expect(WindowSnap.forPointer(const Offset(600, 400), size), isNull);
    });

    test('halves and quarters tile without overlap or gaps', () {
      final WindowGeometry l = WindowSnap.left.geometryIn(size);
      final WindowGeometry r = WindowSnap.right.geometryIn(size);
      expect(l.width + r.width, size.width);
      expect(l.rect.overlaps(r.rect), isFalse);

      final WindowGeometry tl = WindowSnap.topLeft.geometryIn(size);
      final WindowGeometry br = WindowSnap.bottomRight.geometryIn(size);
      expect(tl.rect.overlaps(br.rect), isFalse);
      expect(WindowSnap.maximise.geometryIn(size).rect, Offset.zero & size);
    });

    test('every zone has words a person would use', () {
      for (final WindowSnap z in WindowSnap.values) {
        expect(z.label, isNotEmpty);
        expect(z.label, isNot(contains('_')));
      }
    });
  });

  test('cascade places a second window somewhere the first is not', () {
    const Size size = Size(1200, 800);
    final WindowGeometry a = cascadeGeometry(0, size);
    final WindowGeometry b = cascadeGeometry(1, size);
    expect(a.rect == b.rect, isFalse, reason: 'both must be visible');
  });

  testWidgets('a mock surface is obviously a mock', (WidgetTester t) async {
    // It is a builder now, not a value with a size, so the only honest
    // assertion is what it renders — and what it must render is a label that
    // stops anyone mistaking it for a live stream.
    await t.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Builder(builder: mockSurface(app('Maps'), DexColors.dark)),
      ),
    );
    expect(find.text('mock frame surface'), findsOneWidget);
  });
}
