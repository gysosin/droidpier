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

  /// Moves the desk to another virtual workspace. 1-based, see [kWorkspaceCount].
  Future<VoidResult> selectWorkspace(int workspace);

  /// Sends one window to another virtual workspace.
  Future<VoidResult> moveWindowToWorkspace(String sessionId, int workspace);

  /// Sets one window's zoom factor, 1.0 being the device's own pixel scale.
  Future<VoidResult> setWindowScale(String sessionId, double scale);

  /// Rotates one window between its portrait and landscape aspects.
  Future<VoidResult> setWindowOrientation(
    String sessionId, {
    required bool landscape,
  });

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

  /// Opens a web address in the desktop's default browser.
  ///
  /// Lives on the facade rather than in a widget so that `lib/ui` never
  /// reaches a process directly, and so the scheme is validated in one place.
  Future<VoidResult> openUrl(String url);

  /// Opens a web address in the phone's own browser, as a desk window.
  ///
  /// The phone decides which app handles the address; that app must be in
  /// [OpenDexSnapshot.applications], because only listed apps can be streamed.
  /// The window then behaves like one from [launchApplication], and the
  /// result is its session id. [openUrl] is the desktop's browser instead.
  Future<CommandResult<String>> openUrlOnPhone(String url);

  /// Streams the phone's own screen to the desk, view only.
  ///
  /// Progress lands on [OpenDexSnapshot.displayMirror] rather than only in
  /// the result, because the stream outlives the call: the phone can rotate
  /// it, and it can die. A call while already starting or streaming is a
  /// no-op that succeeds.
  Future<VoidResult> startDisplayMirror();

  /// Ends the screen stream and releases its surface.
  Future<VoidResult> stopDisplayMirror();

  Future<void> dispose();
}
