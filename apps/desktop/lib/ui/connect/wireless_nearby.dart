import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'connection_parts.dart';

/// Phones heard advertising on this network.
///
/// Every state here is a dead end without an action, so each one carries the
/// way out: discovery that cannot run, discovery that found nothing, and
/// discovery that found something all offer pairing by hand.
class NearbyBody extends StatelessWidget {
  const NearbyBody({
    required this.discovery,
    required this.clock,
    required this.busy,
    required this.onPairManually,
    required this.onUseHint,
    required this.onConnect,
    super.key,
  });

  final WirelessDiscoveryState discovery;
  final DateTime Function() clock;
  final bool busy;

  /// Switches the panel to the manual form. The escape hatch from every
  /// unhappy discovery state.
  final VoidCallback onPairManually;

  /// Fills the manual form from a heard advertisement. Never pairs on its own.
  final ValueChanged<WirelessAdvertisement> onUseHint;

  /// Brings up a transport on an endpoint already offering one.
  final void Function(String host, int port) onConnect;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = OutlinedButton(
      onPressed: onPairManually,
      child: const Text('Pair manually'),
    );

    switch (discovery.status) {
      case WirelessDiscoveryStatus.unavailable:
        return ConnectNotice(
          title: 'Cannot look for phones on this network',
          detail:
              discovery.message ??
              'Network discovery is not available on this computer. Pairing '
                  'by QR code or by hand still works.',
          action: fallback,
        );
      case WirelessDiscoveryStatus.idle:
      case WirelessDiscoveryStatus.searching:
        return const ConnectNotice(
          title: 'Listening for phones…',
          detail:
              'Open Wireless debugging on the phone and keep that screen up. '
              'It only advertises while it is showing.',
        );
      case WirelessDiscoveryStatus.ready:
        if (discovery.devices.isEmpty) {
          return ConnectNotice(
            title: 'Nothing is advertising right now',
            detail:
                'The phone must be on this same network, with Developer '
                'options → Wireless debugging open. Some networks block the '
                'discovery these broadcasts use.',
            action: fallback,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final WirelessAdvertisement ad in discovery.devices)
              Padding(
                padding: const EdgeInsets.only(bottom: DexSpace.sm),
                child: _AdvertisementRow(
                  advertisement: ad,
                  expired: !ad.expiresAt.isAfter(clock()),
                  busy: busy,
                  onUse: () => onUseHint(ad),
                  onConnect: () => onConnect(ad.host, ad.port),
                ),
              ),
            const SizedBox(height: DexSpace.xs),
            const ConnectHint(
              icon: DexIcons.privacy,
              text:
                  'These are broadcasts heard on your network, nothing more. '
                  'DroidPier has not paired with any of them and cannot '
                  'confirm a name belongs to the phone using it.',
            ),
          ],
        );
    }
  }
}

/// One heard advertisement.
///
/// Presented as a lead, never as a phone that is paired: the wording, the
/// action label and the absence of anything automatic all say the same thing.
class _AdvertisementRow extends StatelessWidget {
  const _AdvertisementRow({
    required this.advertisement,
    required this.expired,
    required this.busy,
    required this.onUse,
    required this.onConnect,
  });

  final WirelessAdvertisement advertisement;
  final bool expired;
  final bool busy;

  /// Fills the manual form from this hint. Never pairs on its own.
  final VoidCallback onUse;

  /// Brings up a transport on an endpoint that is offering one.
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final bool pairing = advertisement.kind == WirelessServiceKind.pairing;

    // A phone that publishes no name is not "unknown" or an error — most do
    // not. Say what it is instead of leaving a blank.
    final String name = switch (advertisement.displayName) {
      final String n when n.trim().isNotEmpty => n,
      _ => pairing ? 'Android phone (no name given)' : 'Android phone',
    };
    final String role = expired
        ? 'No longer advertising'
        : pairing
        ? 'Offering to pair — needs the code from the phone'
        : 'Offering a debugging connection';

    return Opacity(
      opacity: expired ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(DexSpace.md),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(DexRadius.card),
          border: Border.all(color: c.line, width: DexStroke.hairline),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              pairing ? DexIcons.qrCode : DexIcons.wifiTethering,
              size: 18,
              color: expired ? c.muted : c.text,
            ),
            const SizedBox(width: DexSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: t.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    '${advertisement.host}:${advertisement.port}',
                    style: DexTheme.data(c, size: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(role, style: t.labelSmall?.copyWith(color: c.muted)),
                ],
              ),
            ),
            const SizedBox(width: DexSpace.md),
            if (pairing)
              OutlinedButton(
                onPressed: busy || expired ? null : onUse,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, DexHit.comfortable),
                ),
                child: Semantics(
                  label: 'Pair with $name',
                  child: const Text('Pair…'),
                ),
              )
            else
              OutlinedButton(
                onPressed: busy || expired ? null : onConnect,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, DexHit.comfortable),
                ),
                child: Semantics(
                  label: 'Connect to $name',
                  child: const Text('Connect'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
