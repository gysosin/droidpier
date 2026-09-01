import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// Decides when the shell connects a phone without being asked.
///
/// Lifted out of `AppShell` because it is a policy with its own state machine —
/// a latch, a re-entrancy guard, an attempt budget and a retry timer — and that
/// is exactly the kind of thing that is hard to reason about while it is
/// interleaved with a build method.
class ConnectionController {
  ConnectionController({
    required this.facade,
    required this.notify,
    required this.isMounted,
  });

  final OpenDexFacade facade;

  /// Rebuilds the shell, so a retry re-runs the check.
  final VoidCallback notify;
  final bool Function() isMounted;

  /// Attempts spent. Auto-connect stops after [_limit] so a phone that
  /// genuinely cannot connect does not retry forever.
  int _attempts = 0;
  static const int _limit = 3;

  /// True once this shell must never auto-connect again: a session has been
  /// established, or the person has taken the decision over themselves.
  ///
  /// Latching on *success* rather than on the attempt is the difference between
  /// a transient race resolving itself and the desk never appearing: the first
  /// cut set the latch before calling, so one failed attempt — an adb server
  /// still starting, a device that flickered during discovery — stranded the
  /// app on the boot screen with no retry, which is exactly what was observed
  /// at runtime.
  ///
  /// It never resets, and that is the point. `disconnect()` puts boot back to
  /// idle and clears the selection, which is byte-for-byte the state that
  /// invites an auto-connect — so without a latch that outlives the session,
  /// hitting Disconnect would reconnect the phone before the person's finger
  /// left the button. Disconnecting is a deliberate act; the only thing that
  /// may undo it is another deliberate act.
  bool _done = false;

  /// Guards against a second attempt starting while one is in flight, since
  /// this is driven from `build` and several frames can pass before the first
  /// command resolves.
  ///
  /// Deliberately separate from [_done]: this one is a re-entrancy guard that
  /// clears, that one is a latch that never does. Collapsing them would either
  /// permit a double attempt or strand the shell after the first failure.
  bool _inFlight = false;

  /// Long enough that a retry is not a busy loop, short enough that a person
  /// watching the boot screen does not conclude it has hung.
  static const Duration _backoff = Duration(seconds: 1);
  Timer? _retry;

  /// Stops auto-connect for good.
  ///
  /// Called from every route where the person takes the decision themselves —
  /// retrying the boot, or choosing a phone. Set at the moment of the action
  /// rather than by observing a snapshot, because two backend emissions inside
  /// one frame coalesce into a single build: the shell can go from
  /// "connecting" to "disconnected" without ever rendering the ready state in
  /// between, and watching for a ready phase alone would miss it exactly then.
  void standDown() {
    _done = true;
    _retry?.cancel();
    _retry = null;
  }

  void dispose() {
    _retry?.cancel();
    _retry = null;
  }

  /// Connects on its own when there is exactly one authorised phone.
  ///
  /// The backend auto-*selects* that phone but never connects, so the product
  /// used to open on a boot screen with a single button, which reads as a
  /// connection failure. When to issue `connect` is a product decision, not an
  /// implementation detail: connecting is a decision, not a reflex, so the
  /// automatic case is confined to the one situation with no question in it.
  ///
  /// Deliberately narrow. Zero devices, several devices, or an unauthorised one
  /// all still require a choice, because in those cases there is a real question
  /// only the person can answer.
  void maybeConnect(OpenDexSnapshot snapshot) {
    if (_done || _inFlight) return;
    if (snapshot.boot.isReady) {
      // Connected by any route — this one, or the person choosing a phone.
      _done = true;
      return;
    }
    if (_attempts >= _limit) return;
    if (snapshot.deviceStatus != LoadStatus.ready) return;

    final List<DeviceSummary> authorised = snapshot.devices
        .where((DeviceSummary d) => d.status == DeviceStatus.authorized)
        .toList();
    if (authorised.length != 1) return;

    _attempts++;
    _inFlight = true;

    // After the frame: this runs from build, and a facade command can emit a
    // new snapshot synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool connected = false;
      try {
        if (!isMounted()) return;
        final VoidResult selected = await facade.selectDevice(
          authorised.single.id,
        );
        // Connecting after a failed select would act on whatever was selected
        // before, which could be nothing or the wrong phone.
        if (!isMounted() || selected is! CommandSuccess) return;
        connected = await facade.connectSelectedDevice() is CommandSuccess;
      } finally {
        // Order matters, and every exit path runs through here. The retry is
        // scheduled only after the in-flight flag is cleared, or the timer
        // would find the guard still closed and do nothing. Scheduling inside
        // the `try` also missed the early returns entirely — a failed
        // `selectDevice` scheduled nothing at all and spent an attempt.
        _inFlight = false;
        if (connected) {
          _done = true;
        } else {
          _scheduleRetry();
        }
      }
    });
  }

  /// Re-runs the check after a pause.
  ///
  /// [maybeConnect] is driven from `build`, so without this a retry depends on
  /// some unrelated snapshot happening to arrive and rebuild the shell. On a
  /// phone that failed to connect there may be no such snapshot, and waiting
  /// for one is how a person ends up staring at a boot screen.
  void _scheduleRetry() {
    if (_done || _attempts >= _limit) return;
    _retry?.cancel();
    _retry = Timer(_backoff, () {
      if (isMounted()) notify();
    });
  }
}
