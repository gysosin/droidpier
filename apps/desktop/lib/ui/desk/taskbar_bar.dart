import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_glass.dart';
import '../theme/glass.dart';
import '../theme/dex_tokens.dart';
import '../workspace/window_model.dart';

/// The bottom bar of the desk, present on the home screen and behind windows.
///
/// A segmented bar, not one pill: a nav pill (menu·home·back·search) and the
/// running apps + media on the left, the apps-grid button in the centre, and
/// the system tray on the right — each a floating rounded-glass cluster.
class TaskbarBar extends StatelessWidget {
  const TaskbarBar({
    required this.windows,
    required this.minimised,
    required this.onOpenLauncher,
    required this.onFocus,
    required this.onClose,
    required this.trailing,
    this.currentWorkspace = 1,
    this.onSelectWorkspace,
    this.media,
    this.onMediaAction,
    this.onNavKey,
    this.navEnabled = false,
    super.key,
  });

  final List<WorkspaceWindow> windows;
  final Set<String> minimised;

  /// The centre apps-grid button.
  final VoidCallback onOpenLauncher;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onClose;

  /// The system tray, at the right.
  final Widget trailing;

  /// Which virtual desktop is on screen, and how to change it. 1-based.
  final int currentWorkspace;
  final ValueChanged<int>? onSelectWorkspace;

  /// The currently playing media, shown as a pill on the left.
  final MediaState? media;
  final ValueChanged<MediaAction>? onMediaAction;

  /// Android navigation keys for the nav pill. Enabled only when a window is
  /// focused (the keys inject into that window's display).
  final ValueChanged<AndroidNavKey>? onNavKey;
  final bool navEnabled;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final List<WorkspaceWindow> live = windows
        .where(
          (WorkspaceWindow w) => w.session.status != WindowSessionStatus.closed,
        )
        .toList();

    // The width the bar is actually given, not the window's.
    // `MediaQuery.sizeOf` answers for the window, which is a different number
    // whenever the bar is inset — and in a widget test driven by
    // `setSurfaceSize` it stays at the default view size entirely, so every
    // threshold below silently evaluated against 800 no matter what the test
    // asked for. That is why a tray meant to shed controls at 480 never shed
    // any.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final bool showMedia =
            media != null &&
            media!.playback != PlaybackState.unavailable &&
            onMediaAction != null &&
            // 1100, not 900. At exactly 900 the strip is admitted at the very
            // width where it does not fit: the nav pill, the grid button and
            // the tray already fill the bar, and adding media overflowed it by
            // 35px. The strip is a convenience and the dock's own transport
            // reaches the same controls, so it is the right thing to lose
            // first.
            width >= 1100;
        // The nav pill is dropped on a narrow desk so the fixed clusters cannot
        // push the full-width bar past the screen edge.
        final bool showNav = onNavKey != null && width >= 760;
        // 1100, not 760. The dock's fixed furniture — nav pill, launcher, tray
        // and padding — already wants about 760, and these two additions cost
        // roughly 150 and 76 more. Admitted at 760 they overflowed the bar by
        // 65px at 800 wide with no windows open at all. Switching desks is a
        // rarer job than reaching the launcher, so the keys are what a narrow
        // desk gives up.
        final bool showWorkspaces = onSelectWorkspace != null && width >= 1100;
        // The launcher keeps its button at every width and loses only its
        // label, which costs about 76px.
        final bool labelLauncher = width >= 1100;

        // The bar's whole width budget, in one place.
        //
        // It used to be two independent numbers — the apps strip could take
        // `width - 760` and the tray `width - 140` — which between them could
        // claim more than the bar had. That was survivable while the dock held
        // less; adding the workspace keys and the launcher's label overflowed
        // it by 49px at 1280 with two windows open.
        //
        // Now: measure what cannot shrink, then split what is left. The sum of
        // the two flexible clusters is the remainder by construction, so the
        // Row cannot overflow at any width.
        const double kNavPill = 168;
        const double kWorkspacePill = 160; // keys plus the gap before them
        const double kMediaPill = 176; // pill plus the gap before it
        const double kLauncher = 64;
        // Measured, not guessed: "Your apps" renders 118px wide in the bundled
        // face, plus the gap after the icon. Estimating it at 76 is what left
        // the bar overflowing by 49px at 1280 with windows open.
        const double kLauncherLabel = 126;

        // Slack. Every constant above is a measured width, and measured widths
        // move with the font, the locale and the icon set. The flexible
        // clusters give up the difference, which costs a few pixels of
        // running-apps strip and nothing a user would notice — whereas
        // under-counting overflows the bar, which they would.
        const double kSlack = 40;

        // Each glass pill adds its own horizontal padding, and the bar can
        // carry four of them. Left unaccounted, that chrome is invisible in the
        // budget right up until the flexible clusters actually fill their caps
        // — which is what the labelled task chips made happen.
        const double kPillChrome = DexSpace.sm * 2;
        final int pills =
            ((showNav || live.isNotEmpty) ? 1 : 0) +
            (showWorkspaces ? 1 : 0) +
            (showMedia ? 1 : 0) +
            1; // the tray always has one

        final double fixed =
            kSlack +
            pills * kPillChrome +
            (showNav ? kNavPill : 0) +
            (showWorkspaces ? kWorkspacePill : 0) +
            (showMedia ? kMediaPill : 0) +
            kLauncher +
            (labelLauncher ? kLauncherLabel : 0);
        final double spare = (width - DexSpace.lg * 2 - fixed)
            .clamp(0, double.infinity)
            .toDouble();

        // The tray gets first call on the spare: the clock, the battery and
        // the notification count are read far more often than the running-apps
        // strip is clicked. It is capped anyway, so a wide desk gives the
        // surplus to the apps rather than stretching a row of icons.
        final double trayMax = (spare * 0.62).clamp(120, 400).toDouble();
        final double appsMax = (spare - trayMax).clamp(0, 420).toDouble();

        return Padding(
          padding: const EdgeInsets.only(
            left: DexSpace.lg,
            right: DexSpace.lg,
            bottom: DexSpace.md,
          ),
          child: Row(
            children: <Widget>[
              // LEFT cluster: nav pill and the running apps share one pill so the
              // bar reads as clean segments, not a row of touching borders.
              if (showNav || live.isNotEmpty)
                _Pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showNav)
                        _NavPill(
                          onNavKey: onNavKey!,
                          enabled: navEnabled,
                          colors: c,
                        ),
                      if (showNav && live.isNotEmpty)
                        Container(
                          width: DexStroke.hairline,
                          height: 28,
                          margin: const EdgeInsets.symmetric(
                            horizontal: DexSpace.xs,
                          ),
                          color: c.line,
                        ),
                      if (live.isNotEmpty)
                        ConstrainedBox(
                          // Bounded by what is actually left, not by a fixed 420.
                          // The nav pill, the grid button and the tray are all
                          // effectively fixed, so a running-apps strip that always
                          // claimed 420 pushed the bar past the screen edge on a
                          // narrower desk — 35 pixels at 900. The strip already
                          // scrolls, so giving ground costs reach, not entries.
                          constraints: BoxConstraints(maxWidth: appsMax),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (
                                  int i = 0;
                                  i < live.length;
                                  i++
                                ) ...<Widget>[
                                  if (i > 0) const SizedBox(width: DexSpace.xs),
                                  _TaskEntry(
                                    window: live[i],
                                    minimised: minimised.contains(live[i].id),
                                    colors: c,
                                    onFocus: () => onFocus(live[i].id),
                                    onClose: () => onClose(live[i].id),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (showWorkspaces) ...<Widget>[
                if (showNav || live.isNotEmpty)
                  const SizedBox(width: DexSpace.sm),
                _Pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 1; i <= kWorkspaceCount; i++)
                        _WorkspaceKey(
                          number: i,
                          current: i == currentWorkspace,
                          colors: c,
                          onSelect: () => onSelectWorkspace!(i),
                        ),
                    ],
                  ),
                ),
              ],
              if (showMedia) ...<Widget>[
                const SizedBox(width: DexSpace.sm),
                _Pill(
                  child: _MediaMini(
                    media: media!,
                    onAction: onMediaAction!,
                    colors: c,
                  ),
                ),
              ],
              const Spacer(),
              // CENTRE: the apps-grid button.
              _AppsGridButton(
                onPressed: onOpenLauncher,
                colors: c,
                labelled: labelLauncher,
              ),
              const Spacer(),
              // RIGHT: the system tray, bounded and scrollable.
              //
              // Even after shedding the date, the fullscreen toggle and the
              // settings gear, the tray still wants ~356px — more than a 480px bar
              // can give it alongside the grid button. Rather than shedding
              // controls until it fits a width nobody runs the shell at, it is
              // capped at what is actually spare and scrolls inside that. Reversed,
              // so the clock stays visible and the bell scrolls away first.
              //
              // Bounded here rather than made Flexible on purpose: a loose
              // Flexible claims a share of the free space and wastes whatever it
              // does not use, which pulled the tray off the right edge and left
              // the grid button off-centre.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: trayMax),
                child: _Pill(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: trailing,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A floating rounded-glass cluster — the shape every group in the bar takes.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 22,
      stroke: Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.sm,
        vertical: DexSpace.xs,
      ),
      child: child,
    );
  }
}

/// The Android navigation pill: menu · home · back · search.
///
/// The keys inject into the focused window's display, so the pill is disabled
/// (dimmed, no taps) when nothing is focused — honest rather than a dead button.
class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.onNavKey,
    required this.enabled,
    required this.colors,
  });

  final ValueChanged<AndroidNavKey> onNavKey;
  final bool enabled;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Android's own order: back, home, overview. A hamburger was the
          // first key here and it sends Menu, which almost no app answers.
          _NavButton(
            icon: DexIcons.back,
            label: 'Back',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.back) : null,
            colors: colors,
          ),
          _NavButton(
            icon: DexIcons.home,
            label: 'Home',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.home) : null,
            colors: colors,
          ),
          _NavButton(
            icon: DexIcons.recents,
            label: 'Recents',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.recents) : null,
            colors: colors,
          ),
          _NavButton(
            icon: DexIcons.search,
            label: 'Search',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.search) : null,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Tooltip(
        message: label,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(DexRadius.card),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hovered ? glass.fillStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.card),
              ),
              child: Icon(icon, size: 17, color: colors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// The centre apps-grid button — a filled square with a 2×2 grid, as the
/// reference has it.
/// The centre launcher button.
///
/// It says "Your apps" rather than being a coloured square with a glyph in it.
/// This is the one control on the desk that opens everything, and an unlabelled
/// icon asks a first-time user to guess at exactly the moment they have the
/// least to go on. The label is dropped on a narrow bar, where the word costs
/// more than it earns.
/// One numbered virtual-desktop key.
///
/// Sized at the WCAG 2.2 minimum rather than the comfortable step: four of
/// these sit in one pill next to controls that are already fighting for width,
/// and the floor is a floor, not a compromise.
class _WorkspaceKey extends StatelessWidget {
  const _WorkspaceKey({
    required this.number,
    required this.current,
    required this.colors,
    required this.onSelect,
  });

  final int number;
  final bool current;
  final DexColors colors;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Semantics(
      button: true,
      selected: current,
      label: 'Workspace $number',
      child: Tooltip(
        message: 'Workspace $number',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(DexRadius.control),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: DexHit.minimum,
              height: DexHit.minimum,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Selection out-contrasts hover, hover out-contrasts rest.
                color: current
                    ? colors.signal.withValues(alpha: 0.28)
                    : hovered
                    ? glass.fillStrong
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.control),
              ),
              child: Text(
                '$number',
                style: DexTheme.data(
                  colors,
                  size: 11,
                  color: current ? colors.text : colors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppsGridButton extends StatelessWidget {
  const _AppsGridButton({
    required this.onPressed,
    required this.colors,
    this.labelled = true,
  });

  final VoidCallback onPressed;
  final DexColors colors;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Your apps',
      child: Tooltip(
        message: 'Your apps',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(DexRadius.panel),
            child: AnimatedScale(
              // The reference lifts the launcher a touch on hover: 1.02, enough
              // to answer the pointer, not enough to move its neighbours.
              scale: hovered ? 1.02 : 1,
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              child: AnimatedContainer(
                duration: DexDuration.micro,
                curve: DexMotion.arrive,
                height: 44,
                padding: EdgeInsets.symmetric(
                  horizontal: labelled ? DexSpace.lg : DexSpace.md,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.signal.withValues(alpha: hovered ? 1 : 0.9),
                  borderRadius: BorderRadius.circular(DexRadius.panel),
                  // The reference gives this button a plain elevation shadow,
                  // not a coloured halo. A glow behind a filled accent button
                  // reads as a highlight effect rather than as a control, and
                  // this design spends its one glow on the live dot.
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 25,
                      spreadRadius: -5,
                      offset: Offset(0, 20),
                    ),
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 10,
                      spreadRadius: -6,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      DexIcons.appsGrid,
                      size: 20,
                      color: Colors.white,
                    ),
                    if (labelled) ...<Widget>[
                      const SizedBox(width: DexSpace.sm),
                      Text(
                        'Your apps',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Now playing: album art, title/artist, and a prev/play-pause/next transport.
class _MediaMini extends StatelessWidget {
  const _MediaMini({
    required this.media,
    required this.onAction,
    required this.colors,
  });

  final MediaState media;
  final ValueChanged<MediaAction> onAction;
  final DexColors colors;

  bool get _playing => media.playback == PlaybackState.playing;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    // A round play/pause and the title. The dock is not the place for the
    // artwork, the artist and three transport keys — the Now Playing widget
    // and the control centre both carry those, and a dock entry that wide
    // pushed the launcher off centre on a laptop.
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: true,
            label: _playing ? 'Pause' : 'Play',
            child: InkWell(
              onTap: () => onAction(MediaAction.playPause),
              customBorder: const CircleBorder(),
              child: Container(
                width: DexHit.minimum,
                height: DexHit.minimum,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glass.fillStrong,
                ),
                child: Icon(
                  _playing ? DexIcons.pause : DexIcons.play,
                  size: 12,
                  color: colors.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: DexSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              media.title ?? 'Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.text, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// One running app: its launcher icon, and a dot that says it is running.
class _TaskEntry extends StatelessWidget {
  const _TaskEntry({
    required this.window,
    required this.minimised,
    required this.colors,
    required this.onFocus,
    required this.onClose,
  });

  final WorkspaceWindow window;
  final bool minimised;
  final DexColors colors;
  final VoidCallback onFocus;
  final VoidCallback onClose;

  Color get _dot => switch (window.session.status) {
    WindowSessionStatus.failed => colors.fault,
    WindowSessionStatus.reconnecting => colors.signal,
    _ when minimised => colors.muted.withValues(alpha: 0.5),
    _ => colors.signal,
  };

  String get _note => minimised
      ? ' — minimised'
      : switch (window.session.status) {
          WindowSessionStatus.starting => ' — opening',
          WindowSessionStatus.reconnecting => ' — reconnecting',
          WindowSessionStatus.failed => ' — failed',
          WindowSessionStatus.suspended => ' — paused',
          _ => '',
        };

  @override
  Widget build(BuildContext context) {
    final bool active = window.isFocused && !minimised;
    final DexGlass glass = DexGlass.of(context);
    return Semantics(
      button: true,
      selected: active,
      label:
          '${minimised ? 'Restore' : 'Focus'} '
          '${window.session.application.label}$_note, hold to close',
      child: Tooltip(
        message:
            '${window.session.application.label}$_note'
            '\nHold to close',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onFocus,
            onLongPress: onClose,
            borderRadius: BorderRadius.circular(DexRadius.card),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              height: 44,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: DexSpace.sm,
                vertical: DexSpace.xs,
              ),
              // Borderless: the entry sits inside the dock pill already, so its
              // own hairline made a double edge. State reads from the fill and
              // the running dot instead.
              decoration: BoxDecoration(
                color: active
                    ? colors.signal.withValues(alpha: 0.28)
                    : hovered
                    ? glass.fillStrong
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.card),
              ),
              // A dot, the icon and the name, reading left to right. It used
              // to be an icon with a dot under it and no label, which asks a
              // person to recognise a 24px glyph rather than read a word — and
              // two windows of the same app were indistinguishable.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dot,
                      // The focused entry's dot carries a glow, which is the
                      // reference's one use of it and the only place on the
                      // dock where anything is lit.
                      boxShadow: active
                          ? <BoxShadow>[BoxShadow(color: _dot, blurRadius: 6)]
                          : null,
                    ),
                  ),
                  const SizedBox(width: DexSpace.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Text(
                      window.session.application.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: active ? colors.text : colors.muted,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The system tray: a live status cluster (Wi-Fi, battery) that opens the
/// control panel, the settings gear, the clock, and a fullscreen toggle — as
/// the reference tray shows.
class SystemTray extends StatelessWidget {
  const SystemTray({
    required this.now,
    required this.telemetry,
    required this.onOpenControls,
    required this.onOpenNotifications,
    required this.notificationCount,
    required this.onOpenSettings,
    required this.onToggleFullscreen,
    required this.fullscreenActive,
    super.key,
  });

  final DateTime now;
  final DeviceTelemetry telemetry;

  /// Opens the control panel (quick settings).
  final VoidCallback onOpenControls;

  /// Opens the notification centre; the badge shows how many are waiting.
  final VoidCallback onOpenNotifications;
  final int notificationCount;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleFullscreen;
  final bool fullscreenActive;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sept',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final String m = now.minute.toString().padLeft(2, '0');
    // Lowercase, as the reference sets it: the meridiem is a suffix, not
    // a word, and capitals make it shout.
    final String ap = now.hour < 12 ? 'am' : 'pm';

    // When the bar cannot give the tray its full width it is scrolled rather
    // than shed, reversed, so it gives way from the bell end and the clock —
    // the readout people actually glance at — stays put. TaskbarBar owns that
    // decision because only it knows what width is left.
    //
    // This comment used to describe per-control shedding, with the date going
    // first and the fullscreen toggle after it. That never existed in the
    // build method, and it would not have helped anyway: the date sits under
    // the time in a column, so dropping it saves height, not width.

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Bell(
          count: notificationCount,
          onPressed: onOpenNotifications,
          colors: c,
        ),
        const SizedBox(width: DexSpace.xs),
        // Live status → opens the control panel.
        _StatusCluster(
          telemetry: telemetry,
          onPressed: onOpenControls,
          colors: c,
        ),
        const SizedBox(width: DexSpace.xs),
        _TrayButton(
          icon: DexIcons.settings,
          label: 'Settings',
          onPressed: onOpenSettings,
          colors: c,
        ),
        const SizedBox(width: DexSpace.xs),
        InkWell(
          onTap: onOpenControls,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.sm,
              vertical: DexSpace.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SwapText(
                  '$h:$m $ap',
                  style: DexTheme.data(c, size: 12, color: c.text),
                ),
                Text(
                  '${now.day} ${_months[now.month - 1]}',
                  style: DexTheme.data(c, size: 10),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: DexSpace.xs),
        _TrayButton(
          icon: fullscreenActive
              ? DexIcons.fullscreenExit
              : DexIcons.fullscreen,
          label: fullscreenActive ? 'Exit fullscreen' : 'Fullscreen',
          onPressed: onToggleFullscreen,
          colors: c,
        ),
      ],
    );
  }
}

/// Live Wi-Fi + battery, tappable to open the control panel.
class _StatusCluster extends StatelessWidget {
  const _StatusCluster({
    required this.telemetry,
    required this.onPressed,
    required this.colors,
  });

  final DeviceTelemetry telemetry;
  final VoidCallback onPressed;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    final int? battery = telemetry.batteryPercentage;
    return Semantics(
      button: true,
      label: 'Control panel',
      child: Tooltip(
        message: 'Control panel',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(DexRadius.card),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: DexSpace.sm),
              decoration: BoxDecoration(
                color: hovered ? glass.fillStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.card),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (telemetry.wifiEnabled ?? false) ...<Widget>[
                    Icon(DexIcons.wifi, size: 15, color: colors.muted),
                    const SizedBox(width: DexSpace.sm),
                  ],
                  if (battery != null) ...<Widget>[
                    if (telemetry.charging)
                      Icon(DexIcons.charging, size: 14, color: colors.signal),
                    Icon(DexIcons.batteryFull, size: 15, color: colors.muted),
                    const SizedBox(width: 4),
                    Text('$battery%', style: DexTheme.data(colors, size: 11)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The notification bell, with a count badge like the reference tray's "4".
class _Bell extends StatelessWidget {
  const _Bell({
    required this.count,
    required this.onPressed,
    required this.colors,
  });

  final int count;
  final VoidCallback onPressed;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    final String label = count == 0
        ? 'Notifications, none waiting'
        : count == 1
        ? 'Notifications, 1 waiting'
        : 'Notifications, $count waiting';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(DexRadius.card),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hovered ? glass.fillStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.card),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(DexIcons.notifications, size: 18, color: colors.text),
                  if (count > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        constraints: const BoxConstraints(minWidth: 14),
                        height: 14,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.signal,
                          borderRadius: BorderRadius.circular(
                            DexRadius.control,
                          ),
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round, icon-only tray button.
class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(DexRadius.card),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hovered ? glass.fillStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.card),
              ),
              child: Icon(icon, size: 18, color: colors.text),
            ),
          ),
        ),
      ),
    );
  }
}
