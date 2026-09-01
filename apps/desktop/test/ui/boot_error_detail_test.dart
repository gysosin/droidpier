import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// What a failed boot tells you, and what it keeps back.
///
/// The backend captures the underlying cause in `technicalDetails` — the actual
/// adb or install transcript. It is genuinely the most useful thing when a boot
/// fails, and it is also the most dangerous thing to put on screen: it is built
/// from process exceptions and can carry device identifiers, network addresses
/// and local paths. So it is never rendered. It is offered as a deliberate
/// copy, labelled as technical, with a word about checking it before sharing.
void main() {
  Future<void> pumpBoot(
    WidgetTester tester,
    OpenDexError error, {
    VoidCallback? onRetry,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: BootScreen(
          boot: BootState(
            phase: BootPhase.failed,
            message: error.message,
            error: error,
          ),
          onConnect: () {},
          onRetry: onRetry ?? () {},
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  const String transcript =
      'Exception: adb: failed to install /tmp/companion.apk: '
      'Failure [INSTALL_FAILED_USER_RESTRICTED] while running: '
      'adb -s ABC123DEVICESERIAL install -r -t /tmp/companion.apk';

  testWidgets('the transcript is never rendered', (WidgetTester tester) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails: transcript,
      ),
    );

    // Not on screen at all. It carries a device serial and a local path.
    expect(find.textContaining('INSTALL_FAILED_USER_RESTRICTED'), findsNothing);
    expect(find.textContaining('ABC123DEVICESERIAL'), findsNothing);
    expect(find.textContaining('/tmp/companion.apk'), findsNothing);
  });

  testWidgets('but it can be copied, deliberately', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails: transcript,
      ),
    );

    await tester.tap(find.text('Copy technical details'));
    await tester.pump();

    final MethodCall copy = calls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect((copy.arguments as Map<Object?, Object?>)['text'],
        contains('INSTALL_FAILED_USER_RESTRICTED'));
  });

  testWidgets('the person is told to look at it before sharing it', (
    WidgetTester tester,
  ) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails: transcript,
      ),
    );
    expect(find.textContaining('before sharing'), findsOneWidget);
  });

  testWidgets('no control, and no promise, when there is nothing to copy', (
    WidgetTester tester,
  ) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.adbUnavailable,
        message: 'ADB is not available.',
      ),
    );
    expect(find.text('ADB is not available.'), findsOneWidget);
    expect(find.text('adbUnavailable'), findsOneWidget);
    expect(find.text('Copy technical details'), findsNothing);
    expect(find.textContaining('before sharing'), findsNothing);
  });

  testWidgets('a failure says what to do about it', (
    WidgetTester tester,
  ) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
      ),
    );
    expect(find.textContaining('Play Protect'), findsOneWidget);
  });

  testWidgets('two phones is explained rather than left as a code', (
    WidgetTester tester,
  ) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.multipleDevices,
        message: 'Could not choose a phone.',
      ),
    );
    expect(find.textContaining('More than one phone'), findsOneWidget);
  });

  testWidgets('a failed boot offers both a retry and another phone', (
    WidgetTester tester,
  ) async {
    // `retryable` is deliberately not used to hide the retry. It reads as
    // "safe to retry automatically", not "a person should never press this":
    // a deployment blocked by Play Protect is not retryable until someone
    // acts on the guidance, and then it is. Removing the control on a flag
    // that defaults to false would take it away from almost every failure.
    //
    // What was genuinely missing is the other route. Two phones connected is
    // not fixed by retrying at all — it is fixed by choosing one.
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.multipleDevices,
        message: 'Could not choose a phone.',
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Choose a phone'), findsOneWidget);
  });
}
