import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/connect/connection_commands.dart';
import 'package:open_android_dex/ui/connect/connection_screen.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The single connection screen.
///
/// What is asserted here is what a screenshot cannot show: that discovery runs
/// for exactly as long as the screen is open, that an advertisement is treated
/// as a hint and never acted on by itself, that the QR payload exists only
/// while the phone can still scan it and is never written into the tree, that
/// a typed failure reaches the person as its message and nothing else, and
/// that adding a phone no longer stacks a second modal over the first.
void main() {
  const String payload = 'WIFI:T:ADB;S:studio-2;P:one-time-secret;;';

  final List<String> calls = <String>[];
  late ValueNotifier<OpenDexSnapshot> state;
  String? selected;
  OpenDexError? startDiscoveryError;
  OpenDexError? qrError;
  OpenDexError? pairError;
  CommandResult<DeviceSummary> connectResult =
      const CommandFailure<DeviceSummary>(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'Nothing answered on that port.',
          technicalDetails: 'adb: failed to connect to 10.0.0.4:41234',
          wirelessReason: WirelessFailureReason.unreachable,
        ),
      );
  DateTime now = DateTime.utc(2026, 8, 31, 12);

  setUp(() {
    calls.clear();
    selected = null;
    startDiscoveryError = null;
    qrError = null;
    pairError = null;
    now = DateTime.utc(2026, 8, 31, 12);
    connectResult = const CommandFailure<DeviceSummary>(
      OpenDexError(
        code: OpenDexErrorCode.connectionFailed,
        message: 'Nothing answered on that port.',
        technicalDetails: 'adb: failed to connect to 10.0.0.4:41234',
        wirelessReason: WirelessFailureReason.unreachable,
      ),
    );
  });

  ConnectionCommands commands() => ConnectionCommands(
    startDiscovery: () async {
      calls.add('startDiscovery');
      return startDiscoveryError;
    },
    stopDiscovery: () async {
      calls.add('stopDiscovery');
      return null;
    },
    startQrPairing: () async {
      calls.add('startQrPairing');
      return qrError;
    },
    cancelPairing: () async {
      calls.add('cancelPairing');
      return null;
    },
    pair:
        ({
          required String host,
          required int pairingPort,
          required String pairingCode,
        }) async {
          calls.add('pair:$host|$pairingPort|$pairingCode');
          return pairError;
        },
    connect: ({required String host, required int port}) async {
      calls.add('connect:$host|$port');
      return connectResult;
    },
    disconnectWireless: (String deviceId) async {
      calls.add('disconnect:$deviceId');
      return null;
    },
  );

  /// Entrance staggers and the loading floor are timer-driven; flush them
  /// rather than using `pumpAndSettle`, which never returns while the busy
  /// indicator is spinning.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    OpenDexSnapshot initial = const OpenDexSnapshot(),
    Size size = const Size(1120, 820),
  }) async {
    state = ValueNotifier<OpenDexSnapshot>(initial);
    addTearDown(state.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Material(
          child: ValueListenableBuilder<OpenDexSnapshot>(
            valueListenable: state,
            builder: (BuildContext context, OpenDexSnapshot s, Widget? _) =>
                ConnectionScreen(
                  deviceStatus: s.deviceStatus,
                  devices: s.devices,
                  discovery: s.wirelessDiscovery,
                  pairing: s.wirelessPairing,
                  commands: commands(),
                  selectedId: selected,
                  onSelect: (String id) => selected = id,
                  onConnectSelected: () => calls.add('openWorkspace'),
                  onRefreshDevices: () => calls.add('refresh'),
                  onClose: () => calls.add('close'),
                  clock: () => now,
                ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Pushes a new snapshot the way the facade's stream would.
  Future<void> emit(WidgetTester tester, OpenDexSnapshot next) async {
    state.value = next;
    await settle(tester);
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

  /// The mode switch's segments are private to the screen, so the test reaches
  /// one the way a person does: by its label.
  Finder segment(String label) => find.widgetWithText(InkWell, label);

  String textIn(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.descendant(of: field(label), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  group('discovery lifecycle', () {
    testWidgets('opening the screen starts discovery', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      expect(calls, contains('startDiscovery'));
    });

    testWidgets('closing it stops discovery and cancels any pairing', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      calls.clear();

      // Unmounting is what closing does, by every route — Escape, the Close
      // button, the shell hiding it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(calls, containsAll(<String>['cancelPairing', 'stopDiscovery']));
    });

    testWidgets('a discovery that cannot start says so without a raw error', (
      WidgetTester tester,
    ) async {
      startDiscoveryError = const OpenDexError(
        code: OpenDexErrorCode.capabilityUnavailable,
        message: 'This computer cannot browse the network.',
        technicalDetails: 'mdns: socket bind failed (EACCES)',
      );
      await pumpScreen(tester);

      expect(
        find.text('This computer cannot browse the network.'),
        findsOneWidget,
      );
      expect(find.textContaining('EACCES'), findsNothing);
    });
  });

  group('nearby phones', () {
    WirelessAdvertisement ad({
      required WirelessServiceKind kind,
      String? displayName,
      String host = '10.0.0.4',
      int port = 37105,
      Duration remaining = const Duration(minutes: 1),
    }) => WirelessAdvertisement(
      serviceName: 'adb-tls-${kind.name}-1',
      kind: kind,
      host: host,
      port: port,
      displayName: displayName,
      expiresAt: now.add(remaining),
    );

    OpenDexSnapshot withAds(List<WirelessAdvertisement> ads) => OpenDexSnapshot(
      wirelessDiscovery: WirelessDiscoveryState(
        status: WirelessDiscoveryStatus.ready,
        devices: ads,
      ),
    );

    testWidgets('a nameless phone gets a neutral label, never a paired one', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: withAds(<WirelessAdvertisement>[
          ad(kind: WirelessServiceKind.pairing),
        ]),
      );

      expect(find.text('Android phone (no name given)'), findsOneWidget);
      expect(
        find.text('Offering to pair — needs the code from the phone'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Paired'),
        findsNothing,
        reason: 'an advertisement is not evidence of a pairing',
      );
      expect(
        find.textContaining('has not paired with any of them'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a pairing advertisement fills the form and stops '
        'there', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        initial: withAds(<WirelessAdvertisement>[
          ad(kind: WirelessServiceKind.pairing, displayName: 'Pixel 7a'),
        ]),
      );
      calls.clear();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Pair…'));
      await settle(tester);

      // The hint became a filled-in manual form. Nothing was attempted: the
      // six digits only the phone knows are still missing.
      expect(textIn(tester, 'Phone address'), '10.0.0.4');
      expect(textIn(tester, 'Pairing port'), '37105');
      expect(calls, isEmpty);
    });

    testWidgets('a connection advertisement connects only when asked', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: withAds(<WirelessAdvertisement>[
          ad(
            kind: WirelessServiceKind.connection,
            displayName: 'Pixel 7a',
            port: 41234,
          ),
        ]),
      );
      expect(calls, isNot(contains('connect:10.0.0.4|41234')));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
      await settle(tester);
      expect(calls, contains('connect:10.0.0.4|41234'));
    });

    testWidgets('an expired advertisement cannot be acted on', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: withAds(<WirelessAdvertisement>[
          ad(
            kind: WirelessServiceKind.connection,
            remaining: const Duration(seconds: -1),
          ),
        ]),
      );

      expect(find.text('No longer advertising'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Connect'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('an empty network still offers a way in', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          wirelessDiscovery: WirelessDiscoveryState(
            status: WirelessDiscoveryStatus.ready,
          ),
        ),
      );

      expect(find.text('Nothing is advertising right now'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pair manually'));
      await settle(tester);
      expect(find.text('Pairing code'), findsOneWidget);
    });

    testWidgets('discovery being unavailable is not a dead end', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          wirelessDiscovery: WirelessDiscoveryState(
            status: WirelessDiscoveryStatus.unavailable,
            message: 'Network discovery is blocked on this machine.',
          ),
        ),
      );

      expect(
        find.text('Network discovery is blocked on this machine.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pair manually'));
      await settle(tester);
      expect(find.text('Pairing code'), findsOneWidget);
    });
  });

  group('QR Code', () {
    Future<void> openQr(WidgetTester tester) async {
      await tester.tap(segment('QR Code'));
      await settle(tester);
    }

    testWidgets('the code is requested, shown with its expiry, and can be '
        'regenerated', (WidgetTester tester) async {
      await pumpScreen(tester);
      await openQr(tester);

      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Show QR code'));
      await settle(tester);
      expect(calls, contains('startQrPairing'));

      await emit(
        tester,
        OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.waitingForScan,
            qrPayload: payload,
            expiresAt: now.add(const Duration(minutes: 2)),
          ),
        ),
      );

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);
      expect(find.textContaining('Pair device with QR code'), findsOneWidget);

      calls.clear();
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'New code'));
      await settle(tester);
      expect(calls, contains('startQrPairing'));
    });

    testWidgets('the payload never reaches the tree as text', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.waitingForScan,
            qrPayload: payload,
            expiresAt: now.add(const Duration(minutes: 2)),
          ),
        ),
      );
      await openQr(tester);

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('one-time-secret'), findsNothing);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .every(
              (Semantics s) =>
                  !(s.properties.label ?? '').contains('one-time-secret'),
            ),
        isTrue,
        reason: 'the payload is a secret, not an accessibility label',
      );
    });

    testWidgets('the code disappears the moment pairing begins', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.waitingForScan,
            qrPayload: payload,
            expiresAt: now.add(const Duration(minutes: 2)),
          ),
        ),
      );
      await openQr(tester);
      expect(find.byType(QrImageView), findsOneWidget);

      await emit(
        tester,
        const OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.pairing,
          ),
        ),
      );

      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Pairing…'), findsOneWidget);
      // And no second way in is offered while the exchange is running.
      expect(segment('QR Code'), findsNothing);
    });

    testWidgets('an expired code says so rather than counting below zero', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.waitingForScan,
            qrPayload: payload,
            expiresAt: now.subtract(const Duration(seconds: 5)),
          ),
        ),
      );
      await openQr(tester);

      expect(find.text('Expired — choose “New code”.'), findsOneWidget);
    });

    testWidgets('leaving the QR tab ends the session behind it', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.waitingForScan,
            qrPayload: payload,
            expiresAt: now.add(const Duration(minutes: 2)),
          ),
        ),
      );
      await openQr(tester);
      calls.clear();

      await tester.tap(segment('Manual Entry'));
      await settle(tester);
      expect(calls, contains('cancelPairing'));
    });
  });

  group('manual pairing', () {
    Future<void> openManual(WidgetTester tester) async {
      await tester.tap(segment('Manual Entry'));
      await settle(tester);
    }

    testWidgets('a pasted address:port fills both fields', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await openManual(tester);

      await enter(tester, 'Phone address', '192.168.1.42:37105');
      expect(textIn(tester, 'Phone address'), '192.168.1.42');
      expect(textIn(tester, 'Pairing port'), '37105');
    });

    testWidgets('a leading-zero code is sent exactly as typed', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await openManual(tester);

      await enter(tester, 'Phone address', '192.168.1.42:37105');
      await enter(tester, 'Pairing code', '004821');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Pair'));
      await settle(tester);

      expect(calls, contains('pair:192.168.1.42|37105|004821'));
    });

    testWidgets('the code is obscured and does not survive submission', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await openManual(tester);

      final TextField code = tester.widget<TextField>(
        find.descendant(
          of: field('Pairing code'),
          matching: find.byType(TextField),
        ),
      );
      expect(code.obscureText, isTrue);
      expect(code.autocorrect, isFalse);
      expect(code.enableSuggestions, isFalse);
      expect(code.enableIMEPersonalizedLearning, isFalse);

      await enter(tester, 'Phone address', '192.168.1.42:37105');
      await enter(tester, 'Pairing code', '481920');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Pair'));
      await settle(tester);

      expect(calls, contains('pair:192.168.1.42|37105|481920'));
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((TextField f) => f.controller?.text != '481920'),
        isTrue,
        reason: 'the one-time code must not be retained after submission',
      );
      expect(find.textContaining('481920'), findsNothing);
    });

    testWidgets('nothing is submittable until the form is complete', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await openManual(tester);

      FilledButton pairButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Pair'),
      );

      expect(pairButton().onPressed, isNull);
      await enter(tester, 'Phone address', '192.168.1.42');
      await enter(tester, 'Pairing port', '99999999');
      await enter(tester, 'Pairing code', '1234');
      expect(pairButton().onPressed, isNull);

      await enter(tester, 'Pairing port', '37105');
      expect(
        pairButton().onPressed,
        isNull,
        reason: 'four digits is not a pairing code',
      );

      await enter(tester, 'Pairing code', '123456');
      expect(pairButton().onPressed, isNotNull);
      expect(calls.where((String c) => c.startsWith('pair:')), isEmpty);
    });

    testWidgets(
      'a refused pairing shows the message and never the diagnostic',
      (WidgetTester tester) async {
        pairError = const OpenDexError(
          code: OpenDexErrorCode.protocolError,
          message: 'The phone rejected that pairing code.',
          technicalDetails: 'adb pair: protocol fault 0x21',
          wirelessReason: WirelessFailureReason.rejected,
        );
        await pumpScreen(tester);
        await openManual(tester);

        await enter(tester, 'Phone address', '192.168.1.42:37105');
        await enter(tester, 'Pairing code', '123456');
        await tapVisible(tester, find.widgetWithText(FilledButton, 'Pair'));
        await settle(tester);

        expect(
          find.text('The phone rejected that pairing code.'),
          findsOneWidget,
        );
        expect(find.textContaining('protocol fault'), findsNothing);
        // Still on the form, with the code cleared so an expired one is not
        // silently resubmitted.
        expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
        expect(textIn(tester, 'Pairing code'), isEmpty);
      },
    );
  });

  group('after pairing', () {
    testWidgets('a pairing that connected itself does not ask for a port', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.connected,
            device: DeviceSummary(
              id: '192.168.1.42:41234',
              name: 'Pixel 7a',
              connectionKind: DeviceConnectionKind.wifi,
              status: DeviceStatus.authorized,
            ),
          ),
        ),
      );

      expect(find.text('Connected over Wi-Fi'), findsOneWidget);
      expect(find.text('Connect port'), findsNothing);

      // An authorized transport is not a session: the phone is still selected
      // and connected through the ordinary commands.
      await tester.tap(find.widgetWithText(FilledButton, 'Open workspace'));
      await settle(tester);
      expect(selected, '192.168.1.42:41234');
      expect(calls, contains('openWorkspace'));
    });

    testWidgets('needing the connection port asks for that one port only', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.needsConnectionPort,
            host: '192.168.1.42',
          ),
        ),
      );

      expect(find.text('Connect port'), findsOneWidget);
      expect(find.text('Pairing code'), findsNothing);
      expect(find.text('192.168.1.42'), findsOneWidget);

      await enter(tester, 'Connect port', '41234');
      // The phone list carries a Connect of its own; this is the wireless
      // column's, which is the second of the two.
      await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
      await settle(tester);

      expect(calls, contains('connect:192.168.1.42|41234'));
      // The refusal is the backend's message, inline, with our own next step.
      expect(find.text('Nothing answered on that port.'), findsOneWidget);
      expect(find.textContaining('failed to connect to'), findsNothing);
      expect(find.textContaining('not the pairing port'), findsOneWidget);
    });

    testWidgets('a failed pairing reports its message and leaves the form', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          wirelessPairing: WirelessPairingState(
            phase: WirelessPairingPhase.failed,
            error: OpenDexError(
              code: OpenDexErrorCode.timeout,
              message: 'The phone stopped responding while pairing.',
              technicalDetails: 'deadline exceeded after 20s',
            ),
          ),
        ),
      );

      expect(
        find.text('The phone stopped responding while pairing.'),
        findsOneWidget,
      );
      expect(find.textContaining('deadline exceeded'), findsNothing);
      expect(segment('Manual Entry'), findsOneWidget);
    });
  });

  group('the phone list', () {
    const DeviceSummary wifi = DeviceSummary(
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

    testWidgets('Disconnect is offered for Wi-Fi only, and says what it does '
        'not do', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          deviceStatus: LoadStatus.ready,
          devices: <DeviceSummary>[usb, wifi],
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);
      expect(
        find.textContaining('does not remove the pairing'),
        findsOneWidget,
      );
      expect(find.textContaining('Forget'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
      await settle(tester);
      expect(calls, contains('disconnect:192.168.1.42:41234'));
    });

    testWidgets('Connect waits for an authorized selection', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(
          deviceStatus: LoadStatus.ready,
          devices: <DeviceSummary>[
            DeviceSummary(
              id: 'unauthorized-1',
              name: 'Galaxy S21',
              connectionKind: DeviceConnectionKind.usb,
              status: DeviceStatus.unauthorized,
            ),
          ],
        ),
      );

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
            .onPressed,
        isNull,
      );
      expect(find.text('Tap “Allow” on the phone'), findsOneWidget);
    });

    testWidgets('an empty list points at the Wi-Fi half of the same screen', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        initial: const OpenDexSnapshot(deviceStatus: LoadStatus.empty),
      );
      expect(find.text('No phones found'), findsOneWidget);
      expect(find.textContaining('add one over Wi-Fi'), findsWidgets);
    });
  });

  group('in the shell', () {
    testWidgets('adding a phone no longer stacks a second dialog, and one '
        'Escape leaves', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
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
      await settle(tester);

      // The shell connects on its own when there is exactly one authorised
      // phone, so the door a person actually has is Settings → Manage phones.
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      await tester.ensureVisible(
        find.text('Manage Phones…'),
      );
      await settle(tester);
      await tester.tap(find.text('Manage Phones…'));
      await settle(tester);

      // One surface, carrying both halves. There is nothing left to stack.
      expect(find.text('Manage Android Phones'), findsOneWidget);
      expect(find.text('Connected Devices'), findsOneWidget);
      expect(find.text('Add over Wi-Fi'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Pair over Wi-Fi'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(
        find.text('Manage Android Phones'),
        findsNothing,
        reason: 'one layer, so one Escape',
      );
    });
  });
}
