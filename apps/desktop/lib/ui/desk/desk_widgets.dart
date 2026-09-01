import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../util/relative_time.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'analog_clock.dart';
import 'desk_card.dart';

/// Clock. The largest type on the desk, because a glance is the whole job.
class ClockWidget extends StatelessWidget {
  const ClockWidget({required this.now, this.recessive = false, super.key});

  final DateTime now;
  final bool recessive;

  static const List<String> _days = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;

    // A prominent drawn analog face filling a tall card, with the day and date
    // beneath it — a large clock, not a small dial. The digital time still
    // lives in the taskbar tray.
    return DeskCard(
      label: 'Clock',
      size: DeskCardSize.feature,
      recessive: recessive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: AnalogClock(now: now),
              ),
            ),
          ),
          const SizedBox(height: DexSpace.md),
          Text(
            _days[now.weekday - 1],
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: c.text,
            ),
          ),
          Text(
            '${_months[now.month - 1]} ${now.day}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return DeskCard(
      label: 'Now playing',
      size: DeskCardSize.medium,
      recessive: recessive,
      child: Row(
        children: <Widget>[
          _Artwork(media: media, colors: c),
          const SizedBox(width: DexSpace.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SwapText(
                  media.title ?? 'Nothing playing',
                  style: (t.bodyLarge ?? const TextStyle()).copyWith(
                    color: _available ? c.text : c.muted,
                  ),
                ),
                if (media.artist != null)
                  SwapText(
                    media.artist!,
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: c.muted,
                    ),
                  ),
                const SizedBox(height: DexSpace.sm),
                Row(
                  children: <Widget>[
                    _Transport(
                      icon: Icons.skip_previous,
                      label: 'Previous track',
                      enabled: _available,
                      onPressed: () => onAction(MediaAction.previous),
                      colors: c,
                    ),
                    _Transport(
                      icon: _playing ? Icons.pause : Icons.play_arrow,
                      label: _playing ? 'Pause' : 'Play',
                      enabled: _available,
                      accent: true,
                      onPressed: () => onAction(MediaAction.playPause),
                      colors: c,
                    ),
                    _Transport(
                      icon: Icons.skip_next,
                      label: 'Next track',
                      enabled: _available,
                      onPressed: () => onAction(MediaAction.next),
                      colors: c,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    const double size = 64;
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.card),
      ),
      child: Icon(Icons.music_note, size: 22, color: colors.muted),
    );
    final List<int>? art = media.artwork;
    if (art == null || art.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DexRadius.card),
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
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final DexColors colors;
  final bool accent;

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
              color: !enabled
                  ? colors.muted.withValues(alpha: 0.5)
                  : accent
                  ? colors.signal
                  : colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Desk mode — what the phone is doing as a machine.
///
/// The full widget shows battery, memory, CPU and storage as labelled meters
/// with a device identity line beneath. `DeviceTelemetry` carries only battery
/// today, so the other three are omitted rather than faked: a meter showing a
/// made-up number is worse than no meter. Adding them needs the facade to
/// carry them first — see `docs/ARCHITECTURE.md`.
class PhoneWidget extends StatelessWidget {
  const PhoneWidget({
    required this.telemetry,
    this.device,
    this.recessive = false,
    super.key,
  });

  final DeviceTelemetry telemetry;
  final DeviceSummary? device;
  final bool recessive;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final int? pct = telemetry.batteryPercentage;
    final bool low = (pct ?? 100) <= 15 && !telemetry.charging;

    return DeskCard(
      label: 'Desk mode',
      size: DeskCardSize.medium,
      recessive: recessive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _Meter(
            label: 'Battery',
            value: pct == null ? null : pct / 100,
            reading: pct == null
                ? '—'
                : '$pct%${telemetry.charging ? ' · charging' : ''}',
            colors: c,
            alarming: low,
          ),
          const SizedBox(height: DexSpace.sm),
          Row(
            children: <Widget>[
              _Radio(on: telemetry.wifiEnabled, icon: Icons.wifi, colors: c),
              const SizedBox(width: DexSpace.md),
              _Radio(
                on: telemetry.bluetoothEnabled,
                icon: Icons.bluetooth,
                colors: c,
              ),
              const SizedBox(width: DexSpace.md),
              _Radio(
                on: telemetry.airplaneMode,
                icon: Icons.airplanemode_active,
                colors: c,
              ),
              const Spacer(),
              if (telemetry.linkLatency != null)
                Text(
                  '${telemetry.linkLatency!.value.round()} ms',
                  style: DexTheme.data(c, size: 10),
                ),
            ],
          ),
          if (device != null) ...<Widget>[
            const SizedBox(height: DexSpace.sm),
            Text(
              <String>[
                device!.name,
                if (device!.androidVersion != null)
                  'Android ${device!.androidVersion}',
                device!.connectionKind == DeviceConnectionKind.usb
                    ? 'USB'
                    : 'Wi-Fi',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DexTheme.data(c, size: 10),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled meter. A null value renders the track without a fill and reads
/// "—", because a meter that invents a number is worse than an empty one.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.reading,
    required this.colors,
    this.alarming = false,
  });

  final String label;
  final double? value;
  final String reading;
  final DexColors colors;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final Color tint = alarming ? colors.fault : colors.signal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text(reading, style: DexTheme.data(colors, size: 10)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(DexRadius.pill),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: ColoredBox(color: colors.line)),
                if (value != null)
                  FractionallySizedBox(
                    widthFactor: value!.clamp(0.0, 1.0),
                    child: ColoredBox(color: tint),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A radio's state. Null — the phone never said — is drawn faintest, so the
/// widget never claims a radio is off when it simply does not know.
class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.icon, required this.colors});

  final bool? on;
  final IconData icon;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: 15,
      color: on == null
          ? colors.muted.withValues(alpha: 0.35)
          : on!
          ? colors.signal
          : colors.muted,
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
    super.key,
  });

  final List<NotificationItem> notifications;
  final LoadStatus status;
  final DateTime now;
  final bool recessive;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final List<NotificationItem> ordered = notifications.toList()
      ..sort(
        (NotificationItem a, NotificationItem b) =>
            b.timestamp.compareTo(a.timestamp),
      );
    final List<NotificationItem> shown = ordered.take(3).toList();

    return DeskCard(
      label: 'Notifications',
      size: DeskCardSize.medium,
      recessive: recessive,
      trailing: ordered.isEmpty
          ? null
          : Text('${ordered.length}', style: DexTheme.data(c, size: 10)),
      child: status == LoadStatus.unavailable
          ? Text(
              'Allow notification access on the phone.',
              style: t.bodyMedium?.copyWith(color: c.muted),
            )
          : shown.isEmpty
          ? Text('Nothing new.', style: t.bodyMedium?.copyWith(color: c.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final NotificationItem n in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DexSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 3,
                          height: 26,
                          margin: const EdgeInsets.only(
                            right: DexSpace.sm,
                            top: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.signal.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(DexRadius.pill),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      n.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.labelLarge,
                                    ),
                                  ),
                                  Text(
                                    relativeAge(n.timestamp, now),
                                    style: DexTheme.data(c, size: 9),
                                  ),
                                ],
                              ),
                              Text(
                                n.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(
                                  color: c.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
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
