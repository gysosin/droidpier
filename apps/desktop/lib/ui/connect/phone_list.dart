import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'connection_parts.dart';

/// The phones ADB can actually see, and the choice of which one to open.
///
/// Serials are machine values, so they are set in mono; everything a person
/// reads is set in body. Every state the contract can produce is handled —
/// loading, empty, unavailable, error, ready — and none of them is a dead end.
///
/// This list is *transports*, not advertisements. Anything on it has been
/// accepted by ADB; a phone merely broadcasting on the network appears in the
/// nearby panel instead, and never here.
class PhoneList extends StatelessWidget {
  const PhoneList({
    required this.status,
    required this.devices,
    required this.selectedId,
    required this.onSelect,
    required this.onRefresh,
    required this.onConnect,
    this.onDisconnect,
    this.busy = false,
    this.busyDeviceId,
    super.key,
  });

  final LoadStatus status;
  final List<DeviceSummary> devices;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;

  /// Drops this computer's wireless transport to a device. Offered for Wi-Fi
  /// entries only — a cable is unplugged, not disconnected in software.
  final ValueChanged<String>? onDisconnect;

  /// Whether any command is in flight. Disconnects are held back while one
  /// is, rather than the button vanishing — a control that disappears under
  /// the pointer is worse than one that greys out.
  final bool busy;

  /// The device a disconnect is in flight for, if any.
  final String? busyDeviceId;

  /// Only an authorized, selected device can be connected.
  bool get _canConnect {
    if (selectedId == null) {
      return false;
    }
    for (final DeviceSummary d in devices) {
      if (d.id == selectedId) {
        return d.status == DeviceStatus.authorized;
      }
    }
    return false;
  }

  bool get _hasWifi => devices.any(
    (DeviceSummary d) => d.connectionKind == DeviceConnectionKind.wifi,
  );

  @override
  Widget build(BuildContext context) {
    return ConnectPanel(
      title: 'Connected Devices',
      subtitle: 'Plugged in over USB, or already connected over Wi-Fi.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 292),
            child: _body(context),
          ),
          if (_hasWifi && onDisconnect != null) ...<Widget>[
            const SizedBox(height: DexSpace.md),
            const ConnectHint(
              text:
                  'Disconnect drops this computer’s link to a phone. It does '
                  'not remove the pairing the phone is holding — do that in '
                  'Wireless debugging on the phone itself.',
            ),
          ],
          const SizedBox(height: DexSpace.lg),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(DexIcons.refresh, size: DexIconSize.chrome),
                label: const Text('Look again'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _canConnect ? onConnect : null,
                child: const Text('Connect'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (status) {
      case LoadStatus.loading:
      case LoadStatus.idle:
        return const ConnectNotice(
          title: 'Looking for phones…',
          detail: 'Keep the cable connected while this finishes.',
        );
      case LoadStatus.empty:
        return const ConnectNotice(
          title: 'No phones found',
          detail:
              'Turn on USB debugging and choose “Look again”, or add one over '
              'Wi-Fi on the right.',
        );
      case LoadStatus.unavailable:
        return const ConnectNotice(
          title: 'ADB is unavailable',
          detail: 'DroidPier could not start ADB on this computer.',
        );
      case LoadStatus.error:
        return const ConnectNotice(
          title: 'Could not list phones',
          detail: 'Choose “Look again” to retry the search.',
        );
      case LoadStatus.ready:
        if (devices.isEmpty) {
          return const ConnectNotice(
            title: 'No phones found',
            detail:
                'Turn on USB debugging and choose “Look again”, or add one '
                'over Wi-Fi on the right.',
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: devices.length,
          separatorBuilder: (BuildContext _, int _) =>
              const SizedBox(height: DexSpace.sm),
          itemBuilder: (BuildContext context, int i) => _DeviceRow(
            device: devices[i],
            selected: devices[i].id == selectedId,
            onSelect: () => onSelect(devices[i].id),
            onDisconnect:
                onDisconnect == null ||
                    devices[i].connectionKind != DeviceConnectionKind.wifi
                ? null
                : () => onDisconnect!(devices[i].id),
            busy: busy || busyDeviceId == devices[i].id,
          ),
        );
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.onSelect,
    required this.onDisconnect,
    required this.busy,
  });

  final DeviceSummary device;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onDisconnect;
  final bool busy;

  /// What the person should do about this device, in their words.
  ///
  /// Ready is trace, the colour reserved for facts the phone has reported,
  /// rather than signal, which belongs to link state and primary actions —
  /// and Connect, right beside it, is the primary action.
  ///
  /// A phone waiting for you to tap Allow is amber, not rose. Nothing has
  /// failed; a prompt is open on a screen you are not looking at, and calling
  /// that an error is how people stop reading red.
  (String, Color) _state(DexColors colors) => switch (device.status) {
    DeviceStatus.authorized => ('Ready', colors.trace),
    DeviceStatus.unauthorized => ('Tap “Allow” on the phone', colors.warn),
    DeviceStatus.offline => ('Offline', colors.muted),
  };

  @override
  Widget build(BuildContext context) {
    final DexColors colors = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final (String label, Color color) = _state(colors);
    final bool enabled = device.status == DeviceStatus.authorized;

    return Semantics(
      selected: selected,
      button: true,
      child: HoverLift(
        enabled: enabled,
        builder: (BuildContext context, bool hovered) => InkWell(
          onTap: enabled ? onSelect : null,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            padding: const EdgeInsets.all(DexSpace.md),
            decoration: BoxDecoration(
              color: colors.raised,
              borderRadius: BorderRadius.circular(DexRadius.card),
              // Hover must out-contrast rest, and selection must out-contrast
              // hover.
              border: Border.all(
                color: selected
                    ? colors.signal
                    : hovered
                    ? colors.muted
                    : colors.line,
                width: selected ? DexStroke.focusRing : DexStroke.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: DexHit.comfortable,
                  height: DexHit.comfortable,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(DexRadius.control),
                    border: Border.all(
                      color: colors.line,
                      width: DexStroke.hairline,
                    ),
                  ),
                  child: Icon(
                    device.connectionKind == DeviceConnectionKind.usb
                        ? DexIcons.usb
                        : DexIcons.wifi,
                    size: DexIconSize.tray,
                    color: enabled ? colors.signal : colors.muted,
                  ),
                ),
                const SizedBox(width: DexSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.name,
                        style: t.bodyLarge?.copyWith(
                          color: enabled ? colors.text : colors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Serial and Android version are machine values.
                      Text(
                        <String>[
                          device.id,
                          if (device.androidVersion != null)
                            'Android ${device.androidVersion}',
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DexTheme.data(colors, size: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DexSpace.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelLarge?.copyWith(color: color),
                      ),
                      const SizedBox(height: 2),
                      // The transport as a badge, as the reference tags each
                      // row: which cable or radio this phone is on is the first
                      // thing a person checks when a link misbehaves.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DexSpace.sm,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(
                            DexRadius.control,
                          ),
                          border: Border.all(
                            color: colors.line,
                            width: DexStroke.hairline,
                          ),
                        ),
                        child: Text(
                          device.connectionKind == DeviceConnectionKind.usb
                              ? 'USB'
                              : 'WI-FI',
                          style: DexTheme.data(colors, size: 9),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDisconnect != null) ...<Widget>[
                  const SizedBox(width: DexSpace.md),
                  Tooltip(
                    message:
                        'Drop this computer’s Wi-Fi link to ${device.name}. '
                        'The phone keeps the pairing.',
                    child: OutlinedButton(
                      onPressed: busy ? null : onDisconnect,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, DexHit.comfortable),
                        foregroundColor: colors.fault,
                      ),
                      child: Semantics(
                        label: 'Disconnect ${device.name}',
                        child: const Text('Disconnect'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
