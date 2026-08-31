import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_drawer.dart';
import '../boot/boot_screen.dart';
import '../desk/desk.dart';
import '../diagnostics/stream_diagnostics.dart';
import '../theme/dex_colors.dart';
import '../connect/connection_screen.dart';
import '../permissions/permission_panel.dart';
import '../motion/sustained.dart';
import '../recovery/recovery_overlay.dart';
import '../settings/desk_settings.dart';
import '../theme/dex_tokens.dart';
import '../theme/wallpapers.dart';
import '../workspace/app_window.dart';
import '../workspace/window_input.dart';
import '../workspace/window_switcher.dart';
import '../workspace/window_model.dart';
import '../workspace/workspace.dart';

/// The whole product, composed.
///
/// One widget so the bootstrap only has to inject a facade and a snapshot:
/// which surface is showing, what stacks over what, and how the bottom edge is
/// assembled are UI decisions and belong here rather than in `main.dart`.
///
/// Layout, once the link is up:
///
///     ┌───────────────────────────────────────────┐
///     │  workspace / drawer          │ side panel  │
///     │                                             │
///     │            [ floating dock ]                │
///     └───────────────────────────────────────────┘
///
/// Streamed apps are external OS windows owned by scrcpy, so the workspace is
/// deliberately empty: this app frames and drives those windows, it does not
/// draw them.
void _ignoreTheme(ThemeMode _) {}
void _ignoreBool(bool _) {}
void _ignoreInt(int _) {}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.snapshot,
    required this.facade,
    this.now,
    this.themeMode = ThemeMode.dark,
    this.onThemeChanged = _ignoreTheme,
    this.snapEnabled = true,
    this.onSnapChanged = _ignoreBool,
    this.wallpaperIndex = 0,
    this.onWallpaperChanged = _ignoreInt,
    super.key,
  });

  final OpenDexSnapshot snapshot;
  final OpenDexFacade facade;

  /// The app's theme mode and its setter.
  ///
  /// Owned by whoever builds the `MaterialApp` — the bootstrap in the product,
  /// the harness in tests — because the shell sits inside it and cannot change
  /// it from within.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  /// Window edge-snapping, and its setter. Lifted out of the shell so it can be
  /// persisted by whoever builds the app (see `DeskPreferences`).
  final bool snapEnabled;
  final ValueChanged<bool> onSnapChanged;

  /// The chosen desk wallpaper — 0 is the theme default, 1..N select
  /// [kWallpaperChoices] — and its setter. Persisted alongside the theme.
  final int wallpaperIndex;
  final ValueChanged<int> onWallpaperChanged;

  /// Fixed clock, for tests only.
  ///
  /// Null in the product: the shell then ticks its own clock. The snapshot
  /// stream cannot drive it, because a stream that only emits when device state
  /// changes will leave the desk showing the time the last event arrived — a
  /// clock that does not tick is broken, and it was.
  final DateTime? now;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Workspace state the contract does not carry yet.
  ///
  /// Held here only until `OpenDexFacade` publishes workspace state itself
  /// (see `docs/ARCHITECTURE.md` for the facade boundary). When it does, this
  /// map disappears and the values come from the snapshot — the widgets below
  /// already read it as if it were remote, so the swap is mechanical.
  final Map<String, WorkspaceWindow> _workspace = <String, WorkspaceWindow>{};

  /// Windows already fitted to their video's aspect ratio (once, when the first
  /// frame revealed it). Kept so a person can freely resize afterwards.
  final Set<String> _aspectFitted = <String>{};

  /// The title-bar height the controller subtracts from the window when mapping
  /// it to a phone-display resolution. Kept in sync so a fitted window's
  /// *content* matches the video aspect exactly — no black bars.
  static const double _windowChrome = 34;
  int _nextZ = 1;

  bool _settingsOpen = false;
  bool _drawerOpen = false;

  /// The window shown edge-to-edge with no desk, taskbar, or title bar, or null
  /// when nothing is fullscreen. F11 toggles it for the focused window; Escape
  /// leaves it.
  String? _fullscreenId;
  bool _permissionsOpen = false;

  /// The one connection surface. It used to be two — a phone list with a
  /// pairing dialog stacked over it — which meant Escape peeled layers and the
  /// way to *get* a phone was hidden behind the question of which one to use.
  bool _connectOpen = false;
  String? _selectedDeviceId;

  OpenDexSnapshot get _s => widget.snapshot;

  bool get _recovering =>
      _s.recovery.phase != RecoveryPhase.idle &&
      _s.recovery.phase != RecoveryPhase.recovered;

  Timer? _clock;
  DateTime _tick = DateTime.now();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    if (widget.now == null) {
      // Every 10 s: the clock shows minutes, so a minute-long timer would drift
      // visibly against the real one, and a second-long timer would rebuild the
      // desk sixty times a minute for nothing.
      _clock = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          setState(() => _tick = DateTime.now());
        }
      });
    }
  }

  /// Attempts spent. Auto-connect stops after [_autoConnectLimit] so a phone
  /// that genuinely cannot connect does not retry forever.
  int _autoConnectAttempts = 0;
  static const int _autoConnectLimit = 3;

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
  ///
  /// Every route into a live session sets it at the moment of the action rather
  /// than by observing a snapshot, because two backend emissions inside one
  /// frame coalesce into a single build: the shell can go from "connecting" to
  /// "disconnected" without ever rendering the ready state in between. Watching
  /// for [BootPhase.ready] alone would miss it exactly then.
  bool _autoConnectDone = false;

  /// Guards against a second attempt starting while one is in flight, since
  /// this is driven from `build` and several frames can pass before the first
  /// command resolves.
  bool _autoConnectInFlight = false;

  /// Long enough that a retry is not a busy loop, short enough that a person
  /// watching the boot screen does not conclude it has hung.
  static const Duration _autoConnectBackoff = Duration(seconds: 1);
  Timer? _autoConnectRetry;

  /// Connects on its own when there is exactly one authorised phone.
  ///
  /// The backend auto-*selects* that phone but never connects, so the product
  /// used to open on a boot screen with a single button, which reads as a
  /// connection failure. When to issue `connect` is a product decision, not an
  /// implementation detail: connecting is a decision, not a reflex, so the
  /// automatic case is confined to the one situation with no question in it.
  ///
  /// Deliberately narrow. Zero devices, several devices, or an unauthorised
  /// one all still require a choice, because in those cases there is a real
  /// question only the person can answer.
  ///
  /// It also only ever runs once per shell, before any session exists. See
  /// [_autoConnectDone] for why a disconnect must not be allowed to restart it.
  void _maybeAutoConnect() {
    if (_autoConnectDone || _autoConnectInFlight) return;
    if (_s.boot.isReady) {
      // Connected by any route — this one, or the person choosing a phone.
      _autoConnectDone = true;
      return;
    }
    if (_autoConnectAttempts >= _autoConnectLimit) return;
    if (_s.deviceStatus != LoadStatus.ready) return;
    final List<DeviceSummary> authorised = _s.devices
        .where((DeviceSummary d) => d.status == DeviceStatus.authorized)
        .toList();
    if (authorised.length != 1) return;

    _autoConnectAttempts++;
    _autoConnectInFlight = true;
    // After the frame: this runs from build, and a facade command can emit a
    // new snapshot synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool connected = false;
      try {
        if (!mounted) return;
        final VoidResult selected = await widget.facade.selectDevice(
          authorised.single.id,
        );
        // Connecting after a failed select would act on whatever was selected
        // before, which could be nothing or the wrong phone.
        if (!mounted || selected is! CommandSuccess) return;
        connected =
            await widget.facade.connectSelectedDevice() is CommandSuccess;
      } finally {
        // Order matters, and every exit path runs through here. The retry is
        // scheduled only after the in-flight flag is cleared, or the timer
        // would find the guard still closed and do nothing. Scheduling inside
        // the `try` also missed the early returns entirely — a failed
        // `selectDevice` scheduled nothing at all and spent an attempt.
        _autoConnectInFlight = false;
        if (connected) {
          _autoConnectDone = true;
        } else {
          _scheduleAutoConnectRetry();
        }
      }
    });
  }

  /// Re-runs the check after a pause.
  ///
  /// `_maybeAutoConnect` is driven from `build`, so without this a retry
  /// depends on some unrelated snapshot happening to arrive and rebuild the
  /// shell. On a phone that failed to connect there may be no such snapshot,
  /// and waiting for one is how a person ends up staring at a boot screen.
  void _scheduleAutoConnectRetry() {
    if (_autoConnectDone || _autoConnectAttempts >= _autoConnectLimit) return;
    _moveFlush?.cancel();
    _autoConnectRetry?.cancel();
    _autoConnectRetry = Timer(_autoConnectBackoff, () {
      if (mounted) setState(() {});
    });
  }

  /// The time the desk should display.
  DateTime get _now => widget.now ?? _tick;

  static String _clockLabel(DateTime at) {
    final int h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '$h:${at.minute.toString().padLeft(2, '0')}';
  }

  /// Reconciles the local workspace with the sessions the backend reports.
  ///
  /// The backend owns window state now: `moveWindow`, `raiseWindow` and
  /// `setWindowDisplayState` all update the session it publishes back. So every
  /// field is taken from the session on each rebuild rather than kept locally.
  ///
  /// This used to copy geometry, z-order and surface **once**, at creation.
  /// That was wrong in a way that mattered: a window's texture arrives some
  /// milliseconds after the session does, so the shell captured `null` and
  /// never looked again — the embedded stream would never have appeared no
  /// matter how correct the backend was.
  ///
  /// The one exception is a window being dragged. Its geometry stays local
  /// until the drag ends, so the frame tracks the pointer instead of waiting
  /// for a round trip and stuttering against stale echoes.
  List<WorkspaceWindow> _windows(BuildContext context) {
    final Size approx = MediaQuery.sizeOf(context);

    for (final WindowSessionState session in _s.windows) {
      final WorkspaceWindow? existing = _workspace[session.id];
      final bool dragging = _dragging == session.id;

      if (existing == null) {
        // A brand-new window has whatever geometry the backend defaults to,
        // which is the same for every window — so two opened in a row would
        // land exactly on top of each other. Cascade it and tell the backend,
        // which then echoes our position back as the authoritative one.
        final WindowGeometry placed = _isUnplaced(session.geometry)
            ? cascadeGeometry(_workspace.length, approx)
            : session.geometry;
        _workspace[session.id] = WorkspaceWindow(
          session: session,
          geometry: placed,
          zOrder: session.zOrder,
          displayState: session.displayState,
          surface: session.surface,
          presentedFramesPerSecond: session.presentedFramesPerSecond,
        );
        if (placed != session.geometry) {
          // Deferred to after the frame on purpose. `_windows` runs during
          // build, and a facade command can emit a new snapshot synchronously —
          // which re-enters build and throws "setState called during build".
          final WindowGeometry send = placed;
          final String id = session.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(widget.facade.moveWindow(id, send));
          });
        }
      } else {
        _workspace[session.id] = existing.copyWith(
          session: session,
          geometry: dragging ? existing.geometry : session.geometry,
          zOrder: session.zOrder,
          displayState: session.displayState,
          surface: session.surface,
          presentedFramesPerSecond: session.presentedFramesPerSecond,
        );
      }
    }

    // Once a window's first frame reveals the app's aspect ratio, size the
    // window to it (once). A portrait app then opens in a portrait window and
    // the phone display stays portrait, instead of the default landscape window
    // resizing the display wide and greying the app out. Skipped while dragging
    // or once the person has been given the chance to resize.
    for (final WindowSessionState session in _s.windows) {
      final String id = session.id;
      final WorkspaceWindow? w = _workspace[id];
      if (w == null || _aspectFitted.contains(id) || _dragging == id) continue;
      final WindowSurface? surface = w.surface;
      if (surface == null ||
          surface.pixelSize.width <= 0 ||
          surface.pixelSize.height <= 0) {
        continue;
      }
      _aspectFitted.add(id);
      if (w.displayState != WindowDisplayState.normal) continue;
      final WindowGeometry fitted = _fitToSurface(surface, approx, w.geometry);
      if ((fitted.width - w.geometry.width).abs() < 1 &&
          (fitted.height - w.geometry.height).abs() < 1) {
        continue;
      }
      _workspace[id] = w.copyWith(geometry: fitted);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.facade.moveWindow(id, fitted));
      });
    }
    for (final MapEntry<String, WorkspaceWindow> entry in _workspace.entries) {
      if (_s.windows.any((WindowSessionState w) => w.id == entry.key)) continue;
      final WorkspaceWindow gone = entry.value;
      final String reason =
          gone.session.error?.message ??
          (gone.session.status == WindowSessionStatus.failed
              ? 'stopped unexpectedly'
              : 'closed');
      _recentExits.insert(
        0,
        '${_clockLabel(_now)}  ${gone.session.application.label} — $reason',
      );
      if (_recentExits.length > _recentExitsKept) _recentExits.removeLast();
    }
    _workspace.removeWhere(
      (String id, _) => !_s.windows.any((WindowSessionState w) => w.id == id),
    );
    return _workspace.values.toList();
  }

  /// Alt+Tab: focus the next window and raise it.
  ///
  /// Cycles in z-order rather than creation order, which is what makes repeated
  /// presses feel like "the window behind this one" instead of an arbitrary
  /// list. Minimised windows are skipped — Alt+Tab to something invisible would
  /// look like nothing happened.
  /// Windows Alt+Tab can reach, most recently used first.
  List<WorkspaceWindow> get _switchable =>
      _workspace.values
          .where(
            (WorkspaceWindow w) =>
                w.session.status != WindowSessionStatus.closed,
          )
          .toList()
        ..sort(
          (WorkspaceWindow a, WorkspaceWindow b) =>
              b.zOrder.compareTo(a.zOrder),
        );

  /// Advances the Alt+Tab selection, opening the switcher on the first press.
  ///
  /// This used to swap focus silently on every press. With two windows that
  /// reads as a glitch; with four it is unusable, because nothing says where
  /// you are in the list. Selection is now committed when Alt is released,
  /// which is what every desktop does.
  void _cycleFocus() {
    final List<WorkspaceWindow> open = _switchable;
    if (open.length < 2) {
      return;
    }
    setState(() {
      // First press lands on the window beneath the current one, not on the
      // one already focused — otherwise a quick Alt+Tab does nothing.
      _switcherIndex = _switcherOpen ? (_switcherIndex + 1) % open.length : 1;
      _switcherOpen = true;
    });
  }

  /// Alt released: commit whatever the switcher landed on.
  void _commitSwitch() {
    if (!_switcherOpen) return;
    final List<WorkspaceWindow> open = _switchable;
    final WorkspaceWindow? next = _switcherIndex < open.length
        ? open[_switcherIndex]
        : null;
    setState(() => _switcherOpen = false);
    if (next != null) _raiseAndFocus(next.id);
  }

  void _raiseAndFocus(String id) {
    final WorkspaceWindow? w = _workspace[id];
    if (w == null) return;
    if (w.isMinimised) {
      setState(() {
        _workspace[id] = w.copyWith(displayState: WindowDisplayState.normal);
      });
      unawaited(
        widget.facade.setWindowDisplayState(id, WindowDisplayState.normal),
      );
    }
    setState(() {
      _workspace[id] = _workspace[id]!.copyWith(zOrder: _nextZ++);
    });
    unawaited(widget.facade.raiseWindow(id));
    widget.facade.focusWindow(id);
  }

  /// Dock click. A minimised window is restored first: focusing a window that
  /// is not on screen changes nothing the person can see, which is exactly how
  /// the minimise/restore round trip was broken.
  void _focusOrRestore(String id) {
    final WorkspaceWindow? w = _workspace[id];
    if (w != null && w.isMinimised) {
      setState(() {
        _workspace[id] = w.copyWith(
          displayState: WindowDisplayState.normal,
          zOrder: _nextZ++,
        );
      });
      // The backend owns displayState and `_windows` re-reads it on every
      // rebuild, which fps telemetry triggers constantly. Without this the
      // facade stays on `minimised`, the next snapshot clobbers the local
      // restore, and the window snaps shut again — the restore that looked
      // instant and then undid itself. `_raiseAndFocus` always did this; the
      // taskbar path did not, which is why Alt-Tab restored and a dock click
      // did not.
      unawaited(
        widget.facade.setWindowDisplayState(id, WindowDisplayState.normal),
      );
    }
    widget.facade.focusWindow(id);
  }

  /// Latest geometry not yet sent to the backend, and the timer that will
  /// send it.
  ///
  /// Trailing-edge on purpose: whatever the last geometry of a gesture is, it
  /// is always delivered, so no explicit drag-end signal is needed and a drag
  /// can never leave the backend holding a stale position.
  final Map<String, WindowGeometry> _pendingMoves = <String, WindowGeometry>{};
  Timer? _moveFlush;

  /// Roughly twelve updates a second. Far below pointer rate, far above what
  /// the backend needs to keep a window where the person put it.
  static const Duration _moveThrottle = Duration(milliseconds: 80);

  void _queueMove(String id, WindowGeometry g) {
    _pendingMoves[id] = g;
    _moveFlush ??= Timer(_moveThrottle, _flushMoves);
  }

  void _flushMoves() {
    _moveFlush = null;
    if (_pendingMoves.isEmpty) return;
    final Map<String, WindowGeometry> sending =
        Map<String, WindowGeometry>.from(_pendingMoves);
    _pendingMoves.clear();
    for (final MapEntry<String, WindowGeometry> e in sending.entries) {
      unawaited(
        widget.facade.moveWindow(e.key, e.value).then((_) {
          // Authority goes back to the backend only once it has the position.
          if (mounted && _dragging == e.key && _pendingMoves.isEmpty) {
            setState(() => _dragging = null);
          }
        }),
      );
    }
  }

  /// The window currently being dragged, if any. While a drag is in flight the
  /// backend's echo of that window's geometry is ignored.
  String? _dragging;

  bool _diagnosticsOpen = false;

  /// One line per window that has gone away, most recent first.
  ///
  /// A closed or failed window leaves the snapshot entirely, so by the time
  /// someone asks "where did it go?" there is nothing left to inspect. This is
  /// the only place that answer survives.
  final List<String> _recentExits = <String>[];
  static const int _recentExitsKept = 8;

  /// Alt+Tab switcher state. Open only while Alt is held.
  bool _switcherOpen = false;
  int _switcherIndex = 0;

  /// Whether the backend has actually positioned this window, or is still
  /// reporting the default it gives every new session.
  static bool _isUnplaced(WindowGeometry g) =>
      g.x == 64 && g.y == 64 && g.width == 640 && g.height == 480;

  /// A window geometry whose *content* (height minus the title bar) matches the
  /// video's aspect ratio, sized to ~85% of the work area and centred on the
  /// window's current centre. The surface then fills the window with no black
  /// bars, and the phone display the controller derives from the content keeps
  /// the app's own aspect (so a portrait app is never greyed onto a wide
  /// display).
  WindowGeometry _fitToSurface(
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

  WorkspaceIntents get _intents => WorkspaceIntents(
    fullscreen: _enterFullscreen,
    focus: (String id) => widget.facade.focusWindow(id),
    // Each of these does two things: update locally so the window answers the
    // pointer in the same frame, and tell the backend so the thing it owns —
    // the actual stream, and the external window while one still exists —
    // follows. Local-only was the old behaviour and it meant dragging a window
    // moved our chrome while the app stayed where it was.
    raise: (String id) {
      setState(() {
        final WorkspaceWindow? w = _workspace[id];
        if (w != null) {
          _workspace[id] = w.copyWith(zOrder: _nextZ++);
        }
      });
      unawaited(widget.facade.raiseWindow(id));
    },
    move: (String id, WindowGeometry g) {
      // Local first, every single event: this is what makes the frame track
      // the pointer.
      setState(() {
        _dragging = id;
        final WorkspaceWindow? w = _workspace[id];
        if (w != null) {
          _workspace[id] = w.copyWith(geometry: g);
        }
      });
      // The backend, however, is told on a throttle. Every `moveWindow` makes
      // the controller publish a snapshot, which rebuilds the whole shell —
      // desk, widgets, taskbar and every BackdropFilter behind them. At
      // pointer rate that was sixty to a hundred full-tree repaints a second
      // on top of a live video texture, which showed up as blinking while
      // dragging.
      _queueMove(id, g);
    },
    setDisplayState: (String id, WindowDisplayState state) {
      setState(() {
        final WorkspaceWindow? w = _workspace[id];
        if (w != null) {
          _workspace[id] = w.copyWith(displayState: state);
        }
      });
      unawaited(widget.facade.setWindowDisplayState(id, state));
    },
    close: (String id) => widget.facade.closeWindow(id),
    retry: (String id) => widget.facade.focusWindow(id),
    sendPointer: (String id, WindowPointerSample sample) =>
        unawaited(widget.facade.sendPointer(id, sample)),
  );

  @override
  void dispose() {
    _clock?.cancel();
    _moveFlush?.cancel();
    _autoConnectRetry?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// App-global accelerators.
  ///
  /// Deliberately not `Shortcuts`/`CallbackShortcuts`. Those require the focus
  /// to sit inside their subtree, and the route's ModalScope — an *ancestor*
  /// of this widget — holds primary focus, so key events bubble upward away
  /// from anything the shell could register. A keyboard handler is
  /// focus-independent, which is what an app-wide accelerator needs to be.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      if (event is KeyUpEvent &&
          (event.logicalKey == LogicalKeyboardKey.altLeft ||
              event.logicalKey == LogicalKeyboardKey.altRight) &&
          _switcherOpen) {
        _commitSwitch();
        return true;
      }
      // Key *up* still has to reach a focused Android app, or it sees a key
      // held down forever. Accelerators only ever fire on down.
      return _forwardKeyToWindow(event);
    }
    final bool control = HardwareKeyboard.instance.isControlPressed;
    if (control &&
        HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      setState(() => _diagnosticsOpen = !_diagnosticsOpen);
      return true;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.space) {
      _toggleDrawer();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    if (HardwareKeyboard.instance.isAltPressed &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      _cycleFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Fullscreen is the most immersive layer, so Escape leaves it first.
      if (_fullscreenId != null) {
        _exitFullscreen();
        return true;
      }
      if (_diagnosticsOpen) {
        setState(() => _diagnosticsOpen = false);
        return true;
      }
      if (_switcherOpen) {
        // Cancels the switch rather than committing it, which is the whole
        // reason a person reaches for Escape mid-Alt+Tab.
        setState(() => _switcherOpen = false);
        return true;
      }
      if (_drawerOpen || _permissionsOpen || _settingsOpen) {
        setState(() {
          _drawerOpen = false;
          _permissionsOpen = false;
          _settingsOpen = false;
        });
        return true;
      }
      // One layer, so one Escape. Closing it also stops discovery and cancels
      // any pairing — see [ConnectionScreen.dispose].
      if (_connectOpen) {
        setState(() => _connectOpen = false);
        return true;
      }
    }
    // Nothing above claimed it, so it belongs to the app the person is
    // actually typing into.
    return _forwardKeyToWindow(event);
  }

  /// Sends a key to the focused Android window, if one should have it.
  ///
  /// Returns whether the event was consumed. The guards matter more than the
  /// send does: forwarding indiscriminately would swallow every keystroke the
  /// desk's own text fields need, so the search box in the drawer would stop
  /// accepting letters the moment an app window existed.
  bool _forwardKeyToWindow(KeyEvent event) {
    // Any desk surface that is open owns the keyboard.
    if (_drawerOpen || _settingsOpen || _permissionsOpen || _connectOpen) {
      return false;
    }
    // A focused text field anywhere in our own chrome owns it too.
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText) return false;

    final WorkspaceWindow? target = _workspace.values
        .cast<WorkspaceWindow?>()
        .firstWhere(
          (WorkspaceWindow? w) =>
              w != null &&
              w.isFocused &&
              !w.isMinimised &&
              w.surface != null &&
              w.session.status == WindowSessionStatus.streaming,
          orElse: () => null,
        );
    if (target == null) return false;

    final WindowKeySample? sample = windowKeySample(event);
    if (sample == null) return false;
    unawaited(widget.facade.sendKey(target.id, sample));
    return true;
  }

  void _toggleDrawer() {
    setState(() {
      _drawerOpen = !_drawerOpen;
      if (_drawerOpen) {
        _permissionsOpen = false;
      }
    });
  }

  /// Opens a URL in the desktop's default browser, for the desk search bars.
  ///
  /// `xdg-open` is the portable Linux "open this with whatever handles it" —
  /// no `url_launcher` dependency for a single call. Failures are swallowed:
  /// a missing browser must not crash the desk.
  Future<void> _openUrl(String url) async {
    try {
      await Process.start('xdg-open', <String>[
        url,
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      // No handler for the scheme; nothing sensible to do from the desk.
    }
  }

  /// Enters or leaves edge-to-edge fullscreen for the focused streaming window.
  ///
  /// Fullscreen shows only that window's video, filling the whole monitor with
  /// no desk, taskbar, or title bar. Requires a window that is actually
  /// streaming — there is nothing to show fullscreen otherwise.
  void _toggleFullscreen() {
    if (_fullscreenId != null) {
      _exitFullscreen();
      return;
    }
    final WorkspaceWindow? target = _workspace.values
        .cast<WorkspaceWindow?>()
        .firstWhere(
          (WorkspaceWindow? w) =>
              w != null &&
              w.isFocused &&
              !w.isMinimised &&
              w.surface != null &&
              w.session.status == WindowSessionStatus.streaming,
          orElse: () => null,
        );
    if (target == null) return;
    setState(() {
      _fullscreenId = target.id;
      _drawerOpen = false;
      _settingsOpen = false;
      _diagnosticsOpen = false;
    });
    widget.facade.focusWindow(target.id);
  }

  void _exitFullscreen() {
    if (_fullscreenId == null) return;
    setState(() => _fullscreenId = null);
  }

  /// Routes a nav-pill key to the focused streaming window's display. No-op
  /// when nothing is focused — the pill is disabled in that state anyway.
  void _sendNavKey(AndroidNavKey key) {
    final WorkspaceWindow? target = _workspace.values
        .cast<WorkspaceWindow?>()
        .firstWhere(
          (WorkspaceWindow? w) =>
              w != null &&
              w.isFocused &&
              !w.isMinimised &&
              w.surface != null &&
              w.session.status == WindowSessionStatus.streaming,
          orElse: () => null,
        );
    if (target == null) return;
    unawaited(widget.facade.sendNavKey(target.id, key));
  }

  /// Enters edge-to-edge fullscreen for a specific window — the title bar's
  /// expand (↗) button. Only a streaming window can be shown; a window still
  /// starting has nothing to fill the monitor with.
  void _enterFullscreen(String id) {
    final WorkspaceWindow? w = _workspace[id];
    if (w == null ||
        w.surface == null ||
        w.session.status != WindowSessionStatus.streaming) {
      return;
    }
    setState(() {
      _fullscreenId = id;
      _drawerOpen = false;
      _settingsOpen = false;
      _diagnosticsOpen = false;
    });
    widget.facade.focusWindow(id);
  }

  /// The window currently shown fullscreen, or null if it has closed or stopped
  /// streaming — in which case fullscreen must fall away rather than hold a dead
  /// black screen.
  WorkspaceWindow? get _fullscreenWindow {
    final String? id = _fullscreenId;
    if (id == null) return null;
    final WorkspaceWindow? w = _workspace[id];
    if (w == null ||
        w.surface == null ||
        w.session.status != WindowSessionStatus.streaming) {
      return null;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    // One Material at the root of the product.
    //
    // Ink-based widgets need a Material ancestor, and surfaces that are stacked
    // rather than pushed as routes do not get one for free. Providing it here
    // once means no surface has to remember to bring its own — a fault that has
    // already bitten three separate widgets in this codebase.
    // WallpaperScope carries the chosen desk wallpaper down to every
    // DeskWallpaper — the desk, the launcher, the boot ground — so one setting
    // repaints them all. Index 0 is "Default": pass null so each theme keeps its
    // own wallpaper (forcing a fixed gradient here would paint the light theme
    // with a dark one). Only an explicit pick, 1 and up, overrides.
    return WallpaperScope(
      colors: widget.wallpaperIndex <= 0
          ? null
          : kWallpaperChoices[(widget.wallpaperIndex - 1).clamp(
                  0,
                  kWallpaperChoices.length - 1,
                )]
                .colors,
      child: Material(color: Colors.transparent, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    _maybeAutoConnect();
    // Before the link is up the boot screen is the whole window: there is
    // nothing else to do until it finishes.
    if (!_s.boot.isReady) {
      return Stack(
        children: <Widget>[
          BootScreen(
            boot: _s.boot,
            onConnect: () => setState(() => _connectOpen = true),
            onRetry: () {
              // The person is driving now, so auto-connect stands down for
              // good — including after a later disconnect returns us here.
              _autoConnectDone = true;
              widget.facade.retryBoot();
            },
          ),
          if (_connectOpen) _connectionScreen(),
        ],
      );
    }

    return Stack(
      children: <Widget>[
        _main(),
        ?_overlay(),
        // Edge-to-edge fullscreen: only the phone's video, filling the monitor,
        // above the desk and the launcher but below recovery — a dropped link
        // still takes over the screen. Falls away on its own if the window
        // closes or stops streaming (see [_fullscreenWindow]).
        if (_fullscreenWindow case final WorkspaceWindow w)
          Positioned.fill(
            child: WindowStage(window: w, intents: _intents),
          ),
        // Recovery covers everything: nothing else is usable while the link is
        // down, and pretending otherwise would invite dead clicks.
        // Held back rather than toggled on the raw phase. This overlay covers
        // the whole desk at 92% opacity, and it was appearing and vanishing
        // the instant `recovery.phase` moved — so a transport that dips in and
        // out of recovery flashed the entire screen. That is the blinking, from
        // the UI side.
        Sustained(
          visible: _recovering,
          child: RecoveryOverlay(
            recovery: _s.recovery,
            onReconnect: () => widget.facade.reconnect(),
            onDisconnect: () => widget.facade.disconnect(),
          ),
        ),
        if (_connectOpen) _connectionScreen(),
        // Above the dialogs: Alt+Tab is held down, so it is the most immediate
        // thing on screen for as long as it is up.
        if (_switcherOpen) _switcher(),
        if (_diagnosticsOpen)
          StreamDiagnostics(
            snapshot: _s,
            recentExits: _recentExits,
            onClose: () => setState(() => _diagnosticsOpen = false),
          ),
      ],
    );
  }

  Widget _switcher() {
    final List<WorkspaceWindow> open = _switchable;
    return WindowSwitcher(
      windows: open,
      selected: _switcherIndex.clamp(0, open.isEmpty ? 0 : open.length - 1),
      onPick: (String id) {
        setState(() => _switcherOpen = false);
        _raiseAndFocus(id);
      },
      onDismiss: () => setState(() => _switcherOpen = false),
    );
  }

  /// The desk is always the ground: overlays stack over it rather than
  /// replacing it, which is what makes opening the launcher feel like staying
  /// in the same place.
  Widget _main() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Desk(
            snapshot: _s,
            now: _now,
            onOpenLauncher: _toggleDrawer,
            onWebSearch: _openUrl,
            onMediaAction: widget.facade.sendMediaAction,
            onFocusWindow: _focusOrRestore,
            onCloseWindow: widget.facade.closeWindow,
            onOpenSettings: () => setState(() {
              _settingsOpen = true;
              _drawerOpen = false;
            }),
            onToggleFullscreen: _toggleFullscreen,
            fullscreenActive: _fullscreenId != null,
            onNavKey: _sendNavKey,
            onToggleControl: widget.facade.setDeviceControl,
            onToggleClipboardSync: widget.facade.setClipboardSync,
            onSetVolume: widget.facade.setVolume,
            onOpenPermissions: () => setState(() {
              _permissionsOpen = true;
              _drawerOpen = false;
            }),
            onDismissNotification: (String id) async {
              await widget.facade.dismissNotification(id);
            },
            onActivateNotification: (String id) async {
              await widget.facade.activateNotification(id);
            },
            onDismissAllNotifications: () async {
              await widget.facade.dismissAllNotifications();
            },
            onLaunchApplication: (AndroidApplication app) =>
                widget.facade.launchApplication(app.packageName),
            // The desk hosts the compositor rather than being its
            // background, so the taskbar can paint above app windows and
            // reserve the work area from them.
            workspace: Workspace(
              windows: _windows(context),
              intents: _intents,
              snapEnabled: widget.snapEnabled,
              // The desk is already behind it; a second ground here would
              // paint over the wallpaper, the icons and the widgets.
              emptyChild: const SizedBox.shrink(),
            ),
            windows: _windows(context),
            minimisedWindows: _workspace.values
                .where((WorkspaceWindow w) => w.isMinimised)
                .map((WorkspaceWindow w) => w.id)
                .toSet(),
            // Live self-ticking clock in the product; tests pass a fixed `now`.
            liveClock: widget.now == null,
          ),
        ),
      ],
    );
  }

  Widget? _overlay() {
    if (_drawerOpen) {
      // The drawer is full-bleed: it paints its own blurred scrim and centres
      // its icons, so it is not wrapped in the settings card.
      return AppDrawer(
        status: _s.applicationStatus,
        applications: _s.applications,
        onLaunch: (String pkg) {
          widget.facade.launchApplication(pkg);
          // Launching returns you to the desk; the window opens beside it.
          setState(() => _drawerOpen = false);
        },
        onRefresh: () => widget.facade.discoverDevices(),
        onDismiss: () => setState(() => _drawerOpen = false),
      );
    }
    if (_settingsOpen) {
      return _Overlay(
        onDismiss: () => setState(() => _settingsOpen = false),
        child: DeskSettings(
          snapEnabled: widget.snapEnabled,
          onSnapChanged: widget.onSnapChanged,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
          wallpaperIndex: widget.wallpaperIndex,
          onWallpaperChanged: widget.onWallpaperChanged,
          deviceLabel: _s.selectedDevice?.name,
          onManagePhones: () => setState(() {
            _settingsOpen = false;
            _connectOpen = true;
          }),
          onOpenPermissions: () => setState(() {
            _settingsOpen = false;
            _permissionsOpen = true;
          }),
          onDisconnect: () {
            setState(() => _settingsOpen = false);
            widget.facade.disconnect();
          },
        ),
      );
    }
    if (_permissionsOpen) {
      return _Overlay(
        onDismiss: () => setState(() => _permissionsOpen = false),
        child: PermissionPanel(
          permissions: _s.permissions,
          // Notifications only. `openPermissionSettings` is verified against a
          // real device for that capability alone; offering it for the others
          // would be a button that fails after it is pressed.
          // Notifications only. `openPermissionSettings` is verified against a
          // real device for that capability alone; returning null for the rest
          // leaves those rows saying what to do on the phone, instead of
          // offering a button that fails after it is pressed.
          onOpenSettings: (String capability) => capability == 'notifications'
              ? () =>
                    unawaited(widget.facade.openPermissionSettings(capability))
              : null,
        ),
      );
    }
    return null;
  }

  /// Choosing a phone and adding one, on the same surface.
  ///
  /// Opening it starts Wi-Fi discovery and closing it stops discovery and
  /// cancels any pairing; both happen inside [ConnectionScreen] itself, so
  /// every route in and out — the boot screen, Settings, Escape, the Close
  /// button — is covered by the widget's own lifecycle rather than by the
  /// shell remembering to pair the calls.
  Widget _connectionScreen() {
    return Material(
      color: Colors.black54,
      child: Center(
        child: ConnectionScreen.forFacade(
          facade: widget.facade,
          snapshot: _s,
          selectedId: _selectedDeviceId ?? _s.selectedDevice?.id,
          onSelect: (String id) => setState(() => _selectedDeviceId = id),
          onRefreshDevices: () => widget.facade.discoverDevices(),
          onClose: () => setState(() => _connectOpen = false),
          onConnectSelected: () {
            final String? id = _selectedDeviceId ?? _s.selectedDevice?.id;
            if (id != null) {
              // The person picked this phone themselves. From here on the
              // choice is theirs, so auto-connect never runs again — see
              // [_autoConnectDone].
              _autoConnectDone = true;
              _autoConnectRetry?.cancel();
              widget.facade.selectDevice(id);
              widget.facade.connectSelectedDevice();
            }
            setState(() => _connectOpen = false);
          },
        ),
      ),
    );
  }
}

/// An overlay over the desk.
///
/// [floating] presents the child as a window sitting on the desk rather than
/// replacing it — the One UI 8 launcher behaviour, and the reason it feels like
/// a desktop: the desk stays visible behind, so opening the launcher is not a
/// change of place.
///
/// Escape and a click on the scrim both dismiss it, because a surface you
/// cannot leave is a trap.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget body = Stack(
      children: <Widget>[
        // Scrim: blurs and darkens the desk behind, dismisses on tap, and drops
        // the desk back so the drawer reads as floating in front of it. The
        // blur is what makes opening the launcher feel like frosted glass over
        // the desktop rather than a flat panel dropped on top. Safe over a live
        // stream now that the desk-icon re-decode flicker is fixed — this is a
        // single deliberate, momentary filter, not the dozens of always-on desk
        // panels that were mistaken for the cause earlier.
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(DexSpace.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.bg.withValues(alpha: isDark ? 0.92 : 0.96),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: DexStroke.hairline,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onDismiss();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: body),
      ),
    );
  }
}
