import 'package:open_dex_api/open_dex_api.dart';

class BackendFailure implements Exception {
  const BackendFailure(this.error);

  final OpenDexError error;
}

abstract interface class DeviceGateway {
  Future<void> start();

  Future<List<DeviceSummary>> discoverDevices();

  Future<DeviceSummary> prepareDevice(DeviceSummary device);

  Future<void> disconnectDevice(DeviceSummary device);
}

abstract interface class WirelessDeviceGateway {
  Future<void> pair({
    required String host,
    required int pairingPort,
    required String pairingCode,
  });

  Future<DeviceSummary> connect({required String host, required int port});

  Future<void> forget(String deviceId);
}

abstract interface class WirelessPairingGateway {
  /// Returns the authenticated device GUID, never the supplied secret.
  Future<String?> pairWithSecret({
    required String host,
    required int port,
    required String secret,
  });

  Future<void> cancelPending();
}

abstract interface class WirelessDiscoveryGateway {
  WirelessDiscoveryState get current;
  Stream<WirelessDiscoveryState> get updates;
  Future<void> start();
  Future<void> stop();
}

abstract interface class BootComponent {
  String get stageId;

  Future<void> start(DeviceSummary device);

  Future<void> stop(DeviceSummary device);
}

/// Opens a web address using whatever the host desktop uses for the job.
///
/// Injected rather than called directly because this package is compiled for
/// the web as well, where `dart:io` does not exist.
abstract interface class UrlLauncherGateway {
  Future<void> open(Uri url);
}

abstract interface class ApplicationCatalogProvider {
  List<AndroidApplication> get applications;
}

class BackendStateUpdate {
  const BackendStateUpdate({
    this.telemetry,
    this.clipboard,
    this.permissions,
    this.notificationStatus,
    this.notifications,
    this.media,
  });

  final DeviceTelemetry? telemetry;
  final ClipboardState? clipboard;
  final PermissionState? permissions;
  final LoadStatus? notificationStatus;
  final List<NotificationItem>? notifications;
  final MediaState? media;
}

abstract interface class BackendStateProvider {
  BackendStateUpdate get currentUpdate;

  Stream<BackendStateUpdate> get updates;
}

/// Explicit user intent from an authenticated companion, not a transport loss.
abstract interface class UserDisconnectProvider {
  bool get userDisconnectRequested;
  Stream<void> get userDisconnectRequests;
}

class WindowBackendSession {
  const WindowBackendSession({required this.id, this.displayId, this.surface});

  final String id;
  final int? displayId;
  final WindowSurface? surface;
}

class WindowBackendExit {
  const WindowBackendExit({
    required this.sessionId,
    required this.exitCode,
    this.details,
  });

  final String sessionId;
  final int exitCode;
  final String? details;
}

/// One live stream of the phone's own display, as the backend sees it.
class MirrorBackendSession {
  const MirrorBackendSession({required this.id, required this.surface});
  final String id;
  final WindowSurface surface;
}

class MirrorBackendExit {
  const MirrorBackendExit({
    required this.sessionId,
    required this.exitCode,
    this.details,
  });
  final String sessionId;
  final int exitCode;
  final String? details;
}

/// Streams the phone's display 0 to a desktop texture, view only.
///
/// Kept apart from [WindowGateway]: a window is a virtual display the desk
/// creates, sizes and drives, while the mirror follows a display the phone
/// owns. Different lifetime, no input, and one at a time.
abstract interface class DisplayMirrorGateway {
  Stream<MirrorBackendExit> get exits;

  /// A replacement surface after the phone rotates; the id is unchanged.
  Stream<MirrorBackendSession> get surfaceUpdates;
  Future<MirrorBackendSession> start(DeviceSummary device);
  Future<void> stop(String sessionId);
  Future<void> dispose();
}

class WindowBackendTelemetry {
  const WindowBackendTelemetry({
    required this.sessionId,
    this.producedFramesPerSecond,
    this.presentedFramesPerSecond,
    this.droppedFramesPerSecond,
  });

  final String sessionId;
  final double? producedFramesPerSecond;
  final double? presentedFramesPerSecond;
  final double? droppedFramesPerSecond;
}

class WindowTextureStats {
  const WindowTextureStats({
    required this.frames,
    required this.presentedFrames,
    required this.lastFrameMonotonicUs,
    required this.centerLuma,
    required this.probeLuma,
    required this.droppedFrames,
  });

  final int frames;
  final int presentedFrames;
  final int lastFrameMonotonicUs;
  final int centerLuma;
  final int probeLuma;
  final int droppedFrames;
}

abstract interface class WindowTextureHost {
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  });

  Future<void> waitForFirstFrame(int textureId, {required Duration timeout});

  Future<WindowTextureStats> stats(int textureId);

  Future<void> closeTexture(int textureId);
}

abstract interface class WindowGateway {
  Stream<WindowBackendExit> get exits;

  Stream<WindowBackendTelemetry> get telemetry;

  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  });

  Future<void> close(String sessionId);

  Future<void> sendPointer(String sessionId, WindowPointerSample sample);

  Future<void> sendKey(String sessionId, WindowKeySample sample);

  Future<void> dispose();
}

/// Optional capability for gateways that can replace a live Android surface
/// when the desktop window crosses between landscape and portrait.
abstract interface class ResizableWindowGateway {
  Future<WindowBackendSession> resizeSurface(
    String sessionId,
    WindowPixelSize pixelSize,
  );
}

/// Optional capability for backend-driven surface changes such as an Android
/// application forcing a display rotation without a desktop resize request.
abstract interface class WindowSurfaceUpdateGateway {
  Stream<WindowBackendSession> get surfaceUpdates;
}

/// Optional capability for gateways that can open a web address in the
/// phone's browser inside a new window, rather than only start an app by name.
abstract interface class UrlWindowGateway {
  /// The package the phone would hand [url] to, or null when nothing on the
  /// phone can open a web address.
  Future<String?> resolveBrowser(DeviceSummary device, String url);

  Future<WindowBackendSession> launchUrl(
    DeviceSummary device,
    AndroidApplication browser,
    String url, {
    String? sessionId,
  });
}

/// Optional capability for gateways that can inject Android navigation keys
/// (Home/Back/Recents/Menu/Search) into a window's display.
abstract interface class NavKeyWindowGateway {
  Future<void> sendNavKey(String sessionId, AndroidNavKey key);
}

abstract interface class DeviceCommandGateway {
  Future<void> setVolume(String stream, int value);

  Future<void> sendMediaAction(MediaAction action);

  Future<void> setDeviceControl(DeviceControl control, bool enabled);
}

abstract interface class PermissionGateway {
  Future<void> openSettings(String capability);
}

abstract interface class NotificationGateway {
  Future<void> dismiss(String notificationId);

  Future<void> activate(String notificationId, {int? displayId});

  Future<void> dismissAll();
}

abstract interface class ClipboardGateway {
  ClipboardState get clipboard;

  Future<void> writeText(String text);

  void setSyncEnabled(bool enabled);
}
