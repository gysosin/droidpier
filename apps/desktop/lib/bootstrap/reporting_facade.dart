import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';

/// Reports every typed command failure while preserving the facade contract.
///
/// UI surfaces may fire commands through callbacks without duplicating result
/// handling. The desktop bootstrap owns the presentation of the safe message.
class ReportingOpenDexFacade implements OpenDexFacade {
  ReportingOpenDexFacade({required this.delegate, required this.onError});

  final OpenDexFacade delegate;
  final void Function(OpenDexError error) onError;

  @override
  OpenDexSnapshot get snapshot => delegate.snapshot;

  @override
  Stream<OpenDexSnapshot> get states => delegate.states;

  Future<CommandResult<T>> _report<T>(
    Future<CommandResult<T>> command, {
    bool reportCapabilityGaps = true,
  }) async {
    final result = await command;
    if (result case CommandFailure<T>(:final error)) {
      // A capability the current build simply does not have is not a runtime
      // error worth a banner — surfacing it turns every tap on an unsupported
      // control (notification actions on a companion build) into a nag. Callers
      // that would rather stay silent for those pass reportCapabilityGaps:false.
      final bool capabilityGap =
          error.code == OpenDexErrorCode.capabilityUnavailable;
      if (reportCapabilityGaps || !capabilityGap) onError(error);
    }
    return result;
  }

  @override
  Future<CommandResult<List<DeviceSummary>>> discoverDevices() =>
      _report(delegate.discoverDevices());

  @override
  Future<VoidResult> selectDevice(String deviceId) =>
      _report(delegate.selectDevice(deviceId));

  @override
  Future<VoidResult> connectSelectedDevice() =>
      _report(delegate.connectSelectedDevice());

  @override
  Future<VoidResult> disconnect() => _report(delegate.disconnect());

  @override
  Future<VoidResult> retryBoot() => _report(delegate.retryBoot());

  @override
  Future<CommandResult<String>> launchApplication(String packageName) =>
      _report(delegate.launchApplication(packageName));

  @override
  Future<VoidResult> closeWindow(String sessionId) =>
      _report(delegate.closeWindow(sessionId));

  @override
  Future<VoidResult> focusWindow(String sessionId) =>
      _report(delegate.focusWindow(sessionId));

  @override
  Future<VoidResult> moveWindow(String sessionId, WindowGeometry geometry) =>
      _report(delegate.moveWindow(sessionId, geometry));

  @override
  Future<VoidResult> setWindowDisplayState(
    String sessionId,
    WindowDisplayState state,
  ) => _report(delegate.setWindowDisplayState(sessionId, state));

  @override
  Future<VoidResult> raiseWindow(String sessionId) =>
      _report(delegate.raiseWindow(sessionId));

  @override
  Future<VoidResult> selectWorkspace(int workspace) =>
      _report(delegate.selectWorkspace(workspace));

  @override
  Future<VoidResult> moveWindowToWorkspace(String sessionId, int workspace) =>
      _report(delegate.moveWindowToWorkspace(sessionId, workspace));

  @override
  Future<VoidResult> setWindowScale(String sessionId, double scale) =>
      _report(delegate.setWindowScale(sessionId, scale));

  @override
  Future<VoidResult> setWindowOrientation(
    String sessionId, {
    required bool landscape,
  }) => _report(delegate.setWindowOrientation(sessionId, landscape: landscape));

  @override
  Future<VoidResult> openUrl(String url) => _report(delegate.openUrl(url));

  @override
  Future<VoidResult> startDisplayMirror() => _report(
    delegate.startDisplayMirror(),
    // The mirror frame shows its own state; a banner would say it twice.
    reportCapabilityGaps: false,
  );

  @override
  Future<VoidResult> stopDisplayMirror() =>
      _report(delegate.stopDisplayMirror());

  @override
  Future<VoidResult> sendPointer(
    String sessionId,
    WindowPointerSample sample,
  ) => _report(delegate.sendPointer(sessionId, sample));

  @override
  Future<VoidResult> sendKey(String sessionId, WindowKeySample sample) =>
      _report(delegate.sendKey(sessionId, sample));

  @override
  Future<VoidResult> sendNavKey(String sessionId, AndroidNavKey key) =>
      _report(delegate.sendNavKey(sessionId, key));

  @override
  Future<VoidResult> setClipboardText(String text) =>
      delegate.setClipboardText(text);

  @override
  Future<VoidResult> setClipboardSync(bool enabled) =>
      _report(delegate.setClipboardSync(enabled));

  @override
  Future<VoidResult> pauseClipboardSync() => delegate.pauseClipboardSync();

  @override
  Future<VoidResult> setVolume(String stream, int value) =>
      _report(delegate.setVolume(stream, value));

  @override
  Future<VoidResult> sendMediaAction(MediaAction action) =>
      _report(delegate.sendMediaAction(action));

  @override
  Future<VoidResult> setDeviceControl(DeviceControl control, bool enabled) =>
      _report(delegate.setDeviceControl(control, enabled));

  @override
  Future<VoidResult> openPermissionSettings(String capability) =>
      _report(delegate.openPermissionSettings(capability));

  @override
  Future<VoidResult> dismissNotification(String notificationId) => _report(
    delegate.dismissNotification(notificationId),
    reportCapabilityGaps: false,
  );

  @override
  Future<VoidResult> activateNotification(String notificationId) => _report(
    delegate.activateNotification(notificationId),
    reportCapabilityGaps: false,
  );

  @override
  Future<VoidResult> dismissAllNotifications() =>
      _report(delegate.dismissAllNotifications(), reportCapabilityGaps: false);

  @override
  Future<VoidResult> reconnect() => _report(delegate.reconnect());

  @override
  Future<VoidResult> startWirelessDiscovery() =>
      delegate.startWirelessDiscovery();
  @override
  Future<VoidResult> stopWirelessDiscovery() =>
      delegate.stopWirelessDiscovery();
  @override
  Future<VoidResult> startQrPairing() => delegate.startQrPairing();
  @override
  Future<VoidResult> cancelWirelessPairing() =>
      delegate.cancelWirelessPairing();

  @override
  Future<VoidResult> pairWirelessDevice({
    required String host,
    required int pairingPort,
    required String pairingCode,
  }) => delegate.pairWirelessDevice(
    host: host,
    pairingPort: pairingPort,
    pairingCode: pairingCode,
  );

  @override
  Future<CommandResult<DeviceSummary>> connectWirelessDevice({
    required String host,
    required int port,
  }) => delegate.connectWirelessDevice(host: host, port: port);

  @override
  Future<VoidResult> forgetWirelessDevice(String deviceId) =>
      _report(delegate.forgetWirelessDevice(deviceId));

  @override
  Future<void> dispose() => delegate.dispose();
}
