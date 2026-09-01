import 'package:flutter/widgets.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// Workspace view models.
///
/// `WindowGeometry`, `WindowDisplayState` and `WindowSurface` are now published
/// by `open_dex_api` and come straight from the backend — the local copies that
/// stood in for them before the facade carried them are gone. What remains here
/// is genuinely UI-side: the compositor's view of a window, the intents it
/// sends, and where a dragged window snaps.
///
/// The UI never mutates window state. It sends intent through
/// [WorkspaceIntents] and renders whatever comes back, so there is one source
/// of truth even mid-drag.

/// Geometry helpers the UI needs and the wire format has no reason to carry.
extension WorkspaceGeometry on WindowGeometry {
  Rect get rect => Rect.fromLTWH(x, y, width, height);

  /// Below this an Android app is unusable and the frame chrome dominates.
  static const Size minimum = Size(
    WindowGeometry.minimumWidth,
    WindowGeometry.minimumHeight,
  );

  WindowGeometry copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return WindowGeometry(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Keeps a window reachable: it may hang off an edge, but never so far that
  /// the title bar — the only way to drag it back — leaves the workspace.
  WindowGeometry clampedTo(Size workspace, {double titleBar = 34}) {
    const double margin = 48;
    return copyWith(
      x: x.clamp(margin - width, workspace.width - margin),
      y: y.clamp(0, workspace.height - titleBar),
    );
  }
}

/// One composited window.
@immutable
class WorkspaceWindow {
  const WorkspaceWindow({
    required this.session,
    required this.geometry,
    required this.zOrder,
    this.displayState = WindowDisplayState.normal,
    this.surface,
    this.previewBuilder,
    this.presentedFramesPerSecond,
  });

  final WindowSessionState session;
  final WindowGeometry geometry;

  /// Higher paints later. Deliberately independent of focus: a window can be
  /// raised without being focused, and focused without moving in z.
  final int zOrder;

  final WindowDisplayState displayState;

  /// The backend's video texture for this window. Null while it has not
  /// produced frames yet; the frame renders a skeleton in that case, never an
  /// empty rectangle — an empty rectangle reads as a broken app.
  final WindowSurface? surface;

  /// Paints in place of [surface]. Tests and goldens only: a texture id has
  /// nothing behind it outside a running host, so a widget test that wanted to
  /// assert on a streaming window could not render one.
  final WidgetBuilder? previewBuilder;

  /// Delivered frames per second for this window, when the backend reports it.
  /// Frames per second actually reaching the screen.
  ///
  /// Named for the quantity rather than "frames" because the two gateways once
  /// disagreed about which rate a bare `framesPerSecond` carried, and the
  /// difference between produced and presented was five-fold.
  final double? presentedFramesPerSecond;

  String get id => session.id;
  bool get isFocused => session.isFocused;
  bool get isMinimised => displayState == WindowDisplayState.minimised;

  WorkspaceWindow copyWith({
    WindowSessionState? session,
    WindowGeometry? geometry,
    int? zOrder,
    WindowDisplayState? displayState,
    WindowSurface? surface,
    WidgetBuilder? previewBuilder,
    double? presentedFramesPerSecond,
  }) {
    return WorkspaceWindow(
      session: session ?? this.session,
      geometry: geometry ?? this.geometry,
      zOrder: zOrder ?? this.zOrder,
      displayState: displayState ?? this.displayState,
      surface: surface ?? this.surface,
      previewBuilder: previewBuilder ?? this.previewBuilder,
      presentedFramesPerSecond:
          presentedFramesPerSecond ?? this.presentedFramesPerSecond,
    );
  }
}

/// What the workspace asks the backend to do.
///
/// Every one is a request, not a local mutation. The UI renders the answer.
@immutable
class WorkspaceIntents {
  const WorkspaceIntents({
    required this.focus,
    required this.raise,
    required this.move,
    required this.setDisplayState,
    required this.close,
    required this.retry,
    this.fullscreen,
    this.sendPointer,
  });

  final ValueChanged<String> focus;
  final ValueChanged<String> raise;
  final void Function(String id, WindowGeometry geometry) move;
  final void Function(String id, WindowDisplayState state) setDisplayState;
  final ValueChanged<String> close;
  final ValueChanged<String> retry;

  /// Enters edge-to-edge fullscreen for a window — the title bar's expand
  /// button. Null where the host has no fullscreen surface (e.g. in a test
  /// harness), in which case the button is hidden.
  final ValueChanged<String>? fullscreen;

  /// Raw pointer input for the embedded surface, in surface pixels. Null while
  /// no backend is wired, in which case the surface consumes its own input.
  final void Function(String id, WindowPointerSample sample)? sendPointer;
}

/// Where a window lands when dragged to an edge.
enum WindowSnap {
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  maximise;

  /// The geometry this zone produces in a workspace of [size].
  WindowGeometry geometryIn(Size size) {
    final double w = size.width / 2;
    final double h = size.height / 2;
    return switch (this) {
      WindowSnap.left => WindowGeometry(
        x: 0,
        y: 0,
        width: w,
        height: size.height,
      ),
      WindowSnap.right => WindowGeometry(
        x: w,
        y: 0,
        width: w,
        height: size.height,
      ),
      WindowSnap.topLeft => WindowGeometry(x: 0, y: 0, width: w, height: h),
      WindowSnap.topRight => WindowGeometry(x: w, y: 0, width: w, height: h),
      WindowSnap.bottomLeft => WindowGeometry(x: 0, y: h, width: w, height: h),
      WindowSnap.bottomRight => WindowGeometry(x: w, y: h, width: w, height: h),
      WindowSnap.maximise => WindowGeometry(
        x: 0,
        y: 0,
        width: size.width,
        height: size.height,
      ),
    };
  }

  /// What a person would call this arrangement.
  String get label => switch (this) {
    WindowSnap.left => 'Left half',
    WindowSnap.right => 'Right half',
    WindowSnap.topLeft => 'Top left quarter',
    WindowSnap.topRight => 'Top right quarter',
    WindowSnap.bottomLeft => 'Bottom left quarter',
    WindowSnap.bottomRight => 'Bottom right quarter',
    WindowSnap.maximise => 'Maximise',
  };

  /// The zone a pointer at [p] is in, or null for none.
  ///
  /// Corners are tested before edges, or dragging into a corner would only ever
  /// register as the edge it crossed first.
  static WindowSnap? forPointer(Offset p, Size size) {
    const double edge = 24;
    const double corner = 96;
    final bool left = p.dx <= edge;
    final bool right = p.dx >= size.width - edge;
    final bool top = p.dy <= edge;
    final bool bottom = p.dy >= size.height - edge;
    final bool nearTop = p.dy <= corner;
    final bool nearBottom = p.dy >= size.height - corner;

    if (left && nearTop) return WindowSnap.topLeft;
    if (right && nearTop) return WindowSnap.topRight;
    if (left && nearBottom) return WindowSnap.bottomLeft;
    if (right && nearBottom) return WindowSnap.bottomRight;
    if (left) return WindowSnap.left;
    if (right) return WindowSnap.right;
    if (top) return WindowSnap.maximise;
    if (bottom) return null;
    return null;
  }
}

/// The height of a window's title bar. Chrome, not content.
const double kWindowChrome = 34;

/// [current] turned from landscape to portrait, or back.
///
/// A one-shot orientation change rather than a rotation lock: the Android app
/// stays free to request its own orientation afterwards. The caller is expected
/// to leave snap or maximise first, since neither survives a resize
/// meaningfully.
///
/// The *content* aspect inverts, not the frame. Swapping the frame's own width
/// and height would leave the video letterboxed by exactly the title bar's
/// height, which is the kind of one-off error that looks like a rendering bug.
WindowGeometry rotatedGeometry(
  WindowGeometry current,
  Size workspace, {
  double chrome = kWindowChrome,
}) {
  final double contentWidth = current.width;
  final double contentHeight = (current.height - chrome).clamp(1, double.infinity);

  double width = contentHeight;
  double height = contentWidth + chrome;

  // A very wide window rotates into something taller than the desk, which
  // cannot be dragged back into view. Scale the pair down rather than clipping
  // one side and distorting the aspect.
  final double maxWidth = workspace.width;
  final double maxHeight = workspace.height;
  if (width > maxWidth || height > maxHeight) {
    final double scale =
        (maxWidth / width) < (maxHeight / height)
        ? maxWidth / width
        : maxHeight / height;
    width *= scale;
    height = (height - chrome) * scale + chrome;
  }

  width = width.clamp(WindowGeometry.minimumWidth, maxWidth);
  height = height.clamp(WindowGeometry.minimumHeight, maxHeight);

  // Turn about the centre, so the window does not appear to jump across the
  // desk when it changes shape.
  final double centreX = current.x + current.width / 2;
  final double centreY = current.y + current.height / 2;

  return WindowGeometry(
    x: centreX - width / 2,
    y: centreY - height / 2,
    width: width,
    height: height,
  ).clampedTo(workspace);
}

/// What the rotate control should be called, given what it will do next.
///
/// Names the destination rather than the current state: a control labelled with
/// what you already have is the ambiguous-expand-icon problem again.
String rotateActionLabel(WindowGeometry current, {double chrome = kWindowChrome}) =>
    (current.height - chrome) >= current.width ? 'Landscape' : 'Portrait';
