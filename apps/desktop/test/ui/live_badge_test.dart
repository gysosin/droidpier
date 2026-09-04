import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// The window title used to carry the screen-update rate. A bare "9 fps" reads
/// as a performance grade and was twice mistaken for a fault — once after it
/// had already been relabelled with an explanatory tooltip. Measuring scrcpy
/// alone, with no FFmpeg, FIFO, texture or Flutter in the path, produced 7.1
/// frames a second on the same static video: the number was honest, the
/// presentation was not.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required WindowSessionStatus status,
    double? rate,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 420,
            child: AppWindow(
              window: WorkspaceWindow(
                session: WindowSessionState(
                  id: 'w',
                  application: const AndroidApplication(
                    packageName: 'com.google.android.youtube',
                    label: 'YouTube',
                  ),
                  status: status,
                  isFocused: true,
                ),
                geometry: const WindowGeometry(
                  x: 0,
                  y: 0,
                  width: 620,
                  height: 420,
                ),
                zOrder: 1,
                surface: const WindowSurface(
                  textureId: 1,
                  pixelSize: WindowPixelSize(width: 1280, height: 720),
                ),
                presentedFramesPerSecond: rate,
              ),
              intents: WorkspaceIntents(
                focus: (_) {},
                raise: (_) {},
                move: (_, _) {},
                setDisplayState: (_, _) {},
                close: (_) {},
                retry: (_) {},
              ),
              workspaceSize: const Size(620, 420),
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

  testWidgets('the title says Live, not a rate', (WidgetTester tester) async {
    await pump(tester, status: WindowSessionStatus.streaming, rate: 9);
    expect(find.text('Live'), findsOneWidget);
    expect(
      find.textContaining('/s'),
      findsNothing,
      reason: 'a bare rate in the title reads as a grade, not a measurement',
    );
    expect(find.textContaining('fps'), findsNothing);
  });

  testWidgets('a low rate does not change what the title says', (
    WidgetTester tester,
  ) async {
    // Nine and sixty are both healthy; the difference is whether the screen is
    // moving. The title must not imply otherwise.
    await pump(tester, status: WindowSessionStatus.streaming, rate: 60);
    expect(find.text('Live'), findsOneWidget);
    await pump(tester, status: WindowSessionStatus.streaming, rate: 4);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('zero still reads as live', (WidgetTester tester) async {
    // Android emits frames on change, so a paused video and a dead pipeline
    // look identical from here. Inferring death from zero would tell the person
    // their working app had stopped.
    await pump(tester, status: WindowSessionStatus.streaming, rate: 0);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('the rate is still available for diagnosis, on hover', (
    WidgetTester tester,
  ) async {
    await pump(tester, status: WindowSessionStatus.streaming, rate: 9);
    final Tooltip tip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('Live'), matching: find.byType(Tooltip)),
    );
    expect(tip.message, contains('9'));
    expect(
      tip.message,
      contains('count changes, not speed'),
      reason: 'the number needs its meaning attached wherever it appears',
    );
    expect(
      tip.message,
      contains('presented'),
      reason:
          'every rate is named. This tooltip once read "Screen updates" while '
          'it was fed the produced rate, which was five times larger — the '
          'most visible number in the app naming the wrong quantity. All three '
          'now appear together, each labelled, so no one number can be read as '
          'another.',
    );
  });

  testWidgets('a window that is not streaming claims nothing', (
    WidgetTester tester,
  ) async {
    await pump(tester, status: WindowSessionStatus.reconnecting, rate: 0);
    expect(
      find.text('Live'),
      findsNothing,
      reason: 'saying Live while reconnecting would be a lie',
    );
  });
}
