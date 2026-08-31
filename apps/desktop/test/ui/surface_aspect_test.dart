import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// Android pixels must never be stretched to fill whatever shape the window
/// happens to be. A phone screen squeezed into a wide frame, or a landscape
/// stream squashed into a tall one, is not a cosmetic problem — text and faces
/// distort, and it reads as a broken stream rather than a deliberate fit.
///
/// The rule is aspect-fit containment against `WindowSurface.pixelSize`, with
/// the remaining space left as an intentional black letterbox or pillarbox.
void main() {
  group('orientation swap', _orientationSwapTests);

  const int landscapeW = 1280;
  const int landscapeH = 720;
  const int portraitW = 720;
  const int portraitH = 1280;

  Future<Size> pumpSurface(
    WidgetTester tester, {
    required int pixelWidth,
    required int pixelHeight,
    required Size window,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: window.width,
              height: window.height,
              child: AppWindow(
                window: WorkspaceWindow(
                  session: const WindowSessionState(
                    id: 'w',
                    application: AndroidApplication(
                      packageName: 'com.demo.maps',
                      label: 'Maps',
                    ),
                    status: WindowSessionStatus.streaming,
                    isFocused: true,
                  ),
                  geometry: WindowGeometry(
                    x: 0,
                    y: 0,
                    width: window.width,
                    height: window.height,
                  ),
                  zOrder: 1,
                  surface: WindowSurface(
                    textureId: 1,
                    pixelSize: WindowPixelSize(
                      width: pixelWidth,
                      height: pixelHeight,
                    ),
                  ),
                ),
                intents: WorkspaceIntents(
                  focus: (_) {},
                  raise: (_) {},
                  move: (_, _) {},
                  setDisplayState: (_, _) {},
                  close: (_) {},
                  retry: (_) {},
                ),
                workspaceSize: window,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // The painted rect, not the layout size. `FittedBox` scales its child with
    // a transform, so `getSize` still reports the unscaled 1280x720 while the
    // pixels on screen are much smaller. Corner-to-corner through
    // `localToGlobal` applies the transform and gives what is actually drawn.
    final Finder video = find.byType(Texture);
    final Offset topLeft = tester.getTopLeft(video);
    final Offset bottomRight = tester.getBottomRight(video);
    return Size(bottomRight.dx - topLeft.dx, bottomRight.dy - topLeft.dy);
  }

  /// Asserts the painted video keeps its source ratio and never exceeds the
  /// space it was given.
  void expectAspectFit({
    required Size painted,
    required int pixelWidth,
    required int pixelHeight,
    required String label,
  }) {
    final double source = pixelWidth / pixelHeight;
    final double shown = painted.width / painted.height;
    expect(
      shown,
      closeTo(source, 0.01),
      reason: '$label: video was stretched — source $source, painted $shown',
    );
  }

  const List<(String, Size)> shapes = <(String, Size)>[
    ('tall window', Size(420, 900)),
    ('square window', Size(600, 600)),
    ('wide window', Size(1100, 420)),
  ];

  /// The backend derives each Android display from the settled window ratio
  /// rather than picking one of two presets — long edge 1280, quantised to 16
  /// pixels — so a surface can be almost any shape. Tests that only covered
  /// 16:9 and 9:16 would not have caught a stretch on these.
  const List<(String, int, int)> adaptive = <(String, int, int)>[
    ('768x1280 from a 400x700 window', 768, 1280),
    ('1280x752 from an 800x500 window', 1280, 752),
    ('1280x1280 from a square window', 1280, 1280),
    ('608x1280 from a very tall window', 608, 1280),
  ];

  for (final (String name, int w, int h) in adaptive) {
    testWidgets('an adaptive surface keeps its ratio — $name', (
      WidgetTester tester,
    ) async {
      // Deliberately fitted into a frame of a *different* shape: the point is
      // that the guard holds when the backend's chosen size and the window
      // disagree, which is exactly what happens between a resize and the
      // debounced surface replacement.
      final Size painted = await pumpSurface(
        tester,
        pixelWidth: w,
        pixelHeight: h,
        window: const Size(640, 480),
      );
      expectAspectFit(
        painted: painted,
        pixelWidth: w,
        pixelHeight: h,
        label: name,
      );
      expect(painted.width, lessThanOrEqualTo(640.5));
      expect(painted.height, lessThanOrEqualTo(480.5));
    });
  }

  for (final (String name, Size window) in shapes) {
    testWidgets('a 1280x720 surface keeps its ratio in a $name', (
      WidgetTester tester,
    ) async {
      final Size painted = await pumpSurface(
        tester,
        pixelWidth: landscapeW,
        pixelHeight: landscapeH,
        window: window,
      );
      expectAspectFit(
        painted: painted,
        pixelWidth: landscapeW,
        pixelHeight: landscapeH,
        label: '1280x720 in $name',
      );
      expect(
        painted.width,
        lessThanOrEqualTo(window.width + 0.5),
        reason: 'must fit inside the frame, not overflow it',
      );
    });

    testWidgets('a 720x1280 surface keeps its ratio in a $name', (
      WidgetTester tester,
    ) async {
      final Size painted = await pumpSurface(
        tester,
        pixelWidth: portraitW,
        pixelHeight: portraitH,
        window: window,
      );
      expectAspectFit(
        painted: painted,
        pixelWidth: portraitW,
        pixelHeight: portraitH,
        label: '720x1280 in $name',
      );
      expect(
        painted.height,
        lessThanOrEqualTo(window.height + 0.5),
        reason: 'must fit inside the frame, not overflow it',
      );
    });
  }

  testWidgets('the space left over is a deliberate black surround', (
    WidgetTester tester,
  ) async {
    // Letterbox bars must be black rather than showing the window's own panel
    // colour, or the gap reads as the app failing to fill its frame instead of
    // as a fit.
    await pumpSurface(
      tester,
      pixelWidth: landscapeW,
      pixelHeight: landscapeH,
      window: const Size(420, 900),
    );
    final Finder surround = find.ancestor(
      of: find.byType(FittedBox),
      matching: find.byWidgetPredicate(
        (Widget w) => w is ColoredBox && w.color == const Color(0xFF000000),
      ),
    );
    expect(surround, findsOneWidget);
  });
}

/// The backend replaces the live Android surface when a resized window crosses
/// orientation: a new texture id arrives with a new `pixelSize` under the same
/// session id. The UI should need nothing for this, because it re-reads
/// `pixelSize` on every rebuild — which is worth an assertion rather than an
/// assumption.
void _orientationSwapTests() {
  Widget frame(WindowSurface surface, Size window) => MaterialApp(
    theme: DexTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: window.width,
          height: window.height,
          child: AppWindow(
            window: WorkspaceWindow(
              session: const WindowSessionState(
                id: 'w',
                application: AndroidApplication(
                  packageName: 'com.demo.maps',
                  label: 'Maps',
                ),
                status: WindowSessionStatus.streaming,
                isFocused: true,
              ),
              geometry: WindowGeometry(
                x: 0,
                y: 0,
                width: window.width,
                height: window.height,
              ),
              zOrder: 1,
              surface: surface,
            ),
            intents: WorkspaceIntents(
              focus: (_) {},
              raise: (_) {},
              move: (_, _) {},
              setDisplayState: (_, _) {},
              close: (_) {},
              retry: (_) {},
            ),
            workspaceSize: window,
          ),
        ),
      ),
    ),
  );

  Size painted(WidgetTester tester) {
    final Finder video = find.byType(Texture);
    final Offset a = tester.getTopLeft(video);
    final Offset b = tester.getBottomRight(video);
    return Size(b.dx - a.dx, b.dy - a.dy);
  }

  testWidgets('a surface that swaps orientation is re-fitted, not stretched', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const Size window = Size(700, 700);

    await tester.pumpWidget(
      frame(
        const WindowSurface(
          textureId: 1,
          pixelSize: WindowPixelSize(width: 1280, height: 720),
        ),
        window,
      ),
    );
    await tester.pump();
    final Size landscape = painted(tester);
    expect(landscape.width / landscape.height, closeTo(1280 / 720, 0.01));

    // The backend swaps in a portrait display under the same session: new
    // texture id, new pixel size.
    await tester.pumpWidget(
      frame(
        const WindowSurface(
          textureId: 2,
          pixelSize: WindowPixelSize(width: 720, height: 1280),
        ),
        window,
      ),
    );
    await tester.pump();
    final Size portrait = painted(tester);

    expect(
      portrait.width / portrait.height,
      closeTo(720 / 1280, 0.01),
      reason: 'the UI must follow the new pixelSize, not keep the old ratio',
    );
    expect(
      portrait.height,
      lessThanOrEqualTo(window.height + 0.5),
      reason: 'and still fit inside the frame',
    );
  });
}
