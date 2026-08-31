import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/wireless/wireless_pairing_dialog.dart';

/// The guided Wi-Fi surface.
///
/// Three things are asserted here that a screenshot cannot show: that the
/// six-digit code is obscured and does not survive submission, that pairing and
/// connecting use the two *different* ports Android advertises, and that a
/// failure leaves a way forward instead of a dead end.
void main() {
  const DeviceSummary pairedWifi = DeviceSummary(
    id: '192.168.1.42:41234',
    name: 'Pixel 7a',
    connectionKind: DeviceConnectionKind.wifi,
    status: DeviceStatus.authorized,
  );
  const DeviceSummary usb = DeviceSummary(
    id: 'f086a7b',
    name: 'Redmi Note 7 Pro',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
  );

  /// Records what the surface asked the facade to do.
  final List<String> pairCalls = <String>[];
  final List<String> connectCalls = <String>[];
  final List<String> forgetCalls = <String>[];
  bool pairSucceeds = true;
  bool connectSucceeds = true;
  int closed = 0;

  setUp(() {
    pairCalls.clear();
    connectCalls.clear();
    forgetCalls.clear();
    pairSucceeds = true;
    connectSucceeds = true;
    closed = 0;
  });

  /// Entrance staggers and the loading floor are timer-driven; flush them
  /// rather than using `pumpAndSettle`, which never returns while the busy
  /// indicator is spinning.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Column)).first;

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final Finder target = find.descendant(
      of: field(label),
      matching: find.byType(TextField),
    );
    expect(target, findsOneWidget, reason: 'no field labelled “$label”');
    await tester.enterText(target, value);
    await tester.pump();
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    List<DeviceSummary> devices = const <DeviceSummary>[],
    Size size = const Size(900, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Material(
          child: WirelessPairingDialog(
            devices: devices,
            onClose: () => closed++,
            onPair:
                ({
                  required String host,
                  required int pairingPort,
                  required String pairingCode,
                }) async {
                  pairCalls.add('$host|$pairingPort|$pairingCode');
                  return pairSucceeds;
                },
            onConnect: ({required String host, required int port}) async {
              connectCalls.add('$host|$port');
              return connectSucceeds
                  ? DeviceSummary(
                      id: '$host:$port',
                      name: 'Pixel 7a',
                      connectionKind: DeviceConnectionKind.wifi,
                      status: DeviceStatus.authorized,
                    )
                  : null;
            },
            onForget: (String id) async {
              forgetCalls.add(id);
              return true;
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('pairs, then connects on the separately advertised port', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    // Nothing is submittable until all three values are present.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '123456');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);

    expect(pairCalls, <String>['192.168.1.42|37105|123456']);

    // The connect step reuses the address and asks only for the other port,
    // which is the part of ADB wireless people get wrong.
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.text('192.168.1.42'), findsOneWidget);

    await enter(tester, 'Connect port', '41234');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester);

    expect(connectCalls, <String>['192.168.1.42|41234']);
    expect(find.text('Linked over Wi-Fi'), findsOneWidget);
  });

  testWidgets('the pairing code is obscured and does not survive submission', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    final Finder codeField = find.descendant(
      of: field('Pairing code'),
      matching: find.byType(TextField),
    );
    final TextField code = tester.widget<TextField>(codeField);
    expect(code.obscureText, isTrue);
    expect(code.autocorrect, isFalse);
    expect(code.enableSuggestions, isFalse);
    expect(code.enableIMEPersonalizedLearning, isFalse);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '481920');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);

    expect(pairCalls, <String>['192.168.1.42|37105|481920']);
    // Submitted, therefore gone: not in the field it was typed into, and not
    // rendered anywhere else on the surface.
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((TextField f) => f.controller?.text != '481920'),
      isTrue,
      reason: 'the one-time code must not be retained after submission',
    );
    expect(find.textContaining('481920'), findsNothing);
  });

  testWidgets('rejects a code that is not six digits and a port out of range', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '99999999');
    await enter(tester, 'Pairing code', '1234');

    // A five-digit limit and digits-only formatting are applied by the field
    // itself; the range and length rules gate the button.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await enter(tester, 'Pairing port', '37105');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'four digits is not a pairing code',
    );

    await enter(tester, 'Pairing code', '123456');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(pairCalls, isEmpty);
  });

  testWidgets('a refused pairing stays on the step with a way forward', (
    WidgetTester tester,
  ) async {
    pairSucceeds = false;
    await pumpDialog(tester);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);

    expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
    expect(find.textContaining('new code each time'), findsOneWidget);
    // The code was cleared on submit, so the button waits for a fresh one
    // rather than silently retrying the expired code.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await enter(tester, 'Pairing code', '654321');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);
    expect(pairCalls.length, 2);
  });

  testWidgets('a refused connection explains the port, not the error', (
    WidgetTester tester,
  ) async {
    connectSucceeds = false;
    await pumpDialog(tester);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);
    await enter(tester, 'Connect port', '41234');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester);

    expect(find.textContaining('not the pairing port'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('forget is offered for Wi-Fi devices only', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester, devices: const <DeviceSummary>[usb, pairedWifi]);

    expect(find.text('Redmi Note 7 Pro'), findsNothing);
    expect(find.text('Pixel 7a'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Forget'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Forget'));
    await settle(tester);

    expect(forgetCalls, <String>['192.168.1.42:41234']);
  });

  testWidgets('says so when nothing is paired yet', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text('No phones are paired over Wi-Fi yet.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Forget'), findsNothing);
  });

  testWidgets('submits from the keyboard and leaves on Escape', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '123456');

    // Enter in the code field is the whole gesture: type the three values the
    // phone is showing and commit, without reaching for the pointer.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(pairCalls, <String>['192.168.1.42|37105|123456']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1, reason: 'a modal must be dismissible from the keyboard');
  });

  testWidgets('stacks its fields when the window is narrow', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester, size: const Size(420, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Pairing port'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
  });

  testWidgets('the shell opens the flow from the phone list and Escape closes '
      'it', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.disconnected,
    );
    addTearDown(facade.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data ?? facade.snapshot,
                facade: facade,
                now: DateTime.utc(2026, 8, 24, 23),
              ),
        ),
      ),
    );
    await settle(tester);
    // The shell now connects on its own when there is exactly one authorised
    // phone, and this scenario has one — so the boot screen's "Connect phone"
    // button is gone before a person could reach it. The phone list is still
    // reachable, from Settings (the tray gear) → Manage phones, and that is the
    // path a person actually has.
    await settle(tester);

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    // Manage phones is the first 'Open' action row in Settings; scroll it into
    // view first (the settings page scrolls).
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Open').first,
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Pair over Wi-Fi'));
    await settle(tester);
    expect(find.text('Add a phone over Wi-Fi'), findsOneWidget);

    // The phone list is still behind it, so leaving the pairing flow returns
    // to where it was opened from rather than to nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Add a phone over Wi-Fi'), findsNothing);
    expect(find.text('Choose a phone'), findsOneWidget);
  });

  testWidgets('a real facade pairs and connects end to end', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.disconnected,
    );
    addTearDown(facade.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Material(
          child: StreamBuilder<OpenDexSnapshot>(
            stream: facade.states,
            initialData: facade.snapshot,
            builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
                WirelessPairingDialog.forFacade(
                  facade: facade,
                  devices: (s.data ?? facade.snapshot).devices,
                  onClose: () {},
                ),
          ),
        ),
      ),
    );
    await settle(tester);

    await enter(tester, 'Phone address', '192.168.1.42');
    await enter(tester, 'Pairing port', '37105');
    await enter(tester, 'Pairing code', '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await settle(tester);
    await enter(tester, 'Connect port', '41234');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester);

    expect(find.text('Linked over Wi-Fi'), findsOneWidget);
    // The device the facade returned is now a forgettable Wi-Fi entry.
    expect(find.widgetWithText(OutlinedButton, 'Forget'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Forget'));
    await settle(tester);
    expect(find.text('No phones are paired over Wi-Fi yet.'), findsOneWidget);
  });
}
