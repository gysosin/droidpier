import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
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

  static (String, IconData) _describe(DeviceControl c) => switch (c) {
    DeviceControl.wifi => ('Wi-Fi', Icons.wifi),
    DeviceControl.bluetooth => ('Bluetooth', Icons.bluetooth),
    DeviceControl.airplaneMode => ('Airplane mode', Icons.airplanemode_active),
    DeviceControl.rotationLock => ('Rotation lock', Icons.screen_lock_rotation),
    DeviceControl.torch => ('Torch', Icons.flashlight_on),
    DeviceControl.mobileData => ('Mobile data', Icons.signal_cellular_alt),
    DeviceControl.location => ('Location', Icons.location_on),
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final List<MapEntry<String, VolumeLevel>> volumes =
        telemetry.volume.entries.toList()..sort(
          (MapEntry<String, VolumeLevel> a, MapEntry<String, VolumeLevel> b) =>
              a.key.compareTo(b.key),
        );

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
            Wrap(
              spacing: DexSpace.md,
              runSpacing: DexSpace.md,
              children: <Widget>[
                for (final DeviceControl control in gridControls)
                  _CircleToggle(
                    control: control,
                    value: _valueOf(control),
                    lockedReason: _lockedReason(control),
                    lockedDetail: _lockedDetail(control),
                    onToggle: onToggleControl,
                  ),
              ],
            ),
            if (volumes.isNotEmpty) ...<Widget>[
              const SizedBox(height: DexSpace.md),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Shared clipboard', style: t.labelLarge),
                      Text(
                        switch (clipboard.kind) {
                          ClipboardKind.empty => 'Nothing copied yet',
                          ClipboardKind.text => clipboard.text ?? '',
                          ClipboardKind.image => 'An image is ready to paste',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DexTheme.data(c, size: 11),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  toggled: clipboard.syncEnabled,
                  label: 'Share clipboard between phone and desk',
                  child: Switch(
                    value: clipboard.syncEnabled,
                    onChanged: onToggleClipboardSync,
                    activeThumbColor: c.signal,
                  ),
                ),
              ],
            ),
            if (onManagePhones != null ||
                onOpenPermissions != null ||
                onOpenSettings != null) ...<Widget>[
              const SizedBox(height: DexSpace.sm),
              Divider(color: c.line, height: DexStroke.hairline),
              const SizedBox(height: DexSpace.sm),
              // Without this the phone list is reachable only from the boot
              // screen, so adding a second phone means disconnecting the first.
              if (onManagePhones != null)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onManagePhones,
                    style: TextButton.styleFrom(
                      foregroundColor: c.text,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(0, DexHit.comfortable),
                    ),
                    child: const Text('Phones…'),
                  ),
                ),
              if (onOpenSettings != null)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: c.text,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(0, DexHit.comfortable),
                    ),
                    child: const Text('Settings…'),
                  ),
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
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            height: 60,
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.sm,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              color: on ? c.signal.withValues(alpha: 0.9) : c.raised,
              borderRadius: BorderRadius.circular(24),
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
                        ? Colors.white
                        : c.surface.withValues(alpha: 0.6),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: !known
                        ? c.muted.withValues(alpha: 0.4)
                        : on
                        ? c.signal
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: on ? Colors.white : c.text,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DexTheme.data(
                          c,
                          size: 10,
                          color: on
                              ? Colors.white.withValues(alpha: 0.8)
                              : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked != null)
                  Icon(Icons.lock_outline, size: 12, color: on ? Colors.white : c.muted),
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
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                onTap: usable ? () => onToggle(control, !on) : null,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: DexDuration.micro,
                  curve: DexMotion.arrive,
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? Colors.white : c.raised,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: !usable
                        ? c.muted.withValues(alpha: 0.4)
                        : on
                        ? const Color(0xFF14171C)
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
            width: 58,
            child: Text(stream, style: DexTheme.data(colors, size: 11)),
          ),
          Expanded(
            child: Semantics(
              label: '$stream volume',
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
        ],
      ),
    );
  }
}

/// One line explaining why the whole panel cannot act right now.
class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.sm,
        vertical: DexSpace.sm,
      ),
      decoration: BoxDecoration(
        color: colors.fault.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(
          color: colors.fault.withValues(alpha: 0.5),
          width: DexStroke.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 14, color: colors.fault),
          const SizedBox(width: DexSpace.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.text, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
