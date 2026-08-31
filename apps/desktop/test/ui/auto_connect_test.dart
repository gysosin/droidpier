import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// Connecting on its own is only correct when there is no question to answer.
/// One authorised phone is not a choice; none, several, or an unauthorised one
/// each are, and guessing at those is how a product connects to the wrong
/// device.
void main() {
  Future<List<String>> pump(
    WidgetTester tester,
    List<DeviceSummary> devices, {
    LoadStatus deviceStatus = LoadStatus.ready,
    BootPhase boot = BootPhase.idle,
  }) async {
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      snapshot: OpenDexSnapshot(
        deviceStatus: deviceStatus,
        devices: devices,
        boot: BootState(phase: boot),
      ),
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        // A fixed `now` stops the shell starting its own clock ticker, which
        // would otherwise still be pending when the tree is torn down.
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 25, 10),
        ),
      ),
    );
    await tester.pump();
    // Long enough for the staggered entrances to fire; a Timer still pending
    // at teardown fails the test regardless of the assertion.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return calls;
  }

  DeviceSummary device(String id, DeviceStatus status) => DeviceSummary(
    id: id,
    name: 'Phone $id',
    connectionKind: DeviceConnectionKind.usb,
    status: status,
  );

  testWidgets('one authorised phone connects without being asked', (
    WidgetTester tester,
  ) async {
    final List<String> calls = await pump(tester, <DeviceSummary>[
      device('a', DeviceStatus.authorized),
    ]);
    expect(calls, <String>['select:a', 'connect']);
  });

  testWidgets('two phones wait for a choice', (WidgetTester tester) async {
    final List<String> calls = await pump(tester, <DeviceSummary>[
      device('a', DeviceStatus.authorized),
      device('b', DeviceStatus.authorized),
    ]);
    expect(calls, isEmpty, reason: 'only the person knows which one they mean');
  });

  testWidgets('an unauthorised phone is never connected to', (
    WidgetTester tester,
  ) async {
    final List<String> calls = await pump(tester, <DeviceSummary>[
      device('a', DeviceStatus.unauthorized),
    ]);
    expect(calls, isEmpty);
  });

  testWidgets('no phones, nothing attempted', (WidgetTester tester) async {
    final List<String> calls = await pump(
      tester,
      const <DeviceSummary>[],
      deviceStatus: LoadStatus.empty,
    );
    expect(calls, isEmpty);
  });

  testWidgets('a failed attempt is retried rather than stranding the desk', (
    WidgetTester tester,
  ) async {
    // The first cut latched before calling, so one transient failure — an adb
    // server still starting, a device that flickered during discovery — left
    // the app on the boot screen forever with no retry. That is what was
    // observed at runtime, and it is what this covers.
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      failConnectTimes: 1,
      snapshot: OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 25, 10),
        ),
      ),
    );
    // Long enough for the one-second backoff to elapse twice.
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Exactly two: the first failed, the second succeeded, and success stops
    // it. A third would mean success was not being latched.
    expect(
      calls.where((String c) => c == 'connect').length,
      2,
      reason: 'the failure must not be the end of it, and success must end it',
    );
  });

  testWidgets('a failed select spends an attempt but still retries', (
    WidgetTester tester,
  ) async {
    // The early-return path: `selectDevice` failing used to schedule nothing,
    // so the attempt was spent with no follow-up.
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      failSelectTimes: 1,
      snapshot: OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 25, 10),
        ),
      ),
    );
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      calls.where((String c) => c == 'connect').length,
      1,
      reason: 'the second attempt selected successfully and then connected',
    );
  });

  testWidgets('it gives up rather than retrying forever', (
    WidgetTester tester,
  ) async {
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      failConnectTimes: 99,
      snapshot: OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 25, 10),
        ),
      ),
    );
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      calls.where((String c) => c == 'connect').length,
      lessThanOrEqualTo(3),
      reason: 'a phone that cannot connect must not be hammered',
    );
  });

  testWidgets('an already-connected session is left alone', (
    WidgetTester tester,
  ) async {
    final List<String> calls = await pump(tester, <DeviceSummary>[
      device('a', DeviceStatus.authorized),
    ], boot: BootPhase.ready);
    expect(
      calls,
      isEmpty,
      reason: 'reconnecting over a live session would tear it down',
    );
  });

  testWidgets('disconnecting does not immediately connect straight back', (
    WidgetTester tester,
  ) async {
    // `disconnect()` puts boot back to idle and clears the selection, leaving
    // exactly the state auto-connect exists to act on: one authorised phone,
    // discovery finished, no session. Without a latch that outlives the
    // session, the desk would come back up before the person's finger left the
    // Disconnect button.
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      snapshot: OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );
    addTearDown(facade.dispose);
    final _Harness harness = _Harness(facade: facade, tester: tester);
    await harness.start();

    // It connects on its own, which is the wanted behaviour at startup. That
    // success is the session — the latch is set here, not by a later snapshot.
    expect(calls, <String>['select:a', 'connect']);

    // What the backend emits on disconnect: boot idle, selection cleared, and
    // the phone still sitting there authorised and discovered.
    await harness.show(
      OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );

    expect(calls, <String>[
      'select:a',
      'connect',
    ], reason: 'disconnecting is deliberate; only the person may undo it');
  });

  testWidgets('a hand-picked phone stands auto-connect down for good', (
    WidgetTester tester,
  ) async {
    // The path that never renders a ready snapshot. Two backend emissions
    // inside one frame coalesce into a single build, so the shell can go from
    // connecting to disconnected without `BootPhase.ready` ever reaching
    // `build`. Latching on the person's own action rather than on an observed
    // phase is what closes that window.
    final List<String> calls = <String>[];
    final _RecordingFacade facade = _RecordingFacade(
      calls: calls,
      snapshot: OpenDexSnapshot(
        // Two phones, so there is a real question and auto-connect stays out
        // of it. The person gets to choose first.
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[
          device('a', DeviceStatus.authorized),
          device('b', DeviceStatus.authorized),
        ],
      ),
    );
    addTearDown(facade.dispose);
    final _Harness harness = _Harness(facade: facade, tester: tester);
    await harness.start();
    expect(calls, isEmpty, reason: 'two phones is a choice, not a default');

    // Walk the real doors: the boot screen's button, the phone in the list,
    // then Connect.
    await tester.tap(find.widgetWithText(FilledButton, 'Connect phone'));
    await harness.settle();
    await tester.tap(find.text('Phone a'));
    await harness.settle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await harness.settle();
    expect(calls, <String>['select:a', 'connect']);

    // Now the disconnect: boot idle, selection cleared, the second phone
    // unplugged — so exactly one authorised phone is left and auto-connect's
    // own precondition is satisfied. It must still stay out of it, and it has
    // never once seen `BootPhase.ready`.
    await harness.show(
      OpenDexSnapshot(
        deviceStatus: LoadStatus.ready,
        devices: <DeviceSummary>[device('a', DeviceStatus.authorized)],
      ),
    );

    expect(calls, <String>[
      'select:a',
      'connect',
    ], reason: 'the person chose once; the app does not choose again for them');
  });
}

/// Hosts one [AppShell] and swaps the snapshot underneath it.
///
/// The shell keeps its `State` across a swap — same type, same position, no key
/// — which is the whole point: the latch under test has to survive the session
/// it was set by.
class _Harness {
  _Harness({required this.facade, required this.tester});

  final OpenDexFacade facade;
  final WidgetTester tester;
  final ValueNotifier<OpenDexSnapshot?> _snapshot =
      ValueNotifier<OpenDexSnapshot?>(null);

  Future<void> start() async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(_snapshot.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: ValueListenableBuilder<OpenDexSnapshot?>(
          valueListenable: _snapshot,
          builder: (BuildContext context, OpenDexSnapshot? state, _) {
            return AppShell(
              snapshot: state ?? facade.snapshot,
              facade: facade,
              // A fixed `now` stops the shell starting its own clock ticker,
              // which would still be pending at teardown.
              now: DateTime.utc(2026, 8, 25, 10),
            );
          },
        ),
      ),
    );
    await settle();
  }

  Future<void> show(OpenDexSnapshot state) async {
    _snapshot.value = state;
    await settle();
  }

  /// `pumpAndSettle` never returns while the Link Rail is on screen — its trace
  /// repeats forever by design — so this pumps a fixed span instead. Long
  /// enough for the staggered entrances and the one-second auto-connect backoff
  /// to fire twice over.
  Future<void> settle() async {
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
}

/// Records the two commands under test and does nothing else.
class _RecordingFacade implements OpenDexFacade {
  _RecordingFacade({
    required this.calls,
    required this.snapshot,
    this.failConnectTimes = 0,
    this.failSelectTimes = 0,
  });

  final List<String> calls;

  /// How many `connectSelectedDevice` calls fail before one succeeds.
  final int failConnectTimes;
  int _connectCalls = 0;

  /// How many `selectDevice` calls fail before one succeeds.
  final int failSelectTimes;
  int _selectCalls = 0;
  @override
  final OpenDexSnapshot snapshot;

  final StreamController<OpenDexSnapshot> _controller =
      StreamController<OpenDexSnapshot>.broadcast();

  @override
  Stream<OpenDexSnapshot> get states => _controller.stream;

  @override
  Future<VoidResult> selectDevice(String deviceId) async {
    calls.add('select:$deviceId');
    _selectCalls++;
    if (_selectCalls <= failSelectTimes) {
      return const CommandFailure(
        OpenDexError(code: OpenDexErrorCode.deviceOffline, message: 'not yet'),
      );
    }
    return const CommandSuccess(null);
  }

  @override
  Future<VoidResult> connectSelectedDevice() async {
    calls.add('connect');
    _connectCalls++;
    if (_connectCalls <= failConnectTimes) {
      return const CommandFailure(
        OpenDexError(
          code: OpenDexErrorCode.connectionFailed,
          message: 'not yet',
        ),
      );
    }
    return const CommandSuccess(null);
  }

  @override
  Future<void> dispose() async => _controller.close();

  @override
  Future<VoidResult> startWirelessDiscovery() async =>
      const CommandSuccess(null);

  @override
  Future<VoidResult> stopWirelessDiscovery() async =>
      const CommandSuccess(null);

  @override
  Future<VoidResult> cancelWirelessPairing() async =>
      const CommandSuccess(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not under test');
}
