import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/desk/control_center.dart';
import 'package:open_android_dex/ui/widgets/toggle.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The shared clipboard is an opt-in with three preconditions.
///
/// Sharing means the desk reads what is on the phone, so the switch is off by
/// default and stays *disabled* until the session is up, the agent is
/// connected, and the phone has said it can share at all. Every reason it
/// cannot be used is on screen and stays there — none of this is a snackbar,
/// which is the whole point: a toast that fired while the panel was closed
/// told nobody anything.
void main() {
  const DeviceTelemetry telemetry = DeviceTelemetry(
    wifiEnabled: true,
    bluetoothEnabled: false,
  );

  final List<bool> toggles = <bool>[];

  setUp(toggles.clear);

  Future<void> pump(
    WidgetTester tester, {
    required ClipboardState clipboard,
    AgentConnectionStatus agent = AgentConnectionStatus.connected,
  }) async {
    await tester.binding.setSurfaceSize(const Size(640, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Material(
          child: Center(
            child: SingleChildScrollView(
              child: ControlCenter(
                telemetry: telemetry,
                clipboard: clipboard,
                agentStatus: agent,
                onToggleControl: (_, _) {},
                onToggleClipboardSync: toggles.add,
                onSetVolume: (_, _) {},
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
  }

  DexToggle theSwitch(WidgetTester tester) =>
      tester.widget<DexToggle>(find.byType(DexToggle));

  testWidgets('it is off and unusable before the phone has reported in', (
    WidgetTester tester,
  ) async {
    // The contract's default: sync off, availability unknown.
    await pump(tester, clipboard: const ClipboardState());

    expect(theSwitch(tester).value, isFalse);
    expect(
      theSwitch(tester).onChanged,
      isNull,
      reason: 'a switch that fails when pressed is worse than a disabled one',
    );
    expect(find.text('Waiting for the phone'), findsOneWidget);
    expect(
      find.textContaining('has not said whether it can share'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a phone that cannot share says so, permanently', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      clipboard: const ClipboardState(
        availability: ClipboardAvailability.unavailable,
        message: 'This phone’s Android build blocks clipboard access.',
      ),
    );

    expect(theSwitch(tester).onChanged, isNull);
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(
      find.text('This phone’s Android build blocks clipboard access.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the link being down disables it even when the phone can share', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      clipboard: const ClipboardState(
        availability: ClipboardAvailability.available,
      ),
      agent: AgentConnectionStatus.reconnecting,
    );

    expect(theSwitch(tester).onChanged, isNull);
  });

  testWidgets('once it is available the opt-in works both ways', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      clipboard: const ClipboardState(
        availability: ClipboardAvailability.available,
      ),
    );

    expect(theSwitch(tester).value, isFalse);
    expect(find.text('Off — nothing is read from the phone'), findsOneWidget);
    expect(theSwitch(tester).onChanged, isNotNull);

    await tester.tap(find.byType(DexToggle));
    await tester.pump();
    expect(toggles, <bool>[true]);

    await pump(
      tester,
      clipboard: const ClipboardState(
        kind: ClipboardKind.text,
        text: 'ffmpeg -i in.mp4',
        syncEnabled: true,
        availability: ClipboardAvailability.available,
      ),
    );
    expect(theSwitch(tester).value, isTrue);
    expect(find.text('ffmpeg -i in.mp4'), findsOneWidget);

    toggles.clear();
    await tester.tap(find.byType(DexToggle));
    await tester.pump();
    expect(toggles, <bool>[false]);
  });

  testWidgets('a paused sync explains itself and offers exactly one retry', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      clipboard: const ClipboardState(
        syncEnabled: true,
        availability: ClipboardAvailability.available,
        message: 'The last clipboard read timed out.',
      ),
    );

    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.textContaining('The last clipboard read timed out.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    // Retry is the ordinary opt-in command, not an invented one.
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(toggles, <bool>[true]);
  });

  testWidgets('no retry is offered when there is nothing to retry against', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      clipboard: const ClipboardState(
        syncEnabled: true,
        availability: ClipboardAvailability.available,
        message: 'The last clipboard read timed out.',
      ),
      agent: AgentConnectionStatus.unavailable,
    );

    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(theSwitch(tester).onChanged, isNull);
  });
}
