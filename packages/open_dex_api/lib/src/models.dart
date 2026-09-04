import 'result.dart';
import 'wireless.dart';

const _unset = Object();

enum LoadStatus { idle, loading, ready, empty, unavailable, error }

enum BootPhase {
  idle,
  startingAdb,
  discoveringDevice,
  connectingDevice,
  startingServers,
  deployingAgent,
  installingCompanion,
  awaitingHandshakes,
  loadingApplications,
  ready,
  failed,
}

enum StageStatus { pending, active, complete, failed }

class BootStage {
  const BootStage({
    required this.id,
    required this.label,
    this.status = StageStatus.pending,
    this.detail,
  });

  final String id;
  final String label;
  final StageStatus status;
  final String? detail;
}

const defaultBootStages = [
  BootStage(id: 'adb', label: 'ADB'),
  BootStage(id: 'device', label: 'Device'),
  BootStage(id: 'agent', label: 'Agent :3698'),
  BootStage(id: 'companion', label: 'Companion :3699'),
  BootStage(id: 'applications', label: 'Applications'),
];

class BootState {
  const BootState({
    this.phase = BootPhase.idle,
    this.progress = 0,
    this.message = 'Ready to connect',
    this.stages = defaultBootStages,
    this.error,
  });

  final BootPhase phase;
  final double progress;
  final String message;
  final List<BootStage> stages;
  final OpenDexError? error;

  bool get isReady => phase == BootPhase.ready;
}

enum DeviceConnectionKind { usb, wifi }

enum DeviceStatus { authorized, unauthorized, offline }

class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.name,
    required this.connectionKind,
    required this.status,
    this.androidVersion,
    this.model,
  });

  final String id;
  final String name;
  final DeviceConnectionKind connectionKind;
  final DeviceStatus status;
  final String? androidVersion;
  final String? model;
}

class AndroidApplication {
  const AndroidApplication({
    required this.packageName,
    required this.label,
    this.iconPng,
    this.isSystemApp = false,
  });

  final String packageName;
  final String label;
  final List<int>? iconPng;
  final bool isSystemApp;
}

enum WindowSessionStatus {
  starting,
  streaming,
  suspended,
  reconnecting,
  failed,
  closed,
}

class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static const double minimumWidth = 240;
  static const double minimumHeight = 180;

  final double x;
  final double y;
  final double width;
  final double height;
}

enum WindowDisplayState { normal, minimised, maximised }

class WindowPixelSize {
  const WindowPixelSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// Opaque handle for a native video texture owned by the desktop host.
class WindowSurface {
  const WindowSurface({required this.textureId, required this.pixelSize});

  final int textureId;
  final WindowPixelSize pixelSize;
}

enum WindowPointerPhase { down, move, up, cancel, scroll }

/// Pointer coordinates are native surface pixels, not Flutter logical pixels.
class WindowPointerSample {
  const WindowPointerSample({
    required this.phase,
    required this.x,
    required this.y,
    required this.pointerId,
    this.buttons = 0,
    this.scrollDeltaX = 0,
    this.scrollDeltaY = 0,
  });

  final WindowPointerPhase phase;
  final double x;
  final double y;
  final int pointerId;
  final int buttons;
  final double scrollDeltaX;
  final double scrollDeltaY;
}

enum WindowKeyPhase { down, up }

class WindowKeySample {
  const WindowKeySample({
    required this.phase,
    required this.physicalKeyId,
    required this.logicalKeyId,
    this.character,
    this.repeat = false,
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final WindowKeyPhase phase;
  final int physicalKeyId;
  final int logicalKeyId;
  final String? character;
  final bool repeat;

  /// Modifier keys held when this event fired.
  ///
  /// Carried so command combinations — Ctrl+C, Ctrl+A — reach the phone as a
  /// keycode with the right meta-state, rather than being mistaken for typed
  /// text. Without these the modifier is lost and the shortcut does nothing.
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;
}

/// How many virtual desktops the workspace switcher offers.
///
/// Fixed rather than user-configurable: the taskbar renders one numbered key
/// per workspace, and a variable count turns that into a layout problem for no
/// gain nobody has asked for.
const int kWorkspaceCount = 4;

/// Whether [workspace] names one of the desks that actually exist.
bool isValidWorkspace(int workspace) =>
    workspace >= 1 && workspace <= kWorkspaceCount;

/// The zoom factors a window may be rendered at.
const double kMinimumWindowScale = 0.5;
const double kMaximumWindowScale = 3.0;

/// Whether [scale] is a zoom factor a window can actually be drawn at.
bool isValidWindowScale(double scale) =>
    scale.isFinite &&
    scale >= kMinimumWindowScale &&
    scale <= kMaximumWindowScale;

/// Whether [url] is a web address the desk may hand to the system browser.
///
/// The desk search feeds this, and an application label or notification body
/// can reach it too, so it is not enough for the caller to be careful. Anything
/// that is not `http` or `https` with a real host — `file:`, `javascript:`,
/// `data:`, or a bare string that a shell would read as a flag — is refused
/// here rather than at the call site.
bool isWebUrl(String url) {
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null) return false;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return false;
  return parsed.host.isNotEmpty;
}

class WindowSessionState {
  const WindowSessionState({
    required this.id,
    required this.application,
    required this.status,
    this.displayId,
    this.isFocused = false,
    this.geometry = const WindowGeometry(x: 64, y: 64, width: 640, height: 480),
    this.displayState = WindowDisplayState.normal,
    this.zOrder = 0,
    this.surface,
    this.producedFramesPerSecond,
    this.presentedFramesPerSecond,
    this.droppedFramesPerSecond,
    this.error,
    this.workspace = 1,
    this.scale = 1.0,
    this.isLandscape = false,
  });

  final String id;
  final AndroidApplication application;
  final WindowSessionStatus status;
  final int? displayId;
  final bool isFocused;
  final WindowGeometry geometry;
  final WindowDisplayState displayState;
  final int zOrder;
  final WindowSurface? surface;
  final double? producedFramesPerSecond;
  final double? presentedFramesPerSecond;
  final double? droppedFramesPerSecond;
  final OpenDexError? error;

  /// Which virtual desktop this window sits on. 1-based, see [kWorkspaceCount].
  final int workspace;

  /// Per-window zoom, 1.0 being the device's own pixel scale.
  final double scale;

  /// Whether the window is currently rendered in its landscape aspect.
  final bool isLandscape;

  WindowPixelSize? get surfaceSize => surface?.pixelSize;

  /// Copies the session, changing only what is named.
  ///
  /// Every window transition goes through here. It used to go through two
  /// hand-rolled helpers that each enumerated every field, which meant a new
  /// field was silently dropped on every move, raise and resize until someone
  /// remembered to add it in both places.
  WindowSessionState copyWith({
    WindowSessionStatus? status,
    int? displayId,
    bool? isFocused,
    WindowGeometry? geometry,
    WindowDisplayState? displayState,
    int? zOrder,
    WindowSurface? surface,
    double? producedFramesPerSecond,
    double? presentedFramesPerSecond,
    double? droppedFramesPerSecond,
    OpenDexError? error,
    int? workspace,
    double? scale,
    bool? isLandscape,
  }) => WindowSessionState(
    id: id,
    application: application,
    status: status ?? this.status,
    displayId: displayId ?? this.displayId,
    isFocused: isFocused ?? this.isFocused,
    geometry: geometry ?? this.geometry,
    displayState: displayState ?? this.displayState,
    zOrder: zOrder ?? this.zOrder,
    surface: surface ?? this.surface,
    producedFramesPerSecond:
        producedFramesPerSecond ?? this.producedFramesPerSecond,
    presentedFramesPerSecond:
        presentedFramesPerSecond ?? this.presentedFramesPerSecond,
    droppedFramesPerSecond:
        droppedFramesPerSecond ?? this.droppedFramesPerSecond,
    error: error ?? this.error,
    workspace: workspace ?? this.workspace,
    scale: scale ?? this.scale,
    isLandscape: isLandscape ?? this.isLandscape,
  );
}

class DeviceTelemetry {
  const DeviceTelemetry({
    this.batteryPercentage,
    this.charging = false,
    this.wifiEnabled,
    this.bluetoothEnabled,
    this.airplaneMode,
    this.rotationLocked,
    this.torchEnabled,
    this.mobileDataEnabled,
    this.locationEnabled,
    this.volume = const {},
    this.linkLatency,
    this.throughput,
    this.framesPerSecond,
  });

  final int? batteryPercentage;
  final bool charging;
  final bool? wifiEnabled;
  final bool? bluetoothEnabled;
  final bool? airplaneMode;
  final bool? rotationLocked;
  final bool? torchEnabled;
  final bool? mobileDataEnabled;
  final bool? locationEnabled;
  final Map<String, VolumeLevel> volume;
  final TelemetryMeasurement? linkLatency;
  final TelemetryMeasurement? throughput;
  final TelemetryMeasurement? framesPerSecond;
}

enum TelemetryUnit { milliseconds, bytesPerSecond, framesPerSecond }

class TelemetryMeasurement {
  const TelemetryMeasurement({required this.value, required this.unit});

  final double value;
  final TelemetryUnit unit;
}

class VolumeLevel {
  const VolumeLevel({required this.current, required this.maximum});

  final int current;
  final int maximum;
}

enum ClipboardKind { empty, text, image }

enum ClipboardAvailability { unknown, available, unavailable }

class ClipboardState {
  static const desktopFailureMessage =
      'Clipboard sync is paused because the desktop clipboard could not be accessed. Retry when it is available.';

  const ClipboardState({
    this.kind = ClipboardKind.empty,
    this.text,
    this.imagePng,
    this.syncEnabled = false,
    this.availability = ClipboardAvailability.unknown,
    this.message,
  });

  final ClipboardKind kind;
  final String? text;
  final List<int>? imagePng;
  final bool syncEnabled;
  final ClipboardAvailability availability;
  final String? message;
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.packageName,
    required this.title,
    required this.body,
    required this.timestamp,
  });

  final String id;
  final String packageName;
  final String title;
  final String body;
  final DateTime timestamp;
}

enum PlaybackState { unavailable, stopped, paused, playing }

class MediaState {
  const MediaState({
    this.status = LoadStatus.idle,
    this.playback = PlaybackState.unavailable,
    this.title,
    this.artist,
    this.artwork,
    this.positionMs,
    this.durationMs,
  });

  final LoadStatus status;
  final PlaybackState playback;
  final String? title;
  final String? artist;
  final List<int>? artwork;

  /// Playback position and total length, for the scrubber. The UI extrapolates
  /// a live position from [positionMs] while [playback] is playing, so the bar
  /// ticks without the phone streaming a value every second.
  final int? positionMs;
  final int? durationMs;
}

enum PermissionGrant { granted, denied, requiresSettings, unavailable }

class PermissionState {
  const PermissionState({
    this.status = LoadStatus.idle,
    this.grants = const {},
  });

  final LoadStatus status;
  final Map<String, PermissionGrant> grants;
}

enum RecoveryPhase {
  idle,
  detecting,
  reconnecting,
  restartingServices,
  recovered,
  failed,
}

class RecoveryState {
  const RecoveryState({
    this.phase = RecoveryPhase.idle,
    this.attempt = 0,
    this.message,
    this.error,
  });

  final RecoveryPhase phase;
  final int attempt;
  final String? message;
  final OpenDexError? error;
}

enum AgentConnectionStatus { unavailable, starting, connected, reconnecting }

class OpenDexSnapshot {
  const OpenDexSnapshot({
    this.boot = const BootState(),
    this.deviceStatus = LoadStatus.idle,
    this.devices = const [],
    this.selectedDevice,
    this.applicationStatus = LoadStatus.idle,
    this.applications = const [],
    this.windows = const [],
    this.telemetry = const DeviceTelemetry(),
    this.clipboard = const ClipboardState(),
    this.notificationStatus = LoadStatus.idle,
    this.notifications = const [],
    this.media = const MediaState(),
    this.permissions = const PermissionState(),
    this.recovery = const RecoveryState(),
    this.agentStatus = AgentConnectionStatus.unavailable,
    this.wirelessDiscovery = const WirelessDiscoveryState(),
    this.wirelessPairing = const WirelessPairingState(),
    this.currentWorkspace = 1,
  });

  final BootState boot;
  final LoadStatus deviceStatus;
  final List<DeviceSummary> devices;
  final DeviceSummary? selectedDevice;
  final LoadStatus applicationStatus;
  final List<AndroidApplication> applications;
  final List<WindowSessionState> windows;
  final DeviceTelemetry telemetry;
  final ClipboardState clipboard;
  final LoadStatus notificationStatus;
  final List<NotificationItem> notifications;
  final MediaState media;
  final PermissionState permissions;
  final RecoveryState recovery;
  final AgentConnectionStatus agentStatus;
  final WirelessDiscoveryState wirelessDiscovery;
  final WirelessPairingState wirelessPairing;

  /// The virtual desktop currently on screen. 1-based, see [kWorkspaceCount].
  final int currentWorkspace;

  OpenDexSnapshot copyWith({
    BootState? boot,
    LoadStatus? deviceStatus,
    List<DeviceSummary>? devices,
    Object? selectedDevice = _unset,
    LoadStatus? applicationStatus,
    List<AndroidApplication>? applications,
    List<WindowSessionState>? windows,
    DeviceTelemetry? telemetry,
    ClipboardState? clipboard,
    LoadStatus? notificationStatus,
    List<NotificationItem>? notifications,
    MediaState? media,
    PermissionState? permissions,
    RecoveryState? recovery,
    AgentConnectionStatus? agentStatus,
    WirelessDiscoveryState? wirelessDiscovery,
    WirelessPairingState? wirelessPairing,
    int? currentWorkspace,
  }) => OpenDexSnapshot(
    boot: boot ?? this.boot,
    deviceStatus: deviceStatus ?? this.deviceStatus,
    devices: devices ?? this.devices,
    selectedDevice: identical(selectedDevice, _unset)
        ? this.selectedDevice
        : selectedDevice as DeviceSummary?,
    applicationStatus: applicationStatus ?? this.applicationStatus,
    applications: applications ?? this.applications,
    windows: windows ?? this.windows,
    telemetry: telemetry ?? this.telemetry,
    clipboard: clipboard ?? this.clipboard,
    notificationStatus: notificationStatus ?? this.notificationStatus,
    notifications: notifications ?? this.notifications,
    media: media ?? this.media,
    permissions: permissions ?? this.permissions,
    recovery: recovery ?? this.recovery,
    agentStatus: agentStatus ?? this.agentStatus,
    wirelessDiscovery: wirelessDiscovery ?? this.wirelessDiscovery,
    wirelessPairing: wirelessPairing ?? this.wirelessPairing,
    currentWorkspace: currentWorkspace ?? this.currentWorkspace,
  );
}

enum MediaAction { previous, playPause, next }

enum DeviceControl {
  wifi,
  bluetooth,
  airplaneMode,
  rotationLock,
  torch,
  mobileData,
  location,
}

/// An Android navigation key, for the desk's bottom nav pill.
///
/// These are injected into the focused window's display, so [back] is reliable
/// while [home]/[recents] depend on what the app's virtual display honours.
enum AndroidNavKey { menu, home, back, recents, search }
