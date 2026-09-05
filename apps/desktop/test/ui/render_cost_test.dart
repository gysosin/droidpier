import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/phone_mirror.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// A `BackdropFilter` re-reads and re-blurs its backdrop on every frame the
/// backdrop changes. Over the static wallpaper that is free. Over a 60 fps
/// video texture it is a full-panel blur sixty times a second, for decoration —
/// on a machine already spending most of a core on software H.264 decode.
void main() {
  Finder blurs() => find.byType(BackdropFilter);

  group('glass over live video', () {
    Future<void> pumpMirror(
      WidgetTester tester, {
      required bool overVideo,
      DisplayMirrorState mirror = const DisplayMirrorState(),
    }) async {
      final MockOpenDexFacade facade = MockOpenDexFacade(
        scenario: MockScenario.ready,
      );
      addTearDown(facade.dispose);
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: DexTheme.dark(),
          home: Scaffold(
            body: PhoneMirror(
              snapshot: facade.snapshot.copyWith(displayMirror: mirror),
              now: DateTime.utc(2026, 8, 25, 14),
              onClose: () {},
              onLaunch: (_) {},
              onRetry: () {},
              overVideo: overVideo,
            ),
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('a live mirror is flat, whatever is behind it', (
      WidgetTester tester,
    ) async {
      await pumpMirror(
        tester,
        overVideo: false,
        mirror: const DisplayMirrorState(
          status: DisplayMirrorStatus.streaming,
          surface: WindowSurface(
            textureId: 9,
            pixelSize: WindowPixelSize(width: 540, height: 1170),
          ),
        ),
      );
      expect(find.byType(Texture), findsOneWidget);
      expect(
        blurs(),
        findsNothing,
        reason:
            'the phone paints thirty frames a second into this frame; a blur '
            'above them re-blurs the desk on every one',
      );
    });

    testWidgets('the phone mirror blurs over a static wallpaper', (
      WidgetTester tester,
    ) async {
      await pumpMirror(tester, overVideo: false);
      expect(
        blurs(),
        findsWidgets,
        reason: 'blurring a still wallpaper costs nothing and looks right',
      );
    });

    testWidgets('the phone mirror stops blurring while a window streams', (
      WidgetTester tester,
    ) async {
      await pumpMirror(tester, overVideo: true);
      expect(
        blurs(),
        findsNothing,
        reason: 'this blur would re-run on every decoded frame beneath it',
      );
    });
  });

  group('video layer', () {
    testWidgets('the stream is its own repaint layer, filtered bilinearly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: DexTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 480,
              child: AppWindow(
                window: const WorkspaceWindow(
                  session: WindowSessionState(
                    id: 'w',
                    application: AndroidApplication(
                      packageName: 'com.demo.maps',
                      label: 'Maps',
                    ),
                    status: WindowSessionStatus.streaming,
                    isFocused: true,
                  ),
                  geometry: WindowGeometry(x: 0, y: 0, width: 640, height: 480),
                  zOrder: 1,
                  surface: WindowSurface(
                    textureId: 7,
                    pixelSize: WindowPixelSize(width: 1280, height: 720),
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
                workspaceSize: const Size(640, 480),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder video = find.byType(Texture);
      expect(video, findsOneWidget);

      // The stream must be its own composited layer, or every delivered frame
      // rasterises the desk behind it. Flutter already guarantees this —
      // `TextureBox.isRepaintBoundary` is true — so this asserts the property
      // rather than the presence of a wrapper. An earlier version of this test
      // asserted a `RepaintBoundary` ancestor, which passed on wrappers higher
      // up the tree and would have kept passing if the texture stopped being a
      // boundary at all.
      expect(
        tester.renderObject(video).isRepaintBoundary,
        isTrue,
        reason: 'a new frame must not rasterise anything but itself',
      );

      expect(
        tester.widget<Texture>(video).filterQuality,
        ui.FilterQuality.low,
        reason: 'the texture is rarely 1:1 with the window; nearest shimmers',
      );
    });
  });
}
