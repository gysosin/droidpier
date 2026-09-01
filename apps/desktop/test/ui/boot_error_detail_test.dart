import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// What a failed boot tells you.
///
/// The backend captures the underlying cause in `technicalDetails` — the actual
/// adb or install error — and the boot screen used to show only a summary and
/// an error code. So "The Android companion could not start. deploymentFailed"
/// was the whole of what a person had to work with, when the reason was sitting
/// in the snapshot unused.
void main() {
  Future<void> pumpBoot(WidgetTester tester, OpenDexError error) async {
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
          onRetry: () {},
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the underlying cause is shown, not discarded', (
    WidgetTester tester,
  ) async {
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails:
            'INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match',
      ),
    );

    // Stated once, in the boot line. The box adds the code and the cause.
    expect(find.text('The Android companion could not start.'), findsOneWidget);
    expect(
      find.textContaining('INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
      findsOneWidget,
      reason: 'the reason is the only actionable part of the failure',
    );
  });

  testWidgets('a failure says what to do about it', (
    WidgetTester tester,
  ) async {
    // The code and the transcript both describe the failure. Neither tells a
    // person what to try, and an error with no next step is a dead end.
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails: 'INSTALL_FAILED_USER_RESTRICTED',
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

  testWidgets('an error with no detail shows no empty space for it', (
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
    // Nothing empty where the detail would have been.
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('a long cause is shown in full rather than truncated to one line',
      (WidgetTester tester) async {
    // These are adb transcripts. Clipping one to a single ellipsised line
    // hides the part that names the fault.
    const String long =
        'Exception: adb: failed to install /tmp/companion.apk: '
        'Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user] '
        'while running: adb -s ABC123 install -r -t /tmp/companion.apk';
    await pumpBoot(
      tester,
      const OpenDexError(
        code: OpenDexErrorCode.deploymentFailed,
        message: 'The Android companion could not start.',
        technicalDetails: long,
      ),
    );
    expect(find.textContaining('INSTALL_FAILED_USER_RESTRICTED'), findsOneWidget);
  });
}
