import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';

/// Getting back out of fullscreen.
///
/// The stage used to be a bare black rectangle holding the video and nothing
/// else. Esc and F11 both leave it, and neither is discoverable — so anyone who
/// pressed F11 once was stuck looking at a screen with no visible way out.
void main() {
  WorkspaceWindow makeWindow() => WorkspaceWindow(
    session: const WindowSessionState(
      id: 'w1',
      application: AndroidApplication(
        packageName: 'com.google.android.youtube',
        label: 'YouTube',
      ),
      status: WindowSessionStatus.streaming,
      geometry: WindowGeometry(x: 0, y: 0, width: 800, height: 600),
      isFocused: true,
    ),
    geometry: const WindowGeometry(x: 0, y: 0, width: 800, height: 600),
    zOrder: 1,
    previewBuilder: (BuildContext _) => const ColoredBox(color: Colors.black),
  );

  WorkspaceIntents intents() => WorkspaceIntents(
    focus: (_) {},
    raise: (_) {},
    move: (_, _) {},
    setDisplayState: (_, _) {},
    close: (_) {},
    retry: (_) {},
  );

  Future<void> pumpStage(
    WidgetTester tester, {
    required VoidCallback onExit,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: WindowStage(
          window: makeWindow(),
          intents: intents(),
          onExit: onExit,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('entering fullscreen says how to leave it', (
    WidgetTester tester,
  ) async {
    await pumpStage(tester, onExit: () {});
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Esc'),
      findsWidgets,
      reason: 'the way out has to be stated, not guessed',
    );
  });

  testWidgets('the hint gets out of the way on its own', (
    WidgetTester tester,
  ) async {
    // It is a hint, not a permanent overlay on a video.
    await pumpStage(tester, onExit: () {});
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Esc'), findsWidgets);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));

    // Faded, not removed — AnimatedOpacity keeps the subtree mounted, so
    // findsNothing would pass only by accident and fail here. Presence is not
    // visibility; the opacity is the thing that decides whether anyone sees it.
    final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(fade.opacity, 0);
  });

  testWidgets('an exit control is reachable with the pointer', (
    WidgetTester tester,
  ) async {
    // After the hint has gone, moving the pointer to the top brings back a
    // real control — the same bargain every video player makes.
    await pumpStage(tester, onExit: () {});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(const Offset(600, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
  });

  testWidgets('the exit control leaves fullscreen', (
    WidgetTester tester,
  ) async {
    int exits = 0;
    await pumpStage(tester, onExit: () => exits++);

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(const Offset(600, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('the app being viewed is named while the chrome shows', (
    WidgetTester tester,
  ) async {
    await pumpStage(tester, onExit: () {});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(const Offset(600, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('YouTube'), findsOneWidget);
  });
}
