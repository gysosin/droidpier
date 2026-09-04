import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../util/relative_time.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'desk_card.dart';

/// Now playing, as a desk widget rather than a panel row.
class NowPlayingWidget extends StatelessWidget {
  const NowPlayingWidget({
    required this.media,
    required this.onAction,
    this.recessive = false,
    super.key,
  });

  final MediaState media;
  final ValueChanged<MediaAction> onAction;
  final bool recessive;

  bool get _available => media.playback != PlaybackState.unavailable;
  bool get _playing => media.playback == PlaybackState.playing;

  /// `m:ss`, the way a scrubber says it. Null renders as a dash, never 0:00.
  static String clock(int? ms) {
    if (ms == null) return '—';
    final int s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final int? duration = media.durationMs;
    final int? position = media.positionMs;
    final double? progress = duration == null || duration <= 0 || position == null
        ? null
        : (position / duration).clamp(0.0, 1.0);

    return DeskCard(
      label: 'Now playing',
      icon: DexIcons.music,
      recessive: recessive,
      trailing: _Chip('PHONE AUDIO', colors: c),
      child: !_available || media.title == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: DexSpace.lg),
              child: Center(
                child: Text(
                  'Nothing playing on device',
                  style: t.bodySmall?.copyWith(color: c.muted),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _Artwork(media: media, colors: c),
                    const SizedBox(width: DexSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SwapText(
                            media.title!,
                            style: (t.labelLarge ?? const TextStyle()).copyWith(
                              color: c.text,
                            ),
                          ),
                          if (media.artist != null)
                            SwapText(
                              media.artist!,
                              style: (t.labelSmall ?? const TextStyle())
                                  .copyWith(color: c.muted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DexSpace.md),
                // The scrubber. An unknown duration draws an empty track and a
                // dash: a bar that invents progress is worse than none.
                ClipRRect(
                  borderRadius: BorderRadius.circular(DexRadius.pill),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(child: ColoredBox(color: glass.fill)),
                        if (progress != null)
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: ColoredBox(color: c.signal),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DexSpace.xs),
                Row(
                  children: <Widget>[
                    Text(clock(position), style: DexTheme.data(c, size: 10)),
                    const Spacer(),
                    Text(clock(duration), style: DexTheme.data(c, size: 10)),
                  ],
                ),
                const SizedBox(height: DexSpace.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _Transport(
                      icon: DexIcons.previous,
                      label: 'Previous track',
                      enabled: _available,
                      onPressed: () => onAction(MediaAction.previous),
                      colors: c,
                    ),
                    const SizedBox(width: DexSpace.md),
                    // The reference's round play/pause: the one filled control
                    // in the card, so it is the one you reach for.
                    Semantics(
                      button: true,
                      label: _playing ? 'Pause' : 'Play',
                      child: InkWell(
                        onTap: () => onAction(MediaAction.playPause),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: DexHit.comfortable,
                          height: DexHit.comfortable,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: glass.fillStrong,
                          ),
                          child: Icon(
                            _playing ? DexIcons.pause : DexIcons.play,
                            size: 16,
                            color: c.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DexSpace.md),
                    _Transport(
                      icon: DexIcons.next,
                      label: 'Next track',
                      enabled: _available,
                      onPressed: () => onAction(MediaAction.next),
                      colors: c,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// A small mono chip, the way every card's right-hand header slot is set.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.colors, this.tint});

  final String text;
  final DexColors colors;

  /// Coloured chips carry a state: amber for "n new", nothing for a label.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.20) ?? glass.fill,
        borderRadius: BorderRadius.circular(
          tint == null ? DexRadius.control : DexRadius.pill,
        ),
      ),
      child: Text(
        text,
        style: DexTheme.data(colors, size: 9, color: tint ?? colors.muted),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.media, required this.colors});

  final MediaState media;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    const double size = 48;
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.control),
      ),
      child: Icon(DexIcons.music, size: 20, color: colors.muted),
    );
    final List<int>? art = media.artwork;
    if (art == null || art.isEmpty) {
      return fallback;
    }
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

class _Transport extends StatelessWidget {
  const _Transport({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(DexRadius.control),
          child: SizedBox(
            width: DexHit.comfortable,
            height: DexHit.comfortable,
            child: Icon(
              icon,
              size: 17,
              color: enabled
                  ? colors.muted
                  : colors.muted.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Desk mode — what the phone is doing as a machine.
///
/// Battery with its gauge, then the two radios that matter to a desk — the
/// network and the link — as tiles, then a door to the control centre. The
/// column used to draw three tiny radio glyphs and a latency figure here;
/// none of it said what the phone was connected *to*.
///
/// Every value that the phone has not reported renders as a dash. A meter
/// showing a made-up number is worse than no meter.
class PhoneWidget extends StatelessWidget {
  const PhoneWidget({
    required this.telemetry,
    this.device,
    this.recessive = false,
    this.onOpenControls,
    super.key,
  });

  final DeviceTelemetry telemetry;
  final DeviceSummary? device;
  final bool recessive;
  final VoidCallback? onOpenControls;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final int? pct = telemetry.batteryPercentage;
    final bool low = (pct ?? 100) <= 15 && !telemetry.charging;
    final Color gauge = low ? c.fault : c.signal;

    final String? identity = device == null
        ? null
        : <String>[
            (device!.model ?? device!.name).toUpperCase(),
            if (device!.androidVersion case final String v) 'ANDROID $v',
          ].join(' \u00b7 ');

    final String network = switch (telemetry.wifiEnabled) {
      true => 'Connected',
      false => 'Off',
      null => '—',
    };
    final String transport = switch (device?.connectionKind) {
      DeviceConnectionKind.usb => 'USB High-Speed',
      DeviceConnectionKind.wifi => 'Wi-Fi',
      null => '—',
    };

    return DeskCard(
      label: 'Desk mode',
      icon: DexIcons.portrait,
      iconColor: c.trace,
      recessive: recessive,
      onTap: onOpenControls,
      trailing: identity == null
          ? null
          : Text(
              identity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: DexTheme.data(c, size: 9),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                telemetry.charging ? DexIcons.batteryCharging : DexIcons.battery,
                size: 14,
                color: gauge,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Battery',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(color: c.text),
                ),
              ),
              const SizedBox(width: DexSpace.sm),
              // One shrinkable reading rather than two loose texts: beside a
              // Spacer, neither could give ground, and under a fallback face
              // "(Fast charging)" alone ran past the card. Weighted 3:1 so the
              // reading, which is the longer of the two, gets the room.
              Flexible(
                flex: 3,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: pct == null ? '—' : '$pct%',
                        style: DexTheme.data(
                          c,
                          size: 11,
                          color: c.text,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (telemetry.charging)
                        TextSpan(
                          text: ' (Fast charging)',
                          style: DexTheme.data(c, size: 11, color: c.signal),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(DexRadius.pill),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: glass.fill)),
                  if (pct != null)
                    FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: ColoredBox(color: gauge),
                    ),
                ],
              ),
            ),
          ),
          Container(
            height: DexStroke.hairline,
            margin: const EdgeInsets.symmetric(vertical: DexSpace.md),
            color: glass.stroke,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _Tile(
                  icon: DexIcons.wifi,
                  tint: c.trace,
                  label: 'Wi-Fi',
                  value: network,
                  colors: c,
                ),
              ),
              const SizedBox(width: DexSpace.sm),
              Expanded(
                child: _Tile(
                  icon: DexIcons.check,
                  tint: c.signal,
                  label: 'Link Transport',
                  value: transport,
                  colors: c,
                ),
              ),
            ],
          ),
          if (onOpenControls != null) ...<Widget>[
            const SizedBox(height: DexSpace.sm),
            _Door('Open quick settings', colors: c),
          ],
        ],
      ),
    );
  }
}

/// A labelled readout tile: a tinted icon, what it is, what it says.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: DexSpace.sm),
      decoration: BoxDecoration(
        color: glass.fillSubtle,
        borderRadius: BorderRadius.circular(DexRadius.control),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A right-aligned "go there" affordance, in mono, with a chevron rather than
/// an arrow: the bundled faces have no glyph for the arrow.
class _Door extends StatelessWidget {
  const _Door(this.text, {required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(text, style: DexTheme.data(colors, size: 10)),
        const SizedBox(width: 2),
        Icon(DexIcons.forward, size: 12, color: colors.muted),
      ],
    );
  }
}

/// Recent notifications, trimmed to what fits a widget.
class NotificationsWidget extends StatelessWidget {
  const NotificationsWidget({
    required this.notifications,
    required this.status,
    required this.now,
    this.recessive = false,
    this.onOpen,
    super.key,
  });

  final List<NotificationItem> notifications;
  final LoadStatus status;
  final DateTime now;
  final bool recessive;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final List<NotificationItem> ordered = notifications.toList()
      ..sort(
        (NotificationItem a, NotificationItem b) =>
            b.timestamp.compareTo(a.timestamp),
      );
    final List<NotificationItem> shown = ordered.take(3).toList();

    return DeskCard(
      label: 'Notifications',
      icon: DexIcons.notifications,
      iconColor: c.warn,
      recessive: recessive,
      onTap: onOpen,
      trailing: ordered.isEmpty
          ? null
          : _Chip('${ordered.length} new', colors: c, tint: c.warn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (status == LoadStatus.unavailable)
            Text(
              'Allow notification access on the phone.',
              style: t.bodySmall?.copyWith(color: c.muted),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DexSpace.md),
              child: Center(
                child: Text(
                  'Nothing new.',
                  style: t.bodySmall?.copyWith(color: c.muted),
                ),
              ),
            )
          else
            for (int i = 0; i < shown.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : DexSpace.sm),
                child: Container(
                  padding: const EdgeInsets.all(DexSpace.sm),
                  decoration: BoxDecoration(
                    color: glass.fillSubtle,
                    borderRadius: BorderRadius.circular(DexRadius.control),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              shown[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelMedium?.copyWith(color: c.text),
                            ),
                          ),
                          const SizedBox(width: DexSpace.sm),
                          Text(
                            relativeAge(shown[i].timestamp, now),
                            style: DexTheme.data(c, size: 9),
                          ),
                        ],
                      ),
                      Text(
                        shown[i].body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelSmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
          if (onOpen != null) ...<Widget>[
            const SizedBox(height: DexSpace.sm),
            _Door('View notification shade', colors: c),
          ],
        ],
      ),
    );
  }
}
