import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_glass.dart';
import '../apps/app_glyph.dart';
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
            width >= 900;
        // The nav pill is dropped on a narrow desk so the fixed clusters cannot
        // push the full-width bar past the screen edge.
        final bool showNav = onNavKey != null && width >= 760;

        // What the running-apps strip may take: everything the fixed furniture
        // does not need. 760 is that furniture measured — nav pill, grid button,
        // tray and the bar's own padding — and 420 remains the ceiling so a dozen
        // open apps cannot run the strip across a wide desk.
        final double appsMax = (width - 760).clamp(0, 420).toDouble();

        // What is left for the tray once the bar's padding, the grid button and a
        // minimum left cluster are accounted for.
        final double trayMax = (width - 140)
            .clamp(0, double.infinity)
            .toDouble();

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
              _AppsGridButton(onPressed: onOpenLauncher, colors: c),
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
          _NavButton(
            icon: Icons.menu,
            label: 'Menu',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.menu) : null,
            colors: colors,
          ),
          _NavButton(
            icon: Icons.radio_button_unchecked,
            label: 'Home',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.home) : null,
            colors: colors,
          ),
          _NavButton(
            icon: Icons.arrow_back_ios_new,
            label: 'Back',
            onPressed: enabled ? () => onNavKey(AndroidNavKey.back) : null,
            colors: colors,
          ),
          _NavButton(
            icon: Icons.search,
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
class _AppsGridButton extends StatelessWidget {
  const _AppsGridButton({required this.onPressed, required this.colors});

  final VoidCallback onPressed;
  final DexColors colors;

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
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: 52,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.signal.withValues(alpha: hovered ? 1 : 0.9),
                borderRadius: BorderRadius.circular(DexRadius.panel),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.signal.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 20,
                color: Colors.white,
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
    final TextTheme t = Theme.of(context).textTheme;

    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MiniArt(media: media, colors: colors),
          const SizedBox(width: DexSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  media.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(color: colors.text),
                ),
                if (media.artist != null)
                  Text(
                    media.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(color: colors.muted),
                  ),
                if (media.durationMs != null &&
                    media.durationMs! > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  _MediaProgress(media: media, colors: colors),
                ],
              ],
            ),
          ),
          const SizedBox(width: DexSpace.xs),
          _MiniTransport(
            icon: Icons.skip_previous,
            label: 'Previous track',
            onPressed: () => onAction(MediaAction.previous),
            colors: colors,
          ),
          _MiniTransport(
            icon: _playing ? Icons.pause : Icons.play_arrow,
            label: _playing ? 'Pause' : 'Play',
            accent: true,
            onPressed: () => onAction(MediaAction.playPause),
            colors: colors,
          ),
          _MiniTransport(
            icon: Icons.skip_next,
            label: 'Next track',
            onPressed: () => onAction(MediaAction.next),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

/// A live-ticking media progress bar. The phone reports a position sample; this
/// extrapolates from it locally while playing, so the bar moves smoothly
/// without the phone streaming a value every tick.
class _MediaProgress extends StatefulWidget {
  const _MediaProgress({required this.media, required this.colors});

  final MediaState media;
  final DexColors colors;

  @override
  State<_MediaProgress> createState() => _MediaProgressState();
}

class _MediaProgressState extends State<_MediaProgress> {
  Timer? _timer;
  int _baseMs = 0;
  DateTime _baseAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MediaProgress old) {
    super.didUpdateWidget(old);
    if (old.media.positionMs != widget.media.positionMs ||
        old.media.playback != widget.media.playback) {
      _sync();
    }
  }

  void _sync() {
    _baseMs = widget.media.positionMs ?? 0;
    _baseAt = DateTime.now();
    _timer?.cancel();
    if (widget.media.playback == PlaybackState.playing) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? dur = widget.media.durationMs;
    if (dur == null || dur <= 0) return const SizedBox.shrink();
    final bool playing = widget.media.playback == PlaybackState.playing;
    final int elapsed = playing
        ? DateTime.now().difference(_baseAt).inMilliseconds
        : 0;
    final double value = ((_baseMs + elapsed) / dur).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DexRadius.pill),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 3,
          backgroundColor: widget.colors.line,
          valueColor: AlwaysStoppedAnimation<Color>(widget.colors.signal),
        ),
      ),
    );
  }
}

class _MiniArt extends StatelessWidget {
  const _MiniArt({required this.media, required this.colors});

  final MediaState media;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    const double size = 34;
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.control),
      ),
      child: Icon(Icons.music_note, size: 16, color: colors.muted),
    );
    final List<int>? art = media.artwork;
    if (art == null || art.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DexRadius.control),
      child: Image.memory(
        Uint8List.fromList(art),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _MiniTransport extends StatelessWidget {
  const _MiniTransport({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colors,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final DexColors colors;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(DexRadius.control),
          child: SizedBox(
            width: 34,
            height: 40,
            child: Icon(
              icon,
              size: 18,
              color: accent ? colors.signal : colors.text,
            ),
          ),
        ),
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
              width: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: DexSpace.xs),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppGlyph(app: window.session.application, size: 24),
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dot,
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
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final String m = now.minute.toString().padLeft(2, '0');
    final String ap = now.hour < 12 ? 'AM' : 'PM';

    // On a bar this narrow the tray sheds rather than overflows. The date is
    // the first to go — the time is the readout people glance at — and the
    // fullscreen toggle follows it, because F11 still does the same job and
    // the title bar carries its own control.

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
          icon: Icons.settings_outlined,
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
          icon: fullscreenActive ? Icons.fullscreen_exit : Icons.fullscreen,
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
                    Icon(Icons.wifi, size: 15, color: colors.muted),
                    const SizedBox(width: DexSpace.sm),
                  ],
                  if (battery != null) ...<Widget>[
                    if (telemetry.charging)
                      Icon(Icons.bolt, size: 14, color: colors.signal),
                    Icon(Icons.battery_full, size: 15, color: colors.muted),
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
                  Icon(Icons.notifications_none, size: 18, color: colors.text),
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
