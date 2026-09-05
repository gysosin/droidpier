import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import 'volume_labels.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// Control centre.
///
/// Every control that changes the phone rather than the desk lives here, opened
/// from the menu bar — the place a desktop user already reaches for radios and
/// volume. It exists because the desk widgets report state and do not change
/// it: a widget you can accidentally toggle while glancing at it is worse than
/// one that stays still.
class ControlCenter extends StatelessWidget {
  const ControlCenter({
    required this.telemetry,
    required this.clipboard,
    required this.onToggleControl,
    required this.onToggleClipboardSync,
    required this.onSetVolume,
    this.onManagePhones,
    this.onOpenPermissions,
    this.onOpenSettings,
    this.connectionKind,
    this.agentStatus = AgentConnectionStatus.connected,
    super.key,
  });

  final DeviceTelemetry telemetry;
  final ClipboardState clipboard;

  /// How the selected phone is attached, or null when none is selected.
  ///
  /// It is here because one control depends on it: turning Wi-Fi off over a
  /// Wi-Fi transport cuts the link that carried the command. The backend
  /// rejects that action on its own — this is the UI half, so the person is
  /// told before they press rather than after it fails.
  final DeviceConnectionKind? connectionKind;

  /// Whether the on-device agent — which is what actually runs these commands —
  /// is connected. Without it every toggle fails with a generic message after
  /// the person has already pressed it; with it we can say so beforehand.
  final AgentConnectionStatus agentStatus;
  final void Function(DeviceControl control, bool enabled) onToggleControl;
  final ValueChanged<bool> onToggleClipboardSync;
  final void Function(String stream, int value) onSetVolume;

  /// Opens the phone list. Null hides the row.
  final VoidCallback? onManagePhones;

  /// Opens the capability list. Null hides the row.
  final VoidCallback? onOpenPermissions;

  /// Opens the desk's own settings. Null hides the row.
  final VoidCallback? onOpenSettings;

  bool? _valueOf(DeviceControl c) => switch (c) {
    DeviceControl.wifi => telemetry.wifiEnabled,
    DeviceControl.bluetooth => telemetry.bluetoothEnabled,
    DeviceControl.airplaneMode => telemetry.airplaneMode,
    DeviceControl.rotationLock => telemetry.rotationLocked,
    DeviceControl.torch => telemetry.torchEnabled,
    DeviceControl.mobileData => telemetry.mobileDataEnabled,
    DeviceControl.location => telemetry.locationEnabled,
  };

  /// Why a control that the phone *does* support still cannot be used.
  ///
  /// Distinct from an unreported capability: this one exists and works, and is
  /// held back by the transport the person chose.
  /// Said once at the top of the panel rather than repeated on every control.
  String? get _agentNotice => switch (agentStatus) {
    AgentConnectionStatus.connected => null,
    AgentConnectionStatus.starting =>
      'The phone is still connecting. These controls will work once it '
          'finishes.',
    AgentConnectionStatus.reconnecting =>
      'Reconnecting to the phone. These controls will work once the link is '
          'back.',
    AgentConnectionStatus.unavailable =>
      'The phone is not connected, so these controls cannot reach it.',
  };

  String? _lockedReason(DeviceControl c) {
    // Ordered by what the person can do about it. The agent being down blocks
    // every control, so it is checked first — telling someone that Wi-Fi is
    // pinned by their transport is noise when nothing works at all.
    final String? agent = switch (agentStatus) {
      AgentConnectionStatus.connected => null,
      AgentConnectionStatus.starting => 'The phone is still connecting',
      AgentConnectionStatus.reconnecting => 'Reconnecting to the phone',
      AgentConnectionStatus.unavailable => 'The phone is not connected',
    };
    if (agent != null) return agent;

    if (c == DeviceControl.wifi &&
        connectionKind == DeviceConnectionKind.wifi) {
      return 'Wi-Fi must stay on for wireless debugging';
    }
    return null;
  }

  /// The same cause, said at length. The short form names the reason for a
  /// screen reader and the spoken label; this one has room to say what would
  /// happen, which is what a person hovering actually wants to know.
  String? _lockedDetail(DeviceControl c) {
    final String? reason = _lockedReason(c);
    if (reason == null) return null;
    if (c == DeviceControl.wifi &&
        connectionKind == DeviceConnectionKind.wifi &&
        agentStatus == AgentConnectionStatus.connected) {
      return '$reason. This phone is connected over Wi-Fi, so turning it off '
          'would cut the link.';
    }
    return reason;
  }

  /// Whether the clipboard switch may be operated at all.
  ///
  /// Three things have to be true, and none of them is "the person wants it":
  /// the session is up, the agent that would carry the text is connected, and
  /// the phone has reported that it can share a clipboard. Until then the
  /// switch is disabled with the reason on screen, rather than being live and
  /// failing after it is pressed.
  bool get _clipboardUsable =>
      agentStatus == AgentConnectionStatus.connected &&
      clipboard.availability == ClipboardAvailability.available;

  static (String, IconData) _describe(DeviceControl c) => switch (c) {
    DeviceControl.wifi => ('Wi-Fi', DexIcons.wifi),
    DeviceControl.bluetooth => ('Bluetooth', DexIcons.bluetooth),
    // "Airplane mode" does not fit the tile and rendered as "Airplane mo…".
    // A truncated label reads as a rendering fault; the shorter word is
    // unambiguous next to the aeroplane icon.
    DeviceControl.airplaneMode => ('Airplane', DexIcons.airplane),
    DeviceControl.rotationLock => ('Rotation', DexIcons.rotationLock),
    DeviceControl.torch => ('Torch', DexIcons.torch),
    DeviceControl.mobileData => ('Data', DexIcons.cellular),
    DeviceControl.location => ('Location', DexIcons.location),
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    // Not alphabetical. Sorting by key put "alarm" above "music", which is
    // correct alphabetically and wrong in every other sense.
    final List<String> keys = sortVolumeStreams(telemetry.volume.keys);
    final List<MapEntry<String, VolumeLevel>> volumes =
        <MapEntry<String, VolumeLevel>>[
          for (final String k in keys)
            if (telemetry.volume[k] case final VolumeLevel v)
              MapEntry<String, VolumeLevel>(k, v),
        ];

    // Wi-Fi and Bluetooth ride the two wide pills at the top, as the reference
    // has it; the rest are circular toggles in a grid below.
    const List<DeviceControl> pillControls = <DeviceControl>[
      DeviceControl.wifi,
      DeviceControl.bluetooth,
    ];
    final List<DeviceControl> gridControls = DeviceControl.values
        .where((DeviceControl c) => !pillControls.contains(c))
        .toList();

    return SizedBox(
      width: 372,
      child: GlassPanel(
        radius: DexRadius.dialog,
        fill: DexGlass.of(context).substrate,
        padding: const EdgeInsets.all(DexSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_agentNotice != null) ...<Widget>[
              _Banner(text: _agentNotice!, colors: c),
              const SizedBox(height: DexSpace.md),
            ],
            Row(
              children: <Widget>[
                for (final DeviceControl control in pillControls) ...<Widget>[
                  if (control != pillControls.first)
                    const SizedBox(width: DexSpace.sm),
                  Expanded(
                    child: _WidePill(
                      control: control,
                      value: _valueOf(control),
                      lockedReason: _lockedReason(control),
                      lockedDetail: _lockedDetail(control),
                      onToggle: onToggleControl,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: DexSpace.md),
            // One row, five across, as the reference lays them: a Wrap put
            // the fifth toggle on a line of its own.
            Row(
              children: <Widget>[
                for (final DeviceControl control in gridControls)
                  Expanded(
                    child: _CircleToggle(
                      control: control,
                      value: _valueOf(control),
                      lockedReason: _lockedReason(control),
                      lockedDetail: _lockedDetail(control),
                      onToggle: onToggleControl,
                    ),
                  ),
              ],
            ),
            if (volumes.isNotEmpty) ...<Widget>[
              const SizedBox(height: DexSpace.md),
              Text(
                'PHONE VOLUME LEVELS',
                style: DexTheme.data(c, size: 10).copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: DexSpace.sm),
              for (final MapEntry<String, VolumeLevel> v in volumes)
                _Volume(
                  stream: v.key,
                  level: v.value,
                  onChanged: (int value) => onSetVolume(v.key, value),
                  colors: c,
                ),
            ],
            const SizedBox(height: DexSpace.sm),
            Text(
              'Some controls may be restricted by Android.',
              style: DexTheme.data(c, size: 10),
            ),
            const SizedBox(height: DexSpace.md),
            Divider(color: c.line, height: DexStroke.hairline),
            const SizedBox(height: DexSpace.md),
            _Clipboard(
              clipboard: clipboard,
              usable: _clipboardUsable,
              onToggle: onToggleClipboardSync,
              colors: c,
            ),
            if (onManagePhones != null ||
                onOpenPermissions != null ||
                onOpenSettings != null) ...<Widget>[
              const SizedBox(height: DexSpace.sm),
              Divider(color: c.line, height: DexStroke.hairline),
              const SizedBox(height: DexSpace.sm),
              // Without this the phone list is reachable only from the boot
              // screen, so adding a second phone means disconnecting the first.
              Row(
                children: <Widget>[
                  if (onManagePhones != null)
                    Flexible(
                      child: TextButton.icon(
                        onPressed: onManagePhones,
                        style: TextButton.styleFrom(
                          foregroundColor: c.text,
                          minimumSize: const Size(0, DexHit.comfortable),
                        ),
                        icon: Icon(
                          DexIcons.portrait,
                          size: 14,
                          color: c.signal,
                        ),
                        label: const Text(
                          'Manage Phones…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (onOpenSettings != null)
                    Flexible(
                      child: TextButton.icon(
                        onPressed: onOpenSettings,
                        style: TextButton.styleFrom(
                          foregroundColor: c.text,
                          minimumSize: const Size(0, DexHit.comfortable),
                        ),
                        icon: Icon(
                          DexIcons.slidersHorizontal,
                          size: 14,
                          color: c.muted,
                        ),
                        label: const Text(
                          'Desk Settings…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
              if (onOpenPermissions != null)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onOpenPermissions,
                    style: TextButton.styleFrom(
                      foregroundColor: c.text,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(0, DexHit.comfortable),
                    ),
                    child: const Text('What the desk can use…'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WidePill extends StatelessWidget {
  const _WidePill({
    required this.control,
    required this.value,
    required this.lockedReason,
    required this.lockedDetail,
    required this.onToggle,
  });

  final DeviceControl control;
  final bool? value;
  final String? lockedReason;
  final String? lockedDetail;
  final void Function(DeviceControl control, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final (String label, IconData icon) = ControlCenter._describe(control);
    final bool known = value != null;
    final bool on = value ?? false;
    final String? locked = lockedReason;
    final bool usable = known && locked == null;
    final String sub = !known
        ? 'Unavailable'
        : locked != null
        ? 'Restricted'
        : on
        ? 'On'
        : 'Off';

    return Semantics(
      toggled: on,
      enabled: usable,
      button: true,
      label: switch ((known, locked)) {
        (false, _) => '$label, not available on this phone',
        (true, final String reason?) => '$label, unavailable: $reason',
        (true, null) => '$label, $sub',
      },
      child: Tooltip(
        message: switch ((known, locked)) {
          (false, _) => '$label is not available on this phone',
          (true, final String _?) => lockedDetail ?? label,
          (true, null) => label,
        },
        child: InkWell(
          onTap: usable ? () => onToggle(control, !on) : null,
          borderRadius: BorderRadius.circular(DexRadius.panel),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            height: 60,
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.sm,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              // A slate pill either way; the state lives in the icon's disc,
              // as the reference draws it — trace for the radio that carries
              // the link, signal for the rest.
              color: on ? glass.fillStrong : glass.fill,
              borderRadius: BorderRadius.circular(DexRadius.panel),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? (control == DeviceControl.wifi ? c.trace : c.signal)
                        : c.surface.withValues(alpha: 0.6),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: !known
                        ? c.muted.withValues(alpha: 0.4)
                        : on
                        ? c.bg
                        : c.muted,
                  ),
                ),
                const SizedBox(width: DexSpace.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: c.text),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DexTheme.data(c, size: 10),
                      ),
                    ],
                  ),
                ),
                if (locked != null)
                  Icon(DexIcons.locked, size: 12, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular quick-settings toggle with its label beneath, as controller_1 has
/// them. A disabled control (no backend, or held by the transport) is dimmed.
class _CircleToggle extends StatelessWidget {
  const _CircleToggle({
    required this.control,
    required this.value,
    required this.lockedReason,
    required this.lockedDetail,
    required this.onToggle,
  });

  final DeviceControl control;
  final bool? value;
  final String? lockedReason;
  final String? lockedDetail;
  final void Function(DeviceControl control, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final (String label, IconData icon) = ControlCenter._describe(control);
    final bool known = value != null;
    final bool on = value ?? false;
    final String? locked = lockedReason;
    final bool usable = known && locked == null;

    return Semantics(
      toggled: on,
      enabled: usable,
      button: true,
      label: switch ((known, locked)) {
        (false, _) => '$label, not available on this phone',
        (true, final String reason?) => '$label, unavailable: $reason',
        (true, null) => label,
      },
      child: Tooltip(
        message: switch ((known, locked)) {
          (false, _) => '$label is not available on this phone',
          (true, final String _?) => lockedDetail ?? label,
          (true, null) => label,
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InkWell(
              onTap: usable ? () => onToggle(control, !on) : null,
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: DexDuration.micro,
                curve: DexMotion.arrive,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? (control == DeviceControl.mobileData
                            ? c.trace
                            : c.signal)
                      : c.raised,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: !usable
                      ? c.muted.withValues(alpha: 0.4)
                      : on
                      ? c.bg
                      : c.text,
                ),
              ),
            ),
            const SizedBox(height: DexSpace.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: usable ? c.text : c.muted.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({
    required this.stream,
    required this.level,
    required this.onChanged,
    required this.colors,
  });

  final String stream;
  final VolumeLevel level;
  final ValueChanged<int> onChanged;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final double max = level.maximum <= 0 ? 1 : level.maximum.toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            // 92, not 58: 58 fitted "music" and "ring" because those were the
            // raw keys. "Notifications" is the longest real label and needs
            // the room, and a fixed width keeps every slider starting on the
            // same line rather than stepping in and out with the text.
            width: 92,
            child: Text(
              volumeStreamLabel(stream),
              style: DexTheme.data(colors, size: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Semantics(
              label: '${volumeStreamLabel(stream)} volume',
              child: Slider(
                value: level.current.clamp(0, level.maximum).toDouble(),
                max: max,
                divisions: level.maximum > 0 ? level.maximum : null,
                activeColor: colors.signal,
                inactiveColor: colors.line,
                onChanged: (double v) => onChanged(v.round()),
              ),
            ),
          ),
          // The number, tabular so the three rows stay in column as they move.
          // A slider says roughly; a person setting a phone's volume from a
          // desk wants to know it is the same 68 it was yesterday.
          SizedBox(
            width: 34,
            child: Text(
              '${(level.current / max * 100).round()}%',
              textAlign: TextAlign.right,
              style: DexTheme.data(colors, size: 11, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line explaining why the whole panel cannot act right now.
///
/// [calm] drops the fault colouring for the cases that are not faults — a
/// capability the phone has not reported yet is a state, not a failure, and
/// painting it red teaches people to ignore red.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.colors,
    this.calm = false,
    this.action,
  });

  final String text;
  final DexColors colors;
  final bool calm;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final Color tint = calm ? colors.muted : colors.fault;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.sm,
        vertical: DexSpace.sm,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: calm ? 0.10 : 0.16),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(
          color: tint.withValues(alpha: 0.5),
          width: DexStroke.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(DexIcons.info, size: 14, color: tint),
          const SizedBox(width: DexSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.text, height: 1.35),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: DexSpace.xs),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared clipboard: an opt-in, and the reasons it may not be one yet.
///
/// The switch is off by default and stays off until the person turns it on,
/// because turning it on is what lets the desk read what is on the phone. It
/// is *disabled* until the link is up and the phone has said it can share at
/// all — a live switch that fails when pressed is worse than a dead one that
/// says why.
///
/// Everything it has to say, it says here and keeps saying. None of these
/// states raises a snackbar: they persist for as long as they are true, so a
/// paused sync is visible when the person next opens this panel rather than
/// only in the second the toast appeared.
class _Clipboard extends StatelessWidget {
  const _Clipboard({
    required this.clipboard,
    required this.usable,
    required this.onToggle,
    required this.colors,
  });

  final ClipboardState clipboard;
  final bool usable;
  final ValueChanged<bool> onToggle;
  final DexColors colors;

  /// Sharing is possible and switched on, but the phone reported a problem
  /// with it. The switch stays where the person left it; the notice offers the
  /// one action that resolves it.
  bool get _paused =>
      clipboard.availability == ClipboardAvailability.available &&
      clipboard.message != null;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    final String state = switch (clipboard.availability) {
      ClipboardAvailability.unavailable => 'Not available on this phone',
      ClipboardAvailability.unknown => 'Waiting for the phone',
      // Paused outranks off: the backend can switch sync off itself when it
      // breaks, and reporting only "Off" would hide the reason it went off.
      ClipboardAvailability.available when _paused => 'Paused',
      ClipboardAvailability.available when !clipboard.syncEnabled =>
        'Off — nothing is read from the phone',
      ClipboardAvailability.available => switch (clipboard.kind) {
        ClipboardKind.empty => 'On — nothing copied yet',
        // The text itself is not the state. It used to be both, so a long
        // clipboard pushed out the one line that said whether sharing was
        // even on.
        ClipboardKind.text => 'On — sharing with the phone',
        ClipboardKind.image => 'On — an image is ready to paste',
      },
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Shared clipboard', style: t.labelLarge),
                  Text(
                    state,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DexTheme.data(colors, size: 11),
                  ),
                ],
              ),
            ),
            Semantics(
              toggled: clipboard.syncEnabled,
              enabled: usable,
              label: 'Share clipboard between phone and desk',
              child: Switch(
                value: clipboard.syncEnabled,
                onChanged: usable ? onToggle : null,
                activeThumbColor: colors.signal,
              ),
            ),
          ],
        ),
        // What is actually on the clipboard, in machine type, in its own well.
        // A person checking the bridge works wants to see the thing that
        // crossed it.
        if (clipboard.availability == ClipboardAvailability.available &&
            clipboard.syncEnabled &&
            clipboard.kind == ClipboardKind.text &&
            (clipboard.text?.isNotEmpty ?? false)) ...<Widget>[
          const SizedBox(height: DexSpace.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.md,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(DexRadius.control),
            ),
            child: Text(
              clipboard.text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DexTheme.data(colors, size: 10, color: colors.text),
            ),
          ),
        ],
        if (_notice case final String notice) ...<Widget>[
          const SizedBox(height: DexSpace.sm),
          _Banner(
            text: notice,
            colors: colors,
            calm: clipboard.availability != ClipboardAvailability.unavailable,
            action: _paused && usable
                ? TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, DexHit.minimum),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DexSpace.sm,
                      ),
                    ),
                    // Turning it on again is the retry: there is no separate
                    // command, and inventing one would be a button that lies.
                    onPressed: () => onToggle(true),
                    child: const Text('Retry'),
                  )
                : null,
          ),
        ],
      ],
    );
  }

  /// The persistent explanation, or null when there is nothing to explain.
  String? get _notice => switch (clipboard.availability) {
    ClipboardAvailability.unknown =>
      clipboard.message ??
          'This phone has not said whether it can share a clipboard yet. The '
              'switch turns on once it does.',
    ClipboardAvailability.unavailable =>
      clipboard.message ??
          'This phone will not share its clipboard, so the desk cannot read '
              'or set it.',
    ClipboardAvailability.available =>
      clipboard.message == null
          ? null
          : 'Clipboard sharing is paused. ${clipboard.message}',
  };
}
