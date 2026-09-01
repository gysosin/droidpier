import 'dart:async';

import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

abstract interface class HostClipboardGateway {
  Future<String?> readText();

  Future<void> writeText(String text);
}

class SystemHostClipboardGateway implements HostClipboardGateway {
  const SystemHostClipboardGateway();

  @override
  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Synchronizes text without logging or retaining clipboard history.
class DesktopClipboardCoordinator {
  DesktopClipboardCoordinator({
    required this.facade,
    HostClipboardGateway? hostClipboard,
    this.pollInterval = const Duration(seconds: 1),
  }) : hostClipboard = hostClipboard ?? const SystemHostClipboardGateway();

  static const maximumTextLength = 65536;
  final OpenDexFacade facade;
  final HostClipboardGateway hostClipboard;
  final Duration pollInterval;
  StreamSubscription<OpenDexSnapshot>? _subscription;
  Timer? _timer;
  bool _enabled = false;
  bool _busy = false;
  Completer<void>? _idleWaiter;
  bool _disposed = false;
  int _generation = 0;
  String? _deviceId;
  String? _lastDeviceText;
  String? _pendingDeviceText;

  void start() {
    if (_subscription != null || _disposed) return;
    _acceptSnapshot(facade.snapshot);
    _subscription = facade.states.listen(_acceptSnapshot);
    _timer = Timer.periodic(pollInterval, (_) => unawaited(synchronizeOnce()));
  }

  bool _valid(int generation) =>
      !_disposed &&
      _enabled &&
      generation == _generation &&
      facade.snapshot.boot.isReady &&
      facade.snapshot.agentStatus == AgentConnectionStatus.connected &&
      facade.snapshot.clipboard.availability ==
          ClipboardAvailability.available &&
      facade.snapshot.clipboard.syncEnabled;

  Future<void> synchronizeOnce() async {
    if (_busy || !_valid(_generation)) return;
    final generation = _generation;
    _beginOperation();
    try {
      final hostText = await hostClipboard.readText();
      if (!_valid(generation)) return;
      final deviceText = _pendingDeviceText;
      if (deviceText != null) {
        _pendingDeviceText = null;
        if (hostText != deviceText) await hostClipboard.writeText(deviceText);
      } else if (hostText != null &&
          hostText.length <= maximumTextLength &&
          hostText != facade.snapshot.clipboard.text) {
        final result = await facade.setClipboardText(hostText);
        if (_valid(generation) && result is CommandFailure<void>) {
          _enabled = false;
          await facade.setClipboardSync(false);
        }
      }
    } on Object {
      if (_valid(generation)) {
        _enabled = false;
        await facade.pauseClipboardSync();
      }
    } finally {
      _finishOperation();
    }
  }

  /// Writes an explicit user copy after any in-flight synchronization.
  ///
  /// The user-initiated value wins over phone text that was already pending,
  /// then follows the normal opted-in host-to-phone synchronization policy.
  Future<void> writeHostText(String text) async {
    await _acquireOperation();
    if (_disposed) {
      _finishOperation();
      throw StateError('The desktop clipboard coordinator is disposed.');
    }
    try {
      _pendingDeviceText = null;
      await hostClipboard.writeText(text);
    } finally {
      _finishOperation();
      if (_valid(_generation)) unawaited(synchronizeOnce());
    }
  }

  Future<void> _acquireOperation() async {
    while (_busy) {
      final waiter = _idleWaiter ??= Completer<void>();
      await waiter.future;
    }
    _beginOperation();
  }

  void _beginOperation() {
    assert(!_busy);
    _busy = true;
  }

  void _finishOperation() {
    _busy = false;
    final waiter = _idleWaiter;
    _idleWaiter = null;
    waiter?.complete();
  }

  void _acceptSnapshot(OpenDexSnapshot snapshot) {
    final enabled =
        snapshot.boot.isReady &&
        snapshot.agentStatus == AgentConnectionStatus.connected &&
        snapshot.clipboard.availability == ClipboardAvailability.available &&
        snapshot.clipboard.syncEnabled;
    final deviceId = snapshot.selectedDevice?.id;
    if (!enabled || deviceId != _deviceId) {
      _generation++;
      _lastDeviceText = null;
      _pendingDeviceText = null;
    }
    final wasEnabled = _enabled;
    _enabled = enabled;
    _deviceId = deviceId;
    if (!enabled) return;
    final text = snapshot.clipboard.kind == ClipboardKind.text
        ? snapshot.clipboard.text
        : null;
    if (wasEnabled && text != null && text != _lastDeviceText) {
      _pendingDeviceText = text;
    }
    _lastDeviceText = text;
    unawaited(synchronizeOnce());
  }

  Future<void> dispose() async {
    _disposed = true;
    _enabled = false;
    _generation++;
    _pendingDeviceText = null;
    _lastDeviceText = null;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
