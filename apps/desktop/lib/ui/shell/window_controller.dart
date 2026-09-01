import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../workspace/window_geometry_store.dart';
import '../workspace/window_model.dart';
import '../workspace/workspace.dart' show cascadeGeometry;

/// The compositor's view of the windows: which exist, where they are, and which
/// is on top.
///
/// Lifted out of `AppShell`, which had grown to carry this alongside the desk,
/// the overlays, the clock and the connection. The split is by question rather
/// than by size: this answers *what windows exist and where*, the shell answers
/// *what is on screen*. So the switcher overlay and the exit log stay in the
/// shell — they are about presentation — while everything that mutates the map
/// lives here.
///
/// The UI still never mutates window state on its own authority. Every change
/// here is either a local echo of what the backend has already reported, or an
/// intent sent to the backend which is then echoed back. See
/// `window_model.dart`.
class WindowController {
  WindowController({
    required this.facade,
    required this.notify,
    required this.isMounted,
    required this.rememberedWindows,
    required this.onRememberedChanged,
  });

  final OpenDexFacade facade;

  /// Rebuilds the shell. The controller mutates its own state and then asks to
  /// be redrawn, rather than holding a `State` and calling `setState` on it.
  final VoidCallback notify;

  /// False once the shell is gone. Deferred work — post-frame callbacks, the
  /// move flush — must not touch a disposed tree.
  final bool Function() isMounted;

  /// Remembered placements, read fresh on each use because the shell owns them
  /// and they arrive as a lifted parameter that can change between builds.
  final Map<String, RememberedWindow> Function() rememberedWindows;
  final ValueChanged<Map<String, RememberedWindow>> onRememberedChanged;

  /// Workspace state the facade contract does not carry yet. When it does, this
  /// map disappears and the values come from the snapshot; the widgets already
  /// read it as if it were remote, so the swap is mechanical.
  final Map<String, WorkspaceWindow> windows = <String, WorkspaceWindow>{};

  /// Windows already fitted to their video's aspect ratio, once, when the first
  /// frame revealed it. Kept so a person can freely resize afterwards.
  final Set<String> _aspectFitted = <String>{};

  /// Seeded above whatever the backend has already assigned.
  ///
  /// Starting at 1 while backend zOrders start at 0 and climb meant the first
  /// local raise could hand out a value *below* an existing window. Since the
  /// local echo paints before the backend confirms, the raised window could
  /// appear behind the one it replaced for a frame.
  int _nextZ = 1;

  void _seedZ(Iterable<WindowSessionState> sessions) {
    for (final WindowSessionState s in sessions) {
      if (s.zOrder >= _nextZ) _nextZ = s.zOrder + 1;
    }
  }

  /// The window being dragged. While a drag is in flight the backend's echo of
  /// that window's geometry is ignored.
  String? dragging;

  /// Latest geometry not yet sent to the backend, and the timer that will send
  /// it.
  ///
  /// Trailing-edge on purpose: whatever the last geometry of a gesture is, it
  /// is always delivered, so no explicit drag-end signal is needed and a drag
  /// can never leave the backend holding a stale position.
  final Map<String, WindowGeometry> _pendingMoves = <String, WindowGeometry>{};
  Timer? _moveFlush;

  /// Roughly twelve updates a second. Far below pointer rate, far above what
  /// the backend needs to keep a window where the person put it.
  static const Duration _moveThrottle = Duration(milliseconds: 80);

  /// The title-bar height the controller subtracts when mapping a window to a
  /// phone-display resolution, so a fitted window's *content* matches the video
  /// aspect exactly — no black bars.
  static const double _windowChrome = 34;

  void dispose() {
    _moveFlush?.cancel();
    _moveFlush = null;
  }

  /// Reconciles [sessions] into the local map and returns what to paint.
  ///
  /// [onClosed] reports windows that have gone, so the shell can log them; the
  /// controller has no clock and no business formatting a message.
  List<WorkspaceWindow> sync({
    required List<WindowSessionState> sessions,
    required Size workspaceSize,
    required void Function(WorkspaceWindow closed) onClosed,
  }) {
    _seedZ(sessions);

    for (final WindowSessionState session in sessions) {
      final WorkspaceWindow? existing = windows[session.id];
      final bool isDragging = dragging == session.id;

      if (existing == null) {
        _place(session, workspaceSize);
      } else {
        windows[session.id] = existing.copyWith(
          session: session,
          // Its geometry stays local until the drag ends, so the frame tracks
          // the pointer instead of stuttering against stale echoes.
          geometry: isDragging ? existing.geometry : session.geometry,
          zOrder: session.zOrder,
          displayState: session.displayState,
          surface: session.surface,
          presentedFramesPerSecond: session.presentedFramesPerSecond,
        );
      }
    }

    _fitNewSurfaces(sessions, workspaceSize);

    for (final MapEntry<String, WorkspaceWindow> entry in windows.entries) {
      if (sessions.any((WindowSessionState w) => w.id == entry.key)) continue;
      onClosed(entry.value);
    }
    windows.removeWhere(
      (String id, _) => !sessions.any((WindowSessionState w) => w.id == id),
    );
    return windows.values.toList();
  }

  /// Places a window that has just appeared.
  ///
  /// A brand-new window has whatever geometry the backend defaults to, which is
  /// the same for every window — so two opened in a row would land exactly on
  /// top of each other. A remembered placement wins; failing that the cascade
  /// keeps them apart. Either way the backend is told, and echoes our position
  /// back as the authoritative one.
  void _place(WindowSessionState session, Size workspaceSize) {
    final Map<String, RememberedWindow> remembered = rememberedWindows();
    final String packageName = session.application.packageName;

    final WindowGeometry? recalled = recallWindow(
      remembered,
      packageName,
      workspaceSize,
    );
    final WindowGeometry placed = _isUnplaced(session.geometry)
        ? (recalled ?? cascadeGeometry(windows.length, workspaceSize))
        : session.geometry;

    windows[session.id] = WorkspaceWindow(
      session: session,
      geometry: placed,
      zOrder: session.zOrder,
      displayState: session.displayState,
      surface: session.surface,
      presentedFramesPerSecond: session.presentedFramesPerSecond,
    );

    final String id = session.id;

    // A window remembered as maximised comes back maximised.
    final RememberedWindow? record = remembered[packageName];
    if (record != null &&
        record.maximised &&
        session.displayState != WindowDisplayState.maximised) {
      _afterFrame(
        () => facade.setWindowDisplayState(id, WindowDisplayState.maximised),
      );
    }

    if (placed != session.geometry) {
      _afterFrame(() => facade.moveWindow(id, placed));
    }
  }

  /// Sizes a window to its video's aspect ratio, once, when the first frame
  /// reveals it.
  ///
  /// A portrait app then opens in a portrait window and the phone display stays
  /// portrait, instead of the default landscape window resizing the display
  /// wide and greying the app out. Skipped while dragging, or once the person
  /// has had the chance to resize.
  void _fitNewSurfaces(List<WindowSessionState> sessions, Size workspaceSize) {
    for (final WindowSessionState session in sessions) {
      final String id = session.id;
      final WorkspaceWindow? w = windows[id];
      if (w == null || _aspectFitted.contains(id) || dragging == id) continue;

      final WindowSurface? surface = w.surface;
      if (surface == null ||
          surface.pixelSize.width <= 0 ||
          surface.pixelSize.height <= 0) {
        continue;
      }
      _aspectFitted.add(id);
      if (w.displayState != WindowDisplayState.normal) continue;

      final WindowGeometry fitted = fitToSurface(
        surface,
        workspaceSize,
        w.geometry,
      );
      if ((fitted.width - w.geometry.width).abs() < 1 &&
          (fitted.height - w.geometry.height).abs() < 1) {
        continue;
      }
      windows[id] = w.copyWith(geometry: fitted);
      _afterFrame(() => facade.moveWindow(id, fitted));
    }
  }

  /// Geometry that fits [surface]'s aspect ratio inside [workspace].
  WindowGeometry fitToSurface(
    WindowSurface surface,
    Size workspace,
    WindowGeometry current,
  ) {
    final double aspect = surface.pixelSize.width / surface.pixelSize.height;
    // 0.78, not the full height: leave room for the floating dock band at the
    // bottom so a tall portrait window is not forced taller than the work area
    // (which would push its title bar off the top).
    double contentH = workspace.height * 0.78 - _windowChrome;
    double w = contentH * aspect;
    final double maxW = workspace.width * 0.9;
    if (w > maxW) {
      w = maxW;
      contentH = w / aspect;
    }
    final double h = contentH + _windowChrome;
    final double cx = current.x + current.width / 2;
    final double cy = current.y + current.height / 2;
    return WindowGeometry(
      x: cx - w / 2,
      y: cy - h / 2,
      width: w,
      height: h,
    ).clampedTo(workspace);
  }

  /// Windows Alt+Tab can reach, most recently raised first.
  ///
  /// Cached against the z-order it was built from. The shell reads this from
  /// `build`, which runs on every telemetry snapshot, and allocating a list and
  /// sorting it per frame over a live video texture is the same shape of
  /// mistake as the snap rectangles that cost playback smoothness.
  List<WorkspaceWindow>? _switchableCache;
  int _switchableStamp = -1;

  List<WorkspaceWindow> get switchable {
    // Cheap fingerprint: z-orders and count. Anything that reorders the list
    // changes one of them.
    int stamp = windows.length;
    for (final WorkspaceWindow w in windows.values) {
      stamp = stamp * 31 + w.zOrder;
      stamp = stamp * 31 + w.session.status.index;
    }
    final List<WorkspaceWindow>? cached = _switchableCache;
    if (cached != null && stamp == _switchableStamp) return cached;

    final List<WorkspaceWindow> built =
        windows.values
            .where(
              (WorkspaceWindow w) =>
                  w.session.status != WindowSessionStatus.closed,
            )
            .toList()
          ..sort(
            (WorkspaceWindow a, WorkspaceWindow b) =>
                b.zOrder.compareTo(a.zOrder),
          );
    _switchableCache = built;
    _switchableStamp = stamp;
    return built;
  }

  void raiseAndFocus(String id) {
    final WorkspaceWindow? w = windows[id];
    if (w == null) return;
    if (w.isMinimised) {
      windows[id] = w.copyWith(displayState: WindowDisplayState.normal);
      notify();
      unawaited(
        facade.setWindowDisplayState(id, WindowDisplayState.normal),
      );
    }
    windows[id] = windows[id]!.copyWith(zOrder: _nextZ++);
    notify();
    unawaited(facade.raiseWindow(id));
    facade.focusWindow(id);
  }

  /// Dock click. A minimised window is restored first: focusing a window that
  /// is not on screen changes nothing the person can see, which is exactly how
  /// the minimise/restore round trip was broken.
  void focusOrRestore(String id) {
    final WorkspaceWindow? w = windows[id];
    if (w == null) return;

    // Raise as well as focus. Focusing alone leaves zOrder untouched — the
    // backend is explicit about that — so a window clicked in the dock came
    // forward visually while the switcher went on listing it where it was.
    if (!w.isMinimised) {
      windows[id] = w.copyWith(zOrder: _nextZ++);
      notify();
      unawaited(facade.raiseWindow(id));
    }

    if (w.isMinimised) {
      windows[id] = w.copyWith(
        displayState: WindowDisplayState.normal,
        zOrder: _nextZ++,
      );
      notify();
      // The backend owns displayState and `sync` re-reads it on every rebuild,
      // which fps telemetry triggers constantly. Without this the facade stays
      // on `minimised`, the next snapshot clobbers the local restore, and the
      // window snaps shut again — the restore that looked instant and then
      // undid itself. `raiseAndFocus` always did this; the taskbar path did
      // not, which is why Alt-Tab restored and a dock click did not.
      unawaited(
        facade.setWindowDisplayState(id, WindowDisplayState.normal),
      );
    }
    facade.focusWindow(id);
  }

  /// Raises [id] locally without a round trip, for the start of a drag.
  void raiseLocally(String id) {
    final WorkspaceWindow? w = windows[id];
    if (w == null) return;
    windows[id] = w.copyWith(zOrder: _nextZ++);
  }

  void queueMove(String id, WindowGeometry g) {
    _pendingMoves[id] = g;
    _moveFlush ??= Timer(_moveThrottle, flushMoves);
  }

  void flushMoves() {
    _moveFlush = null;
    if (_pendingMoves.isEmpty) return;
    final Map<String, WindowGeometry> sending =
        Map<String, WindowGeometry>.from(_pendingMoves);
    _pendingMoves.clear();
    for (final MapEntry<String, WindowGeometry> e in sending.entries) {
      rememberGeometry(e.key);
      unawaited(
        facade.moveWindow(e.key, e.value).then((_) {
          // Authority goes back to the backend only once it has the position.
          if (isMounted() && dragging == e.key && _pendingMoves.isEmpty) {
            dragging = null;
            notify();
          }
        }),
      );
    }
  }

  /// Remembers where a window was left, so relaunching reopens it there.
  ///
  /// Called on commit rather than continuously: [queueMove] already coalesces a
  /// drag, and recording per pointer sample would write the settings file dozens
  /// of times per second.
  void rememberGeometry(String id) {
    final WorkspaceWindow? w = windows[id];
    if (w == null) return;
    onRememberedChanged(
      rememberWindow(
        rememberedWindows(),
        w.session.application.packageName,
        w.geometry,
        maximised: w.displayState == WindowDisplayState.maximised,
      ),
    );
  }

  /// Applies a display-state change locally and sends it on.
  void setDisplayState(String id, WindowDisplayState state) {
    final WorkspaceWindow? w = windows[id];
    if (w != null) {
      windows[id] = w.copyWith(displayState: state);
      notify();
    }
    // Maximised is part of the placement, so a change to it is worth
    // remembering as much as a move is. Minimised is not: a window you come
    // back to should not reopen hidden.
    if (state != WindowDisplayState.minimised) rememberGeometry(id);
    unawaited(facade.setWindowDisplayState(id, state));
  }

  /// Whether the backend has actually positioned this window, or is still
  /// reporting the default it gives every new session.
  static bool _isUnplaced(WindowGeometry g) =>
      g.x == 64 && g.y == 64 && g.width == 640 && g.height == 480;

  /// Runs [action] after the current frame.
  ///
  /// Deferred on purpose: [sync] runs during build, and a facade command can
  /// emit a new snapshot synchronously — which re-enters build and throws
  /// "setState called during build".
  void _afterFrame(Future<void> Function() action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isMounted()) unawaited(action());
    });
  }
}
