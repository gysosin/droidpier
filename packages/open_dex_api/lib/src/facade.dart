import 'models.dart';
import 'result.dart';

abstract interface class OpenDexFacade {
  OpenDexSnapshot get snapshot;

  Stream<OpenDexSnapshot> get states;

  Future<CommandResult<List<DeviceSummary>>> discoverDevices();

  Future<VoidResult> selectDevice(String deviceId);

  Future<VoidResult> connectSelectedDevice();

  Future<VoidResult> disconnect();

  Future<VoidResult> retryBoot();

  Future<CommandResult<String>> launchApplication(String packageName);

  Future<VoidResult> closeWindow(String sessionId);

  Future<VoidResult> focusWindow(String sessionId);

  Future<VoidResult> moveWindow(String sessionId, WindowGeometry geometry);

  Future<VoidResult> setWindowDisplayState(
    String sessionId,
    WindowDisplayState state,
  );

  Future<VoidResult> raiseWindow(String sessionId);

  Future<VoidResult> sendPointer(String sessionId, WindowPointerSample sample);

  Future<VoidResult> sendKey(String sessionId, WindowKeySample sample);

  /// Injects an Android navigation key into the focused window's display.
  Future<VoidResult> sendNavKey(String sessionId, AndroidNavKey key);

  Future<VoidResult> setClipboardText(String text);

  Future<VoidResult> setClipboardSync(bool enabled);

  /// Pauses after a desktop clipboard failure, keeping an inline retry reason.
  Future<VoidResult> pauseClipboardSync();

  Future<VoidResult> setVolume(String stream, int value);

  Future<VoidResult> sendMediaAction(MediaAction action);

  Future<VoidResult> setDeviceControl(DeviceControl control, bool enabled);

  Future<VoidResult> openPermissionSettings(String capability);

  Future<VoidResult> dismissNotification(String notificationId);

  Future<VoidResult> activateNotification(String notificationId);

  Future<VoidResult> dismissAllNotifications();

  Future<VoidResult> reconnect();

  Future<VoidResult> startWirelessDiscovery();

  Future<VoidResult> stopWirelessDiscovery();

  Future<VoidResult> startQrPairing();

  Future<VoidResult> cancelWirelessPairing();

  Future<VoidResult> pairWirelessDevice({
    required String host,
    required int pairingPort,
    required String pairingCode,
  });

  Future<CommandResult<DeviceSummary>> connectWirelessDevice({
    required String host,
    required int port,
  });

  Future<VoidResult> forgetWirelessDevice(String deviceId);

  Future<void> dispose();
}
