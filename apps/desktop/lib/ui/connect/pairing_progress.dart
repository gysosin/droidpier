import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'connection_parts.dart';

/// The panel while an exchange with the phone is in flight.
///
/// A pairing in flight owns the whole panel — the QR, the nearby list and the
/// manual form all step aside — so this covers every phase from "pairing…"
/// through to a connected transport.
class PairingProgressBody extends StatelessWidget {
  const PairingProgressBody({
    required this.pairing,
    required this.error,
    required this.host,
    required this.connectPort,
    required this.device,
    required this.busy,
    required this.canConnect,
    required this.onCancel,
    required this.onConnect,
    required this.onChanged,
    required this.onOpenWorkspace,
    super.key,
  });

  final WirelessPairingState pairing;

  /// The last typed failure, shown where it happened.
  final OpenDexError? error;

  /// The phone's address, already resolved by the screen — from the pairing
  /// state where it is known, otherwise from what was typed.
  final String host;

  final TextEditingController connectPort;

  /// The transport this screen brought up, once there is one.
  final DeviceSummary? device;

  final bool busy;

  /// Whether the port field holds something that could be connected to.
  final bool canConnect;

  final VoidCallback onCancel;
  final VoidCallback onConnect;
  final VoidCallback onChanged;
  final ValueChanged<DeviceSummary> onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    switch (pairing.phase) {
      case WirelessPairingPhase.pairing:
        return const ConnectNotice(
          title: 'Pairing…',
          detail: 'Keep the Wireless debugging screen open on the phone.',
        );
      case WirelessPairingPhase.findingConnection:
        return const ConnectNotice(
          title: 'Paired. Finding the connection…',
          detail:
              'Android advertises the debugging port separately from the '
              'pairing one, so this is a second look, not a retry.',
        );
      case WirelessPairingPhase.needsConnectionPort:
        return _connectPortBody(context);
      case WirelessPairingPhase.connected:
        return _connectedBody(context);
      case WirelessPairingPhase.idle:
      case WirelessPairingPhase.waitingForScan:
      case WirelessPairingPhase.failed:
      case WirelessPairingPhase.expired:
        return const SizedBox.shrink();
    }
  }

  Widget _connectPortBody(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Paired. DroidPier could not work out the connection port on its '
          'own — go back one screen on the phone: “Wireless debugging” shows a '
          'different port from the pairing one.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        if (error case final OpenDexError e) ...<Widget>[
          InlineError(
            error: e,
            guidance:
                'The connect port is not the pairing port — check the number '
                'on the Wireless debugging screen itself.',
          ),
          const SizedBox(height: DexSpace.md),
        ],
        ConnectFieldRow(
          children: <Widget>[
            ConnectReadout(label: 'Phone address', value: host),
            ConnectField(
              label: 'Connect port',
              hint: '41234',
              controller: connectPort,
              digitsOnly: true,
              maxLength: 5,
              autofocus: true,
              enabled: !busy,
              onChanged: (_) => onChanged(),
              onSubmitted: onConnect,
            ),
          ],
        ),
        const SizedBox(height: DexSpace.md),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Start over'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: busy || !canConnect ? null : onConnect,
              child: const Text('Connect'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectedBody(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.wifi_tethering, size: 18, color: c.signal),
            const SizedBox(width: DexSpace.sm),
            Text('Connected over Wi-Fi', style: t.bodyLarge),
          ],
        ),
        if (device case final DeviceSummary d) ...<Widget>[
          const SizedBox(height: DexSpace.xs),
          Text(
            '${d.name}  ·  ${d.id}',
            style: DexTheme.data(c, color: c.text),
          ),
        ],
        const SizedBox(height: DexSpace.sm),
        Text(
          'ADB has an authorized transport to this phone. It is on the list '
          'now — open the workspace to finish, or unplug the cable and keep '
          'working.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Add another'),
            ),
            const Spacer(),
            if (device case final DeviceSummary d)
              FilledButton(
                onPressed: busy ? null : () => onOpenWorkspace(d),
                child: const Text('Open workspace'),
              ),
          ],
        ),
      ],
    );
  }
}
