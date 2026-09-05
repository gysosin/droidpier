import 'package:flutter/material.dart';

import '../theme/glass.dart';

import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_tokens.dart';
import '../widgets/bench_backdrop.dart';
import '../widgets/link_rail.dart';
import '../workspace/window_model.dart';
import 'analog_clock.dart';
import 'control_center.dart';
import 'desk_icons.dart';
import 'desk_card.dart';
import 'desk_widgets.dart';
import 'desk_search.dart';
import 'notification_center.dart';
import 'taskbar_bar.dart';

/// The desk — the product's home screen.
///
/// A desktop environment should look inhabited, so this is a real desktop:
/// wallpaper, widgets docked down the right edge, and a taskbar along the
/// bottom carrying the apps button, the running windows and the tray. The
/// arrangement follows the product's reference desk layout rather than a
/// direction invented per screen.
///
/// [focused] is that recede: when an Android window has focus, the widgets drop
/// back so the desk stops competing with the app the person is actually using.
class Desk extends StatefulWidget {
  const Desk({
    required this.snapshot,
    this.glassEnabled = true,
    required this.now,
    required this.onOpenLauncher,
    required this.onWebSearch,
    required this.onMediaAction,
    required this.onFocusWindow,
    required this.onCloseWindow,
    required this.onOpenSettings,
    this.onManagePhones,
    required this.onToggleFullscreen,
    required this.fullscreenActive,
    required this.onNavKey,
    required this.onToggleControl,
    required this.onToggleClipboardSync,
    required this.onSetVolume,
    required this.onOpenPermissions,
    required this.onDismissNotification,
    required this.onActivateNotification,
    required this.onDismissAllNotifications,
    required this.onLaunchApplication,
    required this.workspace,
    required this.windows,
    required this.currentWorkspace,
    required this.onSelectWorkspace,
    required this.minimisedWindows,
    this.liveClock = false,
    super.key,
  });

  final OpenDexSnapshot snapshot;

  /// Whether panels may frost. False is the person's own choice in Settings;
  /// streaming switches it off regardless, for the flicker described below.
  final bool glassEnabled;
  final DateTime now;
  final VoidCallback onOpenLauncher;

  /// Opens a URL in the desktop's browser, for the top-left search bar.
  final ValueChanged<String> onWebSearch;

  /// Media transport for the strip folded into the dock.
  final ValueChanged<MediaAction> onMediaAction;
  final ValueChanged<String> onFocusWindow;
  final ValueChanged<String> onCloseWindow;

  /// Opens the settings hub (the tray gear). Volume, clipboard, device control,
  /// manage-phones and permissions all live behind it now — the reference tray
  /// carries no such buttons.
  final VoidCallback onOpenSettings;

  /// Opens the phone chooser. Null leaves the control centre's link out.
  final VoidCallback? onManagePhones;

  /// Enters/leaves edge-to-edge fullscreen for the focused window (tray button).
  final VoidCallback onToggleFullscreen;
  final bool fullscreenActive;

  /// The bottom nav pill injects an Android navigation key into the focused
  /// window's display.
  final ValueChanged<AndroidNavKey> onNavKey;

  /// Control-panel commands (quick settings): device toggles, volume, clipboard.
  final void Function(DeviceControl control, bool enabled) onToggleControl;
  final ValueChanged<bool> onToggleClipboardSync;
  final void Function(String stream, int value) onSetVolume;

  /// Opens the phone's permission settings, from the notification centre.
  final VoidCallback onOpenPermissions;

  /// Notification actions, from the notification centre (the tray bell).
  final Future<void> Function(String id) onDismissNotification;
  final Future<void> Function(String id) onActivateNotification;
  final Future<void> Function() onDismissAllNotifications;

  /// Launching an app goes through the same path from every surface.
  final ValueChanged<AndroidApplication> onLaunchApplication;

  /// The window compositor, painted between the desk's furniture and its
  /// taskbar.
  ///
  /// The desk used to be the workspace's `emptyChild`, which put every app
  /// window *above* the taskbar, tray and phone mirror — maximise an app and
  /// the taskbar was gone until you moved the window. Hosting the workspace
  /// here instead lets the desk order its own layers, and lets the taskbar
  /// reserve the work area so a window cannot be dragged underneath it.
  final Widget workspace;

  /// Passed through to the dock so a minimised window can be restored from it.
  final List<WorkspaceWindow> windows;

  /// Which virtual desktop is on screen, and how to change it. 1-based.
  final int currentWorkspace;
  final ValueChanged<int> onSelectWorkspace;
  final Set<String> minimisedWindows;

  /// Whether the analog clock runs its own live one-second ticker (product) or
  /// paints the fixed [now] (tests/goldens).
  final bool liveClock;

  @override
  State<Desk> createState() => _DeskState();
}

class _DeskState extends State<Desk> {
  /// Whether the control panel (quick settings) is open, from the tray.
  bool _controlsOpen = false;

  /// Whether the notification centre is open, from the tray bell.
  bool _notificationsOpen = false;

  /// The band reserved at the bottom for the floating dock, so a maximised
  /// window stays above it rather than running underneath. Covers the dock's
  /// glass (~52) plus its float margin (~12) with a small gap.
  static const double _taskbarHeight = 72;

  OpenDexSnapshot get snapshot => widget.snapshot;
  DateTime get now => widget.now;

  /// Whether an Android window has focus, so the widgets should recede.
  ///
  /// Only a window that is actually streaming counts. A window spends its first
  /// moments in `starting`, and during recovery it passes through
  /// `reconnecting` — taking focus on and off as it goes. Every one of those
  /// transitions used to fade all four widgets between full and half opacity,
  /// which reads as the desk blinking.
  /// Whether any window is actually delivering video right now.
  ///
  /// Distinct from [_focused]: an unfocused window still streams, and it is the
  /// streaming — not the focus — that makes a blur above it expensive.
  bool get _streaming => snapshot.windows.any(
    (WindowSessionState w) =>
        w.status == WindowSessionStatus.streaming && w.surface != null,
  );

  bool get _focused => snapshot.windows.any(
    (WindowSessionState w) =>
        w.isFocused && w.status == WindowSessionStatus.streaming,
  );

  @override
  Widget build(BuildContext context) {
    // Layer order, deliberately: wallpaper, desk furniture, the phone, then
    // app windows over all of that, then the taskbar over the windows, then
    // the popovers the taskbar opens. Every desktop keeps its taskbar on top;
    // this one did not, because the desk was the workspace's background.
    //
    // While a window streams, blur across the whole desk is switched off. A
    // BackdropFilter re-blurs its backdrop every frame the backdrop changes, so
    // dozens of glass panels over a live 60 fps texture re-blur the scene
    // continuously — which read as the desk flickering. Flat translucent glass
    // is nearly indistinguishable at these alphas and costs nothing.
    return GlassBlurScope(
      // Two independent reasons to drop the blur, and either is enough: the
      // person turned glass off, or a window is streaming.
      enabled: widget.glassEnabled && !_streaming,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const DexWallpaper(),
          // Home furniture, over the wallpaper and under the app windows: the
          // two search bars top-left, the app icons filling the left below
          // them, a large bare analog clock top-right, and — where the desk is
          // big enough for it — a column of widgets under the clock. The dock
          // and tray carry the same readings in compact form, so the column is
          // the first thing dropped when the desk is small.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _taskbarHeight,
            child: _Furniture(
              onOpenControls: () => setState(() => _controlsOpen = true),
              onOpenNotifications: () =>
                  setState(() => _notificationsOpen = true),
              now: now,
              recessive: _focused,
              applications: snapshot.applications,
              onLaunch: widget.onLaunchApplication,
              onWebSearch: widget.onWebSearch,
              liveClock: widget.liveClock,
              snapshot: snapshot,
              onMediaAction: widget.onMediaAction,
            ),
          ),
          // App windows: over the desk's furniture, under its taskbar, and inset
          // by the taskbar's height so one cannot be dragged out of reach.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _taskbarHeight,
            child: widget.workspace,
          ),
          // The segmented bottom bar spans the full width so the nav pill sits
          // left, the apps-grid button centres, and the tray sits right.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Entrance(
              order: 5,
              rise: 18,
              child: TaskbarBar(
                windows: widget.windows,
                currentWorkspace: widget.currentWorkspace,
                onSelectWorkspace: widget.onSelectWorkspace,
                minimised: widget.minimisedWindows,
                onOpenLauncher: widget.onOpenLauncher,
                onFocus: widget.onFocusWindow,
                onClose: widget.onCloseWindow,
                media: snapshot.media,
                onMediaAction: widget.onMediaAction,
                onNavKey: widget.onNavKey,
                navEnabled: _focused,
                trailing: SystemTray(
                  now: now,
                  telemetry: snapshot.telemetry,
                  onOpenControls: () => setState(() => _controlsOpen = true),
                  onOpenNotifications: () =>
                      setState(() => _notificationsOpen = true),
                  notificationCount: snapshot.notifications.length,
                  onOpenSettings: widget.onOpenSettings,
                  onToggleFullscreen: widget.onToggleFullscreen,
                  fullscreenActive: widget.fullscreenActive,
                ),
              ),
            ),
          ),
          if (_controlsOpen) ...<Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _controlsOpen = false),
              ),
            ),
            // Anchored above the tray, which is where it opens from.
            Positioned(
              bottom: _taskbarHeight + 6,
              right: DexSpace.lg,
              child: Entrance(
                rise: 6,
                child: ControlCenter(
                  telemetry: snapshot.telemetry,
                  clipboard: snapshot.clipboard,
                  connectionKind: snapshot.selectedDevice?.connectionKind,
                  agentStatus: snapshot.agentStatus,
                  onToggleControl: widget.onToggleControl,
                  onToggleClipboardSync: widget.onToggleClipboardSync,
                  onSetVolume: widget.onSetVolume,
                  onManagePhones: widget.onManagePhones == null
                      ? null
                      : () {
                          setState(() => _controlsOpen = false);
                          widget.onManagePhones!();
                        },
                  onOpenSettings: () {
                    setState(() => _controlsOpen = false);
                    widget.onOpenSettings();
                  },
                ),
              ),
            ),
          ],
          if (_notificationsOpen)
            Focus(
              autofocus: true,
              onKeyEvent: (FocusNode _, KeyEvent event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(() => _notificationsOpen = false);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: NotificationCenter(
                notifications: snapshot.notifications,
                status: snapshot.notificationStatus,
                applications: snapshot.applications,
                now: now,
                onClose: () => setState(() => _notificationsOpen = false),
                onDismiss: widget.onDismissNotification,
                onActivate: widget.onActivateNotification,
                onDismissAll: widget.onDismissAllNotifications,
                onOpenPermissions: () {
                  setState(() => _notificationsOpen = false);
                  widget.onOpenPermissions();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The desk's home furniture, laid out over the wallpaper: search bars
/// top-left, app icons filling the left beneath them, and a large bare analog
/// clock top-right.
class _Furniture extends StatelessWidget {
  const _Furniture({
    required this.now,
    required this.recessive,
    required this.applications,
    required this.onLaunch,
    required this.onWebSearch,
    required this.liveClock,
    required this.snapshot,
    required this.onMediaAction,
    required this.onOpenControls,
    required this.onOpenNotifications,
  });

  /// The widget column's doors: a card that previews a surface opens it.
  final VoidCallback onOpenControls;
  final VoidCallback onOpenNotifications;

  /// Everything the right-hand column reads. All of it is already on the
  /// snapshot the desk is given, so the column costs no new plumbing.
  final OpenDexSnapshot snapshot;
  final ValueChanged<MediaAction> onMediaAction;

  final DateTime now;
  final bool recessive;
  final List<AndroidApplication> applications;
  final ValueChanged<AndroidApplication> onLaunch;
  final ValueChanged<String> onWebSearch;
  final bool liveClock;

  /// Where the search bar starts, leaving the corner above it to the collapsed
  /// Link Rail.
  static const double _searchTop = 56;

  /// The bare clock's diameter, and the width below which it is dropped so it
  /// cannot collide with the search bars.
  static const double _clockSize = 280;
  static const double _clockMinWidth = 860;

  /// The right-hand column's width, and the desk width below which it is
  /// dropped entirely. The icons and the search bar are what the desk is for;
  /// a status card squeezed against them is worse than no status card.
  static const double _columnWidth = DeskCard.width;
  static const double _columnMinWidth = 1180;

  /// 660, measured rather than guessed. The column hangs below the clock, so
  /// what it needs is the clock's own extent plus room for two cards: 16 + 300
  /// + 16 of clock, then about 320 of column, then a bottom margin.
  ///
  /// It was 760, which sounded safe and meant the column never appeared on a
  /// laptop at all. The desk gets the window height less the 72px taskbar, so
  /// a 1280x800 screen leaves 691 and a 1366x768 one leaves 659 — both under
  /// the old bar, and between them that is most laptops. Tests pin both.
  static const double _columnMinHeight = 660;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final bool showClock = w >= _clockMinWidth;
        // Height matters as much as width: the column hangs below the clock,
        // and on a short desk there is nothing left for it to hang into.
        final bool showColumn =
            w >= _columnMinWidth && constraints.maxHeight >= _columnMinHeight;
        // Leave the clock its corner: cap the search bars so a wide window does
        // not run them under the clock.
        final double searchMax =
            (showClock ? w - _clockSize - DexSpace.xl * 3 : w - DexSpace.lg * 2)
                .clamp(280.0, 620.0);

        return Stack(
          children: <Widget>[
            // App icons fill the left, starting below the search bars.
            Positioned(
              left: 0,
              right: 0,
              // Directly under the search pill, as the reference has it: the
              // rail at 16, the pill at 56, the icons at 112. They used to
              // start at 190, which left a band of empty wallpaper between the
              // pill and the first app.
              top: 112,
              bottom: 0,
              child: AnimatedOpacity(
                duration: DexDuration.standard,
                curve: DexMotion.arrive,
                opacity: recessive ? 0.4 : 1,
                child: DeskIcons(
                  applications: applications,
                  onLaunch: onLaunch,
                ),
              ),
            ),
            // The Link Rail, collapsed. First thing on the desk, and the only
            // furniture that does not recede behind a stream: whether the link
            // is healthy is exactly what a user wants to read while something
            // is streaming.
            Positioned(
              top: DexSpace.lg,
              left: DexSpace.lg,
              child: Entrance(
                order: 0,
                child: LinkRailChip(
                  telemetry: snapshot.telemetry,
                  live:
                      snapshot.recovery.phase == RecoveryPhase.idle ||
                      snapshot.recovery.phase == RecoveryPhase.recovered,
                  readings: w >= 900
                      ? 3
                      : w >= 700
                      ? 2
                      : 1,
                ),
              ),
            ),
            // Search bars, below the rail.
            Positioned(
              top: _searchTop,
              left: DexSpace.lg,
              child: Entrance(
                order: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: searchMax),
                  child: DeskSearchBars(onSearch: onWebSearch),
                ),
              ),
            ),
            // A large bare analog clock, top-right — no card, lifted off the
            // wallpaper by a soft shadow.
            if (showClock)
              Positioned(
                top: DexSpace.xl,
                right: DexSpace.xl,
                child: Entrance(
                  order: 2,
                  child: AnimatedOpacity(
                    duration: DexDuration.standard,
                    curve: DexMotion.arrive,
                    opacity: recessive ? 0.4 : 1,
                    child: Container(
                      width: _clockSize,
                      height: _clockSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          // The reference's dial shadow: lifted, and pulled in
                          // rather than spread, so it reads as a disc sitting
                          // on the wallpaper instead of glowing against it.
                          BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 36,
                            spreadRadius: -4,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: AnalogClock(now: now, live: liveClock),
                    ),
                  ),
                ),
              ),
            // The right-hand column, under the clock.
            //
            // These four widgets existed and were placed nowhere: no import,
            // no test, no instantiation. The clock among them is deliberately
            // left out — the desk already has a large bare one in this corner,
            // and a second carded one beside it is not composition.
            if (showColumn)
              Positioned(
                top: DexSpace.xl + _clockSize + DexSpace.xl,
                right: DexSpace.xl,
                bottom: DexSpace.xl,
                width: _columnWidth,
                child: AnimatedOpacity(
                  duration: DexDuration.standard,
                  curve: DexMotion.arrive,
                  opacity: recessive ? 0.4 : 1,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Entrance(
                          order: 3,
                          child: NowPlayingWidget(
                            media: snapshot.media,
                            onAction: onMediaAction,
                            recessive: recessive,
                          ),
                        ),
                        const SizedBox(height: DexSpace.md),
                        Entrance(
                          order: 4,
                          child: PhoneWidget(
                            telemetry: snapshot.telemetry,
                            device: snapshot.selectedDevice,
                            recessive: recessive,
                            onOpenControls: onOpenControls,
                          ),
                        ),
                        const SizedBox(height: DexSpace.md),
                        Entrance(
                          order: 5,
                          child: NotificationsWidget(
                            notifications: snapshot.notifications,
                            status: snapshot.notificationStatus,
                            now: now,
                            recessive: recessive,
                            onOpen: onOpenNotifications,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
