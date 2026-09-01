import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_drawer.dart';
import '../apps/app_ranking.dart';
import '../boot/boot_screen.dart';
import '../boot/first_run_tour.dart';
import '../desk/desk.dart';
import '../diagnostics/diagnostics_report.dart';
import '../diagnostics/stream_diagnostics.dart';
import 'command_palette.dart';
import 'commands.dart';
import 'connection_controller.dart';
import 'shortcut_sheet.dart';
import 'window_controller.dart';
import 'shortcuts.dart';
import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../connect/connection_screen.dart';
import '../permissions/permission_panel.dart';
import '../motion/sustained.dart';
import '../recovery/recovery_overlay.dart';
import '../settings/desk_settings.dart';
import '../theme/dex_tokens.dart';
import '../util/app_version.dart';
import '../theme/glass.dart';
import '../theme/wallpapers.dart';
import '../workspace/app_window.dart';
import '../workspace/window_input.dart';
import '../workspace/window_switcher.dart';
import '../workspace/window_geometry_store.dart';
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
void _ignoreHistory(Map<String, AppLaunchStats> _) {}
void _ignorePins(List<String> _) {}
void _ignoreVoid() {}
void _ignoreRemembered(Map<String, RememberedWindow> _) {}

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
    this.launchHistory = const <String, AppLaunchStats>{},
    this.onLaunchHistoryChanged = _ignoreHistory,
    this.pinnedPackages = const <String>[],
    this.onPinnedChanged = _ignorePins,
    this.accentIndex = 0,
    this.onAccentChanged = _ignoreInt,
    this.glassEnabled = true,
    this.onGlassChanged = _ignoreBool,
    this.reduceMotion = false,
    this.onReduceMotionChanged = _ignoreBool,
    this.onCopyText,
    this.tourCompleted = true,
    this.onTourCompleted = _ignoreVoid,
    this.rememberedWindows = const <String, RememberedWindow>{},
    this.onRememberedWindowsChanged = _ignoreRemembered,
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

  /// Launch counts and recency per package, and its setter. Lifted out of the
  /// shell exactly as [snapEnabled] is, because the file it persists to is
  /// owned by the bootstrap lane rather than by the UI.
  ///
  /// Empty by default, in which case drawer search ranks on match quality
  /// alone — the behaviour before any of this existed.
  final Map<String, AppLaunchStats> launchHistory;
  final ValueChanged<Map<String, AppLaunchStats>> onLaunchHistoryChanged;

  /// Packages pinned to the top of the drawer, in pin order, and its setter.
  /// Lifted for the same reason as [launchHistory].
  final List<String> pinnedPackages;
  final ValueChanged<List<String>> onPinnedChanged;

  /// Which accent tints links, focus rings and selected rows, and its setter.
  /// Applied to the theme by whoever builds the `MaterialApp`, as `themeMode`
  /// already is — the shell sits inside it and cannot change it from within.
  final int accentIndex;
  final ValueChanged<int> onAccentChanged;

  /// Whether panels frost what is behind them, and its setter.
  ///
  /// Off is the low-end-GPU and legibility path: a `BackdropFilter` is
  /// expensive, and heavy translucency is hard to read. Off removes the filter
  /// entirely rather than softening it.
  final bool glassEnabled;
  final ValueChanged<bool> onGlassChanged;

  /// Whether to cut motion beyond whatever the platform already asks for, and
  /// its setter. Can only ever reduce: see [DexMotion.enabled].
  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotionChanged;

  /// Puts text on the desktop clipboard, for the diagnostics report.
  ///
  /// Null where the host has not supplied one. `lib/ui` never touches the
  /// system clipboard itself — see `lib/bootstrap/desktop_clipboard_coordinator`
  /// — so without this the Copy diagnostics button is simply absent.
  final ValueChanged<String>? onCopyText;

  /// Whether the first-run tour has already been shown, and the setter that
  /// records it.
  ///
  /// Defaults to true so a harness never meets the tour by accident; the host
  /// passes the stored value, which starts false on a fresh install.
  final bool tourCompleted;
  final VoidCallback onTourCompleted;

  /// Where each application's window was last left, and its setter. Lifted for
  /// the same reason as [launchHistory].
  final Map<String, RememberedWindow> rememberedWindows;
  final ValueChanged<Map<String, RememberedWindow>> onRememberedWindowsChanged;

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
  /// Which windows exist and where they are. See `window_controller.dart`.
  late final WindowController _wm = WindowController(
    facade: widget.facade,
    notify: () {
      if (mounted) setState(() {});
    },
    isMounted: () => mounted,
    rememberedWindows: () => widget.rememberedWindows,
    onRememberedChanged: widget.onRememberedWindowsChanged,
  );

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

  /// When the shell connects a phone without being asked.
  /// See `connection_controller.dart`.
  late final ConnectionController _connection = ConnectionController(
    facade: widget.facade,
    notify: () {
      if (mounted) setState(() {});
    },
    isMounted: () => mounted,
  );

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
    return _wm.sync(
      sessions: _s.windows,
      workspaceSize: MediaQuery.sizeOf(context),
      onClosed: _logExit,
    );
  }

  /// Notes a window that has gone, for the diagnostics panel. The controller
  /// reports the closure; formatting it needs the clock, which lives here.
  void _logExit(WorkspaceWindow gone) {
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

  /// Alt+Tab: focus the next window and raise it.
  ///
  /// Cycles in z-order rather than creation order, which is what makes repeated
  /// presses feel like "the window behind this one" instead of an arbitrary
  /// list. Minimised windows are skipped — Alt+Tab to something invisible would
  /// look like nothing happened.
  /// Advances the Alt+Tab selection, opening the switcher on the first press.
  ///
  /// This used to swap focus silently on every press. With two windows that
  /// reads as a glitch; with four it is unusable, because nothing says where
  /// you are in the list. Selection is now committed when Alt is released,
  /// which is what every desktop does.
  /// The order Alt+Tab is walking, captured when the switcher opens.
  ///
  /// Frozen on purpose. `_cycleFocus`, the switcher widget and `_commitSwitch`
  /// each used to re-derive the list independently, while `_switcherIndex`
  /// pointed into it — so a snapshot arriving mid-hold could reorder the list
  /// under the highlight, and releasing Alt could focus a window the person
  /// never selected. The shell rebuilds on every telemetry snapshot, which
  /// during streaming is continuous.
  List<String> _switchOrder = const <String>[];

  /// The frozen order, resolved against the windows that still exist.
  List<WorkspaceWindow> get _switchList => <WorkspaceWindow>[
    for (final String id in _switchOrder)
      if (_wm.windows[id] case final WorkspaceWindow w) w,
  ];

  void _cycleFocus({bool backwards = false}) {
    if (!_switcherOpen) {
      final List<WorkspaceWindow> open = _wm.switchable;
      if (open.length < 2) return;
      setState(() {
        _switchOrder = <String>[
          for (final WorkspaceWindow w in open) w.id,
        ];
        // First press lands on the window beneath the current one, not on the
        // one already focused — otherwise a quick Alt+Tab does nothing.
        _switcherIndex = backwards ? _switchOrder.length - 1 : 1;
        _switcherOpen = true;
      });
      return;
    }

    final int count = _switchOrder.length;
    if (count < 2) return;
    setState(() {
      _switcherIndex = backwards
          ? (_switcherIndex - 1 + count) % count
          : (_switcherIndex + 1) % count;
    });
  }

  /// Alt released: commit whatever the switcher landed on.
  void _commitSwitch() {
    if (!_switcherOpen) return;
    // Committed against the frozen order, not a fresh sort.
    final List<WorkspaceWindow> open = _switchList;
    final WorkspaceWindow? next = _switcherIndex < open.length
        ? open[_switcherIndex]
        : null;
    setState(() {
      _switcherOpen = false;
      _switchOrder = const <String>[];
    });
    if (next != null) _wm.raiseAndFocus(next.id);
  }

  bool _diagnosticsOpen = false;

  /// The keyboard cheat sheet. Ctrl+/, F1, or a bare ? when nothing is typing.
  bool _sheetOpen = false;

  /// The command palette. Ctrl+Shift+P.
  bool _paletteOpen = false;

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

  WorkspaceIntents get _intents => WorkspaceIntents(
    fullscreen: _enterFullscreen,
    focus: (String id) => widget.facade.focusWindow(id),
    // Each of these does two things: update locally so the window answers the
    // pointer in the same frame, and tell the backend so the thing it owns —
    // the actual stream, and the external window while one still exists —
    // follows. Local-only was the old behaviour and it meant dragging a window
    // moved our chrome while the app stayed where it was.
    raise: (String id) {
      setState(() => _wm.raiseLocally(id));
      unawaited(widget.facade.raiseWindow(id));
    },
    move: (String id, WindowGeometry g) {
      // Local first, every single event: this is what makes the frame track
      // the pointer.
      setState(() {
        _wm.dragging = id;
        final WorkspaceWindow? w = _wm.windows[id];
        if (w != null) {
          _wm.windows[id] = w.copyWith(geometry: g);
        }
      });
      // The backend, however, is told on a throttle. Every `moveWindow` makes
      // the controller publish a snapshot, which rebuilds the whole shell —
      // desk, widgets, taskbar and every BackdropFilter behind them. At
      // pointer rate that was sixty to a hundred full-tree repaints a second
      // on top of a live video texture, which showed up as blinking while
      // dragging.
      _wm.queueMove(id, g);
    },
    setDisplayState: _wm.setDisplayState,
    close: (String id) => widget.facade.closeWindow(id),
    retry: (String id) => widget.facade.focusWindow(id),
    sendPointer: (String id, WindowPointerSample sample) =>
        unawaited(widget.facade.sendPointer(id, sample)),
  );

  @override
  void dispose() {
    _clock?.cancel();
    _wm.dispose();
    _connection.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Everything the palette can offer, assembled from live state.
  ///
  /// Rebuilt per open rather than cached, so a command can never outlive the
  /// thing it acts on — an app that was uninstalled or a window that closed is
  /// simply not in the list.
  List<DexCommand> get _commands => buildCommands(
    applications: _s.applications,
    windows: _s.windows,
    onLaunchApplication: (String pkg) {
      widget.facade.launchApplication(pkg);
      _recordLaunch(pkg);
    },
    onFocusWindow: _wm.raiseAndFocus,
    shellEntries: <DexCommandEntry>[
      DexCommandEntry(
        title: 'Open settings',
        keywords: const <String>['preferences', 'theme', 'accent'],
        run: () => setState(() => _settingsOpen = true),
      ),
      DexCommandEntry(
        title: 'Show keyboard shortcuts',
        keywords: const <String>['help', 'keys'],
        run: () => setState(() => _sheetOpen = true),
      ),
      DexCommandEntry(
        title: 'Toggle stream diagnostics',
        keywords: const <String>['fps', 'performance', 'debug'],
        run: () => setState(() => _diagnosticsOpen = !_diagnosticsOpen),
      ),
      DexCommandEntry(
        title: 'Open the app launcher',
        keywords: const <String>['apps', 'drawer'],
        run: _toggleDrawer,
      ),
      DexCommandEntry(
        title: 'Manage phones',
        keywords: const <String>['connect', 'pair', 'device'],
        run: () => setState(() => _connectOpen = true),
      ),
      DexCommandEntry(
        title: 'Permissions',
        keywords: const <String>['access', 'grant'],
        run: () => setState(() => _permissionsOpen = true),
      ),
    ],
  );

  /// The shell's half of the shortcut registry: what each accelerator asks
  /// about the shell, and what it does to it. The list itself, and its order,
  /// live in `shortcuts.dart`.
  ShellShortcutHooks get _shortcutHooks => ShellShortcutHooks(
    openPalette: () => setState(() => _paletteOpen = true),
    isPaletteOpen: () => _paletteOpen,
    closePalette: () => setState(() => _paletteOpen = false),
    openSheet: () => setState(() => _sheetOpen = true),
    isSheetOpen: () => _sheetOpen,
    closeSheet: () => setState(() => _sheetOpen = false),
    keyboardIsFree: () => !_deskOwnsKeyboard,
    toggleDiagnostics: () =>
        setState(() => _diagnosticsOpen = !_diagnosticsOpen),
    toggleDrawer: _toggleDrawer,
    toggleFullscreen: _toggleFullscreen,
    cycleFocus: _cycleFocus,
    cycleFocusBack: () => _cycleFocus(backwards: true),
    isFullscreen: () => _fullscreenId != null,
    exitFullscreen: _exitFullscreen,
    isDiagnosticsOpen: () => _diagnosticsOpen,
    closeDiagnostics: () => setState(() => _diagnosticsOpen = false),
    isSwitcherOpen: () => _switcherOpen,
    cancelSwitch: () => setState(() => _switcherOpen = false),
    isDeskSurfaceOpen: () => _drawerOpen || _permissionsOpen || _settingsOpen,
    closeDeskSurfaces: () => setState(() {
      _drawerOpen = false;
      _permissionsOpen = false;
      _settingsOpen = false;
    }),
    isConnectOpen: () => _connectOpen,
    closeConnect: () => setState(() => _connectOpen = false),
  );

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
    final HardwareKeyboard keys = HardwareKeyboard.instance;
    final DexShortcut? hit = matchShortcut(
      buildShortcuts(_shortcutHooks),
      event.logicalKey,
      control: keys.isControlPressed,
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
    );
    if (hit != null) {
      hit.run();
      return true;
    }
    // Nothing above claimed it, so it belongs to the app the person is
    // actually typing into.
    return _forwardKeyToWindow(event);
  }

  /// Whether the desk's own chrome should keep every plain keystroke.
  ///
  /// True while any desk surface is open, or while a text field anywhere in our
  /// chrome has focus. Two callers need exactly this question and must not
  /// drift apart: forwarding to the phone, and the bare `?` cheat-sheet
  /// binding. Without the second, typing a question mark into the launcher
  /// search would throw a help panel over what you were searching for.
  bool get _deskOwnsKeyboard {
    if (_drawerOpen ||
        _settingsOpen ||
        _permissionsOpen ||
        _connectOpen ||
        _sheetOpen ||
        _paletteOpen) {
      return true;
    }
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    return focus?.context?.widget is EditableText;
  }

  /// Sends a key to the focused Android window, if one should have it.
  ///
  /// Returns whether the event was consumed. The guards matter more than the
  /// send does: forwarding indiscriminately would swallow every keystroke the
  /// desk's own text fields need, so the search box in the drawer would stop
  /// accepting letters the moment an app window existed.
  bool _forwardKeyToWindow(KeyEvent event) {
    if (_deskOwnsKeyboard) return false;

    final WorkspaceWindow? target = _wm.windows.values
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

  /// Notes that [packageName] was opened, so the drawer can rank on habit.
  ///
  /// Counted on launch rather than on window creation: a launch that fails to
  /// produce a window is still what the person asked for, and ranking should
  /// follow intent rather than the transport's luck.
  void _recordLaunch(String packageName) {
    final AppLaunchStats? previous = widget.launchHistory[packageName];
    final Map<String, AppLaunchStats> next =
        Map<String, AppLaunchStats>.of(widget.launchHistory);
    next[packageName] = AppLaunchStats(
      count: (previous?.count ?? 0) + 1,
      lastLaunchedMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    widget.onLaunchHistoryChanged(next);
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
    final WorkspaceWindow? target = _wm.windows.values
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
    final WorkspaceWindow? target = _wm.windows.values
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
    final WorkspaceWindow? w = _wm.windows[id];
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
    final WorkspaceWindow? w = _wm.windows[id];
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
      // The outer blur gate: the person's own choice, covering every surface
      // including those stacked beside the desk rather than inside it — the
      // launcher and the settings overlay both sit outside the desk's own
      // scope, so gating only there left them frosted after glass was off.
      // The desk nests a narrower scope for the streaming case.
      child: GlassBlurScope(
        enabled: widget.glassEnabled,
        child: ReduceMotionScope(
          reduce: widget.reduceMotion,
          child: Material(
            color: Colors.transparent,
            child: _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    _connection.maybeConnect(_s);
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
              _connection.standDown();
              widget.facade.retryBoot();
            },
          ),
          // Only once the desk exists. Shown over the connection screen it would
        // be describing surfaces the person cannot see yet.
        if (!widget.tourCompleted && !_connectOpen && !_recovering)
          Positioned.fill(
            child: FirstRunTour(onFinished: widget.onTourCompleted),
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
            child: WindowStage(
              window: w,
              intents: _intents,
              onExit: _exitFullscreen,
            ),
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
            onCopyDiagnostics: widget.onCopyText == null
                ? null
                : () => widget.onCopyText!(
                    diagnosticsReport(
                      snapshot: _s,
                      buildLabel: versionLabel(),
                      platform: Platform.operatingSystem,
                    ),
                  ),
            recentExits: _recentExits,
            onClose: () => setState(() => _diagnosticsOpen = false),
          ),
      ],
    );
  }

  Widget _switcher() {
    final List<WorkspaceWindow> open = _switchList;
    return WindowSwitcher(
      windows: open,
      selected: _switcherIndex.clamp(0, open.isEmpty ? 0 : open.length - 1),
      onPick: (String id) {
        setState(() => _switcherOpen = false);
        _wm.raiseAndFocus(id);
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
            glassEnabled: widget.glassEnabled,
            snapshot: _s,
            now: _now,
            onOpenLauncher: _toggleDrawer,
            onWebSearch: _openUrl,
            onMediaAction: widget.facade.sendMediaAction,
            onFocusWindow: _wm.focusOrRestore,
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
            minimisedWindows: _wm.windows.values
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
        launchHistory: widget.launchHistory,
        pinnedPackages: widget.pinnedPackages,
        onPinnedChanged: widget.onPinnedChanged,
        onLaunch: (String pkg) {
          widget.facade.launchApplication(pkg);
          _recordLaunch(pkg);
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
          accentIndex: widget.accentIndex,
          onAccentChanged: widget.onAccentChanged,
          glassEnabled: widget.glassEnabled,
          onGlassChanged: widget.onGlassChanged,
          reduceMotion: widget.reduceMotion,
          onReduceMotionChanged: widget.onReduceMotionChanged,
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
    if (_paletteOpen) {
      return _Overlay(
        onDismiss: () => setState(() => _paletteOpen = false),
        child: CommandPalette(
          commands: _commands,
          onDismiss: () => setState(() => _paletteOpen = false),
        ),
      );
    }
    if (_sheetOpen) {
      return _Overlay(
        onDismiss: () => setState(() => _sheetOpen = false),
        child: ShortcutSheet(
          shortcuts: buildShortcuts(_shortcutHooks),
          onClose: () => setState(() => _sheetOpen = false),
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
              // choice is theirs, so auto-connect never runs again.
              _connection.standDown();
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
            // Gated on the same scope as every panel, so turning frosted
            // panels off actually turns them all off.
            child: Builder(
              builder: (BuildContext context) {
                final Widget scrim = ColoredBox(
                  color: Colors.black.withValues(
                    alpha: isDark ? 0.55 : 0.30,
                  ),
                );
                if (!GlassBlurScope.of(context)) return scrim;
                return BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: scrim,
                );
              },
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(DexSpace.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DexRadius.dialog),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.bg.withValues(alpha: isDark ? 0.92 : 0.96),
                    borderRadius: BorderRadius.circular(DexRadius.dialog),
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
