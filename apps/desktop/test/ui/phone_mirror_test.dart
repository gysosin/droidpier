import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/phone_mirror.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The mirror frame is honest about what it holds: the phone's real frames
/// when there are any, and otherwise a plain account of why not.
void main() {
  const WindowSurface surface = WindowSurface(
    textureId: 7,
    pixelSize: WindowPixelSize(width: 540, height: 1170),
  );

  Future<void> pump(
    WidgetTester tester, {
    required DisplayMirrorState mirror,
    VoidCallback? onRetry,
    bool overVideo = false,
  }) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: PhoneMirror(
              snapshot: facade.snapshot.copyWith(displayMirror: mirror),
              now: DateTime(2026, 9, 5, 10, 8),
              overVideo: overVideo,
              onClose: () {},
              onLaunch: (_) {},
              onRetry: onRetry ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('streaming draws the phone texture, flat and low-filtered', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      mirror: const DisplayMirrorState(
        status: DisplayMirrorStatus.streaming,
        surface: surface,
      ),
    );
    final Finder video = find.byType(Texture);
    expect(video, findsOneWidget);
    expect(tester.widget<Texture>(video).textureId, 7);
    expect(
      tester.widget<Texture>(video).filterQuality,
      ui.FilterQuality.low,
      reason: 'the frame is far smaller than the stream; nearest shimmers',
    );
    expect(tester.renderObject(video).isRepaintBoundary, isTrue);
    // The phone's frames arrive thirty times a second. A blur anywhere above
    // them re-blurs the desk on every one, so the frame goes flat while live.
    expect(
      find.ancestor(of: video, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.textContaining('Connecting'), findsNothing);
  });

  testWidgets('the frame keeps the phone aspect while streaming', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      mirror: const DisplayMirrorState(
        status: DisplayMirrorStatus.streaming,
        surface: WindowSurface(
          textureId: 7,
          // Landscape: the phone has rotated, the frame has not.
          pixelSize: WindowPixelSize(width: 1170, height: 540),
        ),
      ),
    );
    final Size drawn = tester.getSize(find.byType(Texture));
    expect(
      drawn.width / drawn.height,
      closeTo(1170 / 540, 0.02),
      reason: 'letterboxed, never stretched',
    );
  });

  testWidgets('starting says it is connecting; idle says what will appear', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      mirror: const DisplayMirrorState(status: DisplayMirrorStatus.starting),
    );
    expect(find.text("Connecting to the phone's screen…"), findsOneWidget);
    expect(find.byType(Texture), findsNothing);

    await pump(tester, mirror: const DisplayMirrorState());
    expect(
      find.text("The phone's screen appears here once the mirror starts."),
      findsOneWidget,
    );
  });

  testWidgets('a failure shows its reason and offers a retry', (
    WidgetTester tester,
  ) async {
    var retries = 0;
    await pump(
      tester,
      mirror: const DisplayMirrorState(
        status: DisplayMirrorStatus.failed,
        error: OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'The phone screen stream stopped.',
          retryable: true,
        ),
      ),
      onRetry: () => retries++,
    );
    expect(find.text('The phone screen stream stopped.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('an unavailable mirror explains itself with no dead button', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      mirror: const DisplayMirrorState(
        status: DisplayMirrorStatus.unavailable,
        error: OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'The preview has no phone to mirror.',
        ),
      ),
    );
    expect(find.text('The preview has no phone to mirror.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
