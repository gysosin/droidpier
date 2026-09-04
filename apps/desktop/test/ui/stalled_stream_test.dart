import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';

/// A window that is streaming, has a texture, and never receives a frame.
///
/// This is the reported defect's symptom: the frame appears with the right
/// title and a lit Live badge, and the body stays solid black forever. The
/// root cause is in the video path, but the interface made it worse by saying
/// nothing — a black rectangle is indistinguishable from an app that happens
/// to be showing black.
Future<void> _loadFonts() async {
  final String root =
      Platform.environment['FLUTTER_ROOT'] ??
      Directory('../../.tools/flutter').absolute.path;
  final File icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader l = FontLoader('MaterialIcons');
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await l.load();
  }
  const Map<String, List<String>> families = <String, List<String>>{
    'Lucide': <String>['assets/icons/lucide.ttf'],
    'InstrumentSans': <String>['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final MapEntry<String, List<String>> e in families.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String path in e.value) {
      final File f = File(path);
      if (f.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  WorkspaceWindow win({required double? fps}) => WorkspaceWindow(
    session: const WindowSessionState(
      id: 'w1',
      application: AndroidApplication(
        packageName: 'com.example.notes',
        label: 'Notes',
      ),
      status: WindowSessionStatus.streaming,
      isFocused: true,
    ),
    geometry: const WindowGeometry(x: 40, y: 40, width: 420, height: 300),
    zOrder: 1,
    surface: const WindowSurface(
      textureId: 1,
      pixelSize: WindowPixelSize(width: 1080, height: 1920),
    ),
    presentedFramesPerSecond: fps,
  );

  Future<void> pump(WidgetTester tester, WorkspaceWindow w) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Workspace(
            windows: <WorkspaceWindow>[w],
            intents: WorkspaceIntents(
              focus: (_) {},
              raise: (_) {},
              move: (_, _) {},
              setDisplayState: (_, _) {},
              close: (_) {},
              retry: (_) {},
            ),
            emptyChild: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    // Past the fade, so a healthy stream has had every chance to cancel it.
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('a measured zero on a window that never painted says so', (
    WidgetTester tester,
  ) async {
    await pump(tester, win(fps: 0));
    expect(find.textContaining('No video'), findsOneWidget);
  });

  testWidgets('an unmeasured rate accuses nobody', (WidgetTester tester) async {
    // Null is not zero. The backend emits a number on every completed sample,
    // so null means no interval has finished — which is every window that has
    // only just opened.
    await pump(tester, win(fps: null));
    expect(find.textContaining('No video'), findsNothing);
  });

  testWidgets('a still app is not a broken one', (WidgetTester tester) async {
    // The trap this nearly walked into. A motionless app — a paused video, a
    // page nobody is scrolling — presents zero frames in an interval and is
    // working perfectly. Only a window that has *never* painted is broken.
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Workspace(
            windows: <WorkspaceWindow>[win(fps: 42)],
            intents: WorkspaceIntents(
              focus: (_) {},
              raise: (_) {},
              move: (_, _) {},
              setDisplayState: (_, _) {},
              close: (_) {},
              retry: (_) {},
            ),
            emptyChild: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    // It painted, and then went still.
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Workspace(
            windows: <WorkspaceWindow>[win(fps: 0)],
            intents: WorkspaceIntents(
              focus: (_) {},
              raise: (_) {},
              move: (_, _) {},
              setDisplayState: (_, _) {},
              close: (_) {},
              retry: (_) {},
            ),
            emptyChild: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('No video'), findsNothing);
  });

  testWidgets('a stream that is delivering says nothing', (
    WidgetTester tester,
  ) async {
    await pump(tester, win(fps: 58.5));
    expect(find.textContaining('No video'), findsNothing);
  });

  testWidgets('the notice is not a dead end', (WidgetTester tester) async {
    await pump(tester, win(fps: 0));
    // Something to press. A message with no action leaves the person with a
    // black rectangle and a sentence about it.
    expect(find.text('Reopen'), findsOneWidget);
  });

  testWidgets('stalled window, dark', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester, win(fps: 0));
    await expectLater(
      find.byType(Workspace),
      matchesGoldenFile('goldens/stalled_stream_dark.png'),
    );
  }, tags: <String>['golden']);
}

// Rendered so the notice can be looked at rather than trusted. A message that
// sits unreadably over a black rectangle would pass every assertion above.
