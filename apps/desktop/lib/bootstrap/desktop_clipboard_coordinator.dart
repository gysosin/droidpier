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
  bool _syncEnabled = false;
  bool _synchronizing = false;
  String? _lastDeviceText;

  void start() {
    if (_subscription != null) return;
    _acceptSnapshot(facade.snapshot);
    _subscription = facade.states.listen(_acceptSnapshot);
    _timer = Timer.periodic(pollInterval, (_) => unawaited(synchronizeOnce()));
  }

  Future<void> synchronizeOnce() async {
    if (!_syncEnabled || _synchronizing) return;
    _synchronizing = true;
    try {
      final hostText = await hostClipboard.readText();
      if (hostText == null || hostText.length > maximumTextLength) return;
      if (hostText != facade.snapshot.clipboard.text) {
        await facade.setClipboardText(hostText);
      }
    } on Object {
      // Host clipboard access can be unavailable in headless sessions.
    } finally {
      _synchronizing = false;
    }
  }

  void _acceptSnapshot(OpenDexSnapshot snapshot) {
    final enabled = snapshot.clipboard.syncEnabled;
    final deviceText = snapshot.clipboard.kind == ClipboardKind.text
        ? snapshot.clipboard.text
        : null;
    if (!enabled) {
      _syncEnabled = false;
      _lastDeviceText = null;
      return;
    }
    if (!_syncEnabled) {
      _syncEnabled = true;
      _lastDeviceText = deviceText;
      unawaited(synchronizeOnce());
      return;
    }
    if (deviceText == null || deviceText == _lastDeviceText) return;
    _lastDeviceText = deviceText;
    unawaited(_copyDeviceToHost(deviceText));
  }

  Future<void> _copyDeviceToHost(String text) async {
    if (_synchronizing) return;
    _synchronizing = true;
    try {
      if (await hostClipboard.readText() != text) {
        await hostClipboard.writeText(text);
      }
    } on Object {
      // Retain the last safe facade state and retry on a later change.
    } finally {
      _synchronizing = false;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
