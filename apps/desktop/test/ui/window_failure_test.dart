import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/workspace/workspace.dart';

/// What a window says when its stream will not start.
///
/// The video path captures the decoder's own account of the failure — FFmpeg
/// usually knows exactly why — and the window showed only the one-line summary,
/// so "The direct Android application stream could not start." was the whole of
/// what a person had. The same gap the boot screen had, one surface over.
void main() {
  const String tail =
      'Error while decoding stream #0:0: Invalid data found when processing '
      'input\nNo frame received before the first-frame timeout elapsed';

  WorkspaceWindow failed({String? details}) => WorkspaceWindow(
    session: WindowSessionState(
      id: 'w1',
      application: const AndroidApplication(
        packageName: 'com.example.notes',
        label: 'Notes',
      ),
      status: WindowSessionStatus.failed,
      isFocused: true,
      error: OpenDexError(
        code: OpenDexErrorCode.capabilityUnavailable,
        message: 'The direct Android application stream could not start.',
        capability: 'direct streaming',
        technicalDetails: details,
      ),
    ),
    geometry: const WindowGeometry(x: 20, y: 20, width: 620, height: 460),
    zOrder: 1,
  );

  Future<void> pump(WidgetTester tester, WorkspaceWindow w) async {
    await tester.binding.setSurfaceSize(const Size(800, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a failed window says what to try', (WidgetTester tester) async {
    await pump(tester, failed(details: tail));
    expect(find.textContaining('does not offer'), findsOneWidget);
  });

  testWidgets('the decoder transcript is offered, never rendered', (
    WidgetTester tester,
  ) async {
    // Same rule as the boot screen: it is built from process output and can
    // carry paths and device detail, so it is copied deliberately.
    await pump(tester, failed(details: tail));
    expect(find.textContaining('Invalid data found'), findsNothing);
    expect(find.text('Copy technical details'), findsOneWidget);
  });

  testWidgets('nothing to copy means no control offered', (
    WidgetTester tester,
  ) async {
    await pump(tester, failed());
    expect(find.text('Copy technical details'), findsNothing);
  });

  testWidgets('copying puts the decoder output on the clipboard', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, failed(details: tail));
    await tester.tap(find.text('Copy technical details'));
    await tester.pump();

    final MethodCall copy = calls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect(
      (copy.arguments as Map<Object?, Object?>)['text'],
      contains('Invalid data found'),
    );
  });
}
