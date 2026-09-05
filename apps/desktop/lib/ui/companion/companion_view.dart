import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// The phone-side companion, drawn in a phone frame over the desk.
///
/// The real companion lives in `android/` and is a Jetpack Compose app on
/// Material 3 tokens, not on the desk's. This is a rendering of what it shows
/// — the link state, the foreground notification, the permissions the phone
/// has granted, how to pair — inside a phone frame, reached from the header's
/// Companion App door, as the reference reaches it. It draws on the
/// companion's own Material 3 surfaces rather than the desk's glass: this is
/// a view of the phone's app, and it should look like the phone's app.
///
/// Everything with a number reads it from the snapshot. Where the snapshot
/// carries nothing, the readout is an em dash, not a plausible value.
class CompanionView extends StatefulWidget {
  const CompanionView({
    required this.snapshot,
    required this.onClose,
    super.key,
  });

  final OpenDexSnapshot snapshot;

  /// Closes the view. The reference's "Disconnect Desktop Session" button does
  /// exactly this too, so it is labelled for what it does here: Close.
  final VoidCallback onClose;

  @override
  State<CompanionView> createState() => _CompanionViewState();
}

enum _Tab { dashboard, permissions, pairing }

/// The companion's Material 3 dark surfaces, as the reference sets them. They
/// are the phone app's tokens, not the desk's, which is why they are literal.
const Color _m3Background = Color(0xFF1C1B1F);
const Color _m3Surface = Color(0xFF2B2930);
const Color _m3OnSurface = Color(0xFFE6E1E5);
const Color _m3Bezel = Color(0xFF1E293B);

class _CompanionViewState extends State<CompanionView> {
  _Tab _tab = _Tab.dashboard;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final OpenDexSnapshot s = widget.snapshot;
    final DeviceSummary? device = s.selectedDevice;

    return Semantics(
      container: true,
      label: 'Companion app preview',
      child: SizedBox(
        width: 384,
        height: 640,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _m3Background,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: _m3Bezel, width: 8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              children: <Widget>[
                // Status bar: the time and the charge are the phone's own,
                // which the desk does not know; both are set as placeholders
                // the reference also draws statically.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DexSpace.xl,
                    DexSpace.md,
                    DexSpace.xl,
                    0,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text('12:00', style: DexTheme.data(c, size: 11)),
                      const Spacer(),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.signal, width: 2),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        s.telemetry.batteryPercentage == null
                            ? '—'
                            : '${s.telemetry.batteryPercentage}%',
                        style: DexTheme.data(c, size: 11),
                      ),
                    ],
                  ),
                ),
                // Header.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DexSpace.lg,
                    DexSpace.md,
                    DexSpace.md,
                    DexSpace.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.signal,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          'D',
                          style: t.labelLarge?.copyWith(color: c.bg),
                        ),
                      ),
                      const SizedBox(width: DexSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'DroidPier Companion',
                              style: t.labelLarge?.copyWith(color: c.text),
                            ),
                            Text(
                              'Jetpack Compose M3 UI',
                              style: t.bodySmall?.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(DexIcons.close, size: 16),
                        color: c.muted,
                        tooltip: 'Close',
                        constraints: const BoxConstraints(
                          minWidth: DexHit.comfortable,
                          minHeight: DexHit.comfortable,
                        ),
                      ),
                    ],
                  ),
                ),
                _Tabs(
                  selected: _tab,
                  colors: c,
                  onSelect: (_Tab tab) => setState(() => _tab = tab),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(DexSpace.lg),
                    child: switch (_tab) {
                      _Tab.dashboard => _Dashboard(
                        snapshot: s,
                        device: device,
                        colors: c,
                        onClose: widget.onClose,
                      ),
                      _Tab.permissions => _Permissions(
                        permissions: s.permissions,
                        colors: c,
                      ),
                      _Tab.pairing => _Pairing(device: device, colors: c),
                    },
                  ),
                ),
                // The gesture pill.
                Padding(
                  padding: const EdgeInsets.only(bottom: DexSpace.sm),
                  child: Container(
                    width: 96,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(DexRadius.pill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.colors,
    required this.onSelect,
  });

  final _Tab selected;
  final DexColors colors;
  final ValueChanged<_Tab> onSelect;

  static String _label(_Tab t) => switch (t) {
    _Tab.dashboard => 'Dashboard',
    _Tab.permissions => 'Permissions',
    _Tab.pairing => 'Pairing',
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.line, width: DexStroke.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final _Tab tab in _Tab.values)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(tab),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(
                    minHeight: DexHit.comfortable,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: tab == selected
                            ? colors.signal
                            : Colors.transparent,
                        width: DexStroke.focusRing,
                      ),
                    ),
                  ),
                  child: Text(
                    _label(tab),
                    style: t.labelMedium?.copyWith(
                      color: tab == selected ? colors.signal : colors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.colors});

  final Widget child;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: DexSpace.md),
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: _m3Surface,
        borderRadius: BorderRadius.circular(DexRadius.modal),
        border: Border.all(
          color: _m3OnSurface.withValues(alpha: 0.05),
          width: DexStroke.hairline,
        ),
      ),
      child: child,
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.snapshot,
    required this.device,
    required this.colors,
    required this.onClose,
  });

  final OpenDexSnapshot snapshot;
  final DeviceSummary? device;
  final DexColors colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool linked = device != null;
    final TelemetryMeasurement? tx = snapshot.telemetry.throughput;
    final TelemetryMeasurement? rtt = snapshot.telemetry.linkLatency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Card(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    linked ? DexIcons.circleCheck : DexIcons.circleX,
                    size: 16,
                    color: linked ? colors.trace : colors.muted,
                  ),
                  const SizedBox(width: DexSpace.sm),
                  Text(
                    linked ? 'Connected to Desktop' : 'No desktop linked',
                    style: t.labelLarge?.copyWith(
                      color: linked ? colors.trace : colors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DexSpace.sm),
              Text(
                linked ? 'This computer' : 'Waiting for a link',
                style: t.titleMedium?.copyWith(color: colors.text),
              ),
              Divider(color: colors.line, height: DexSpace.xl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Readout(
                      label: 'ROUND TRIP',
                      value: rtt == null ? '—' : '${rtt.value.round()} ms',
                      colors: colors,
                    ),
                  ),
                  Expanded(
                    child: _Readout(
                      label: 'DATA TX',
                      value: tx == null ? '—' : _bytes(tx.value),
                      colors: colors,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Card(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'FOREGROUND NOTIFICATION',
                style: DexTheme.data(
                  colors,
                  size: 10,
                ).copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: DexSpace.sm),
              Container(
                padding: const EdgeInsets.all(DexSpace.sm),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(DexRadius.control),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            linked ? 'DroidPier active' : 'DroidPier idle',
                            style: t.labelMedium?.copyWith(color: colors.text),
                          ),
                          Text(
                            linked
                                ? 'Link active on port 3698/3699'
                                : 'Listening on port 3698/3699',
                            style: t.bodySmall?.copyWith(color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (linked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DexSpace.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.fault.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            DexRadius.control,
                          ),
                        ),
                        child: Text(
                          'Disconnect',
                          style: t.labelSmall?.copyWith(color: colors.fault),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (linked)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: colors.fault,
                foregroundColor: _m3Background,
                minimumSize: const Size(0, DexHit.primary),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(DexIcons.close, size: 16),
              label: const Text('Close Companion View'),
            ),
          ),
      ],
    );
  }

  static String _bytes(double perSecond) {
    if (perSecond >= 1000000) {
      return '${(perSecond / 1000000).toStringAsFixed(1)} MB/s';
    }
    if (perSecond >= 1000) return '${(perSecond / 1000).round()} kB/s';
    return '${perSecond.round()} B/s';
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: DexTheme.data(colors, size: 9).copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 2),
        Text(value, style: DexTheme.data(colors, size: 12, color: colors.text)),
      ],
    );
  }
}

class _Permissions extends StatelessWidget {
  const _Permissions({required this.permissions, required this.colors});

  final PermissionState permissions;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<MapEntry<String, PermissionGrant>> rows =
        permissions.grants.entries.toList()..sort(
          (
            MapEntry<String, PermissionGrant> a,
            MapEntry<String, PermissionGrant> b,
          ) => a.key.compareTo(b.key),
        );
    if (rows.isEmpty) {
      return _Card(
        colors: colors,
        child: Text(
          'The desk has not asked for anything yet.',
          style: t.bodyMedium?.copyWith(color: colors.muted),
        ),
      );
    }
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MapEntry<String, PermissionGrant> r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DexSpace.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      r.key,
                      style: t.bodyMedium?.copyWith(color: colors.text),
                    ),
                  ),
                  Text(
                    switch (r.value) {
                      PermissionGrant.granted => 'Granted',
                      PermissionGrant.denied => 'Off',
                      PermissionGrant.requiresSettings => 'Needs settings',
                      PermissionGrant.unavailable => 'Not on this phone',
                    },
                    style: DexTheme.data(
                      colors,
                      size: 11,
                      color: switch (r.value) {
                        PermissionGrant.granted => colors.trace,
                        PermissionGrant.requiresSettings => colors.warn,
                        _ => colors.muted,
                      },
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

class _Pairing extends StatelessWidget {
  const _Pairing({required this.device, required this.colors});

  final DeviceSummary? device;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(DexIcons.qrCode, size: 40, color: colors.signal),
          const SizedBox(height: DexSpace.md),
          Text(
            'Pair over Wi-Fi',
            style: t.titleMedium?.copyWith(color: colors.text),
          ),
          const SizedBox(height: DexSpace.xs),
          Text(
            'Turn on Wireless debugging on this phone, then scan the code the '
            'desk shows, or type the address it prints.',
            style: t.bodySmall?.copyWith(color: colors.muted),
          ),
          Divider(color: colors.line, height: DexSpace.xl),
          _Readout(
            label: 'THIS PHONE',
            value: device?.name ?? '—',
            colors: colors,
          ),
          const SizedBox(height: DexSpace.sm),
          _Readout(
            label: 'AGENT · COMPANION',
            value: 'tcp 3698 · ws 3699',
            colors: colors,
          ),
        ],
      ),
    );
  }
}
