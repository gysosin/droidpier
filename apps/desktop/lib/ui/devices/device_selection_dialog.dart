import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// Device selection. Serials are machine values, so they are set in mono;
/// everything a person reads is set in body.
///
/// Handles the states the contract can produce: loading, empty, error, ready.
/// None of them is a dead end.
class DeviceSelectionDialog extends StatelessWidget {
  const DeviceSelectionDialog({
    required this.status,
    required this.devices,
    required this.selectedId,
    required this.onSelect,
    required this.onRefresh,
    required this.onConnect,
    this.onClose,
    this.onPairWireless,
    super.key,
  });

  final LoadStatus status;
  final List<DeviceSummary> devices;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;

  /// Dismisses the dialog. Null only where there is nowhere to go back to.
  final VoidCallback? onClose;

  /// Opens the guided Wi-Fi flow. Absent where there is nothing to open it
  /// over, such as a golden harness rendering the list on its own.
  final VoidCallback? onPairWireless;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(DexSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Choose a phone', style: t.titleLarge),
              const SizedBox(height: DexSpace.xs),
              Text(
                'Plug in over USB with USB debugging on, or pair over Wi-Fi.',
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: DexSpace.lg),
              Flexible(child: _body(context, c, t)),
              const SizedBox(height: DexSpace.lg),
              // Wrapped rather than a fixed row: three controls plus a long
              // localised label do not fit a 520 px dialog at every text
              // scale, and a clipped action is an unusable one.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: DexSpace.sm,
                  runSpacing: DexSpace.sm,
                  children: <Widget>[
                    // A phone that is not on the list yet is the one case
                    // this dialog cannot answer by itself, so the way out of
                    // it sits beside the actions that assume the phone is
                    // already there.
                    if (onPairWireless != null)
                      TextButton(
                        onPressed: onPairWireless,
                        child: const Text('Pair over Wi-Fi'),
                      ),
                    // A way out that does not require connecting: opened from
                    // the desk, this dialog would otherwise be a trap.
                    if (onClose != null)
                      TextButton(
                        onPressed: onClose,
                        child: const Text('Close'),
                      ),
                    if (onClose != null) const SizedBox(width: DexSpace.sm),
                    OutlinedButton(
                      onPressed: onRefresh,
                      child: const Text('Look again'),
                    ),
                    FilledButton(
                      onPressed: _canConnect ? onConnect : null,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _body(BuildContext context, DexColors c, TextTheme t) {
    switch (status) {
      case LoadStatus.loading:
      case LoadStatus.idle:
        return _Notice(
          title: 'Looking for phones…',
          detail: 'Keep the cable connected while this finishes.',
          colors: c,
        );
      case LoadStatus.empty:
        return _Notice(
          title: 'No phones found',
          detail: 'Turn on USB debugging, then choose “Look again”.',
          colors: c,
        );
      case LoadStatus.unavailable:
        return _Notice(
          title: 'ADB is unavailable',
          detail: 'DroidPier could not start ADB on this computer.',
          colors: c,
        );
      case LoadStatus.error:
        return _Notice(
          title: 'Could not list phones',
          detail: 'Choose “Look again” to retry the search.',
          colors: c,
        );
      case LoadStatus.ready:
        return ListView.separated(
          shrinkWrap: true,
          itemCount: devices.length,
          separatorBuilder: (BuildContext _, int _) =>
              const SizedBox(height: DexSpace.sm),
          itemBuilder: (BuildContext context, int i) => _DeviceRow(
            device: devices[i],
            selected: devices[i].id == selectedId,
            onSelect: () => onSelect(devices[i].id),
            colors: c,
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
    required this.colors,
  });

  final DeviceSummary device;
  final bool selected;
  final VoidCallback onSelect;
  final DexColors colors;

  /// What the person should do about this device, in their words.
  (String, Color) get _state => switch (device.status) {
    DeviceStatus.authorized => ('Ready', colors.signal),
    DeviceStatus.unauthorized => ('Tap “Allow” on the phone', colors.fault),
    DeviceStatus.offline => ('Offline', colors.muted),
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final (String label, Color color) = _state;
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
                Icon(
                  device.connectionKind == DeviceConnectionKind.usb
                      ? Icons.usb
                      : Icons.wifi,
                  size: 18,
                  color: enabled ? colors.text : colors.muted,
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
                        style: DexTheme.data(colors, size: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DexSpace.md),
                Text(label, style: t.labelLarge?.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.detail,
    required this.colors,
  });

  final String title;
  final String detail;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: colors.line, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: t.bodyLarge),
          const SizedBox(height: DexSpace.xs),
          Text(detail, style: t.bodyMedium?.copyWith(color: colors.muted)),
        ],
      ),
    );
  }
}
