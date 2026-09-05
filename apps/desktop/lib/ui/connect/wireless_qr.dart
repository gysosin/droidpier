import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'connection_parts.dart';

/// The phone scans this computer.
///
/// Android's own *Pair device with QR code* screen is the scanner; DroidPier
/// only shows the payload. Before a code exists the panel explains where that
/// scanner lives, because a QR plate with no instructions is a picture of a
/// dead end.
class QrBody extends StatelessWidget {
  const QrBody({
    required this.pairing,
    required this.clock,
    required this.busy,
    required this.onStart,
    required this.onCancel,
    super.key,
  });

  final WirelessPairingState pairing;
  final DateTime Function() clock;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bool waiting =
        pairing.phase == WirelessPairingPhase.waitingForScan &&
        pairing.qrPayload != null;

    if (!waiting) {
      return ConnectNotice(
        title: 'Let the phone scan this computer',
        detail:
            'On the phone: Settings → Developer options → Wireless debugging → '
            'Pair device with QR code. That screen is the scanner; point it at '
            'the code shown here.',
        action: FilledButton(
          onPressed: busy ? null : onStart,
          child: const Text('Show QR code'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(child: _QrPlate(payload: pairing.qrPayload!)),
        const SizedBox(height: DexSpace.md),
        Center(
          child: _Expiry(expiresAt: pairing.expiresAt, clock: clock),
        ),
        const SizedBox(height: DexSpace.md),
        const ConnectHint(
          icon: DexIcons.qrScan,
          text:
              'On the phone: Settings → Developer options → Wireless '
              'debugging → Pair device with QR code, then point its camera '
              'here. The code is single-use and is not saved anywhere.',
        ),
        const SizedBox(height: DexSpace.md),
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: busy ? null : onStart,
              child: const Text('New code'),
            ),
            const SizedBox(width: DexSpace.sm),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Stop'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The pairing payload, rendered for a camera.
///
/// Always dark modules on a white plate, in both themes. A QR code tinted to
/// match a dark UI is a QR code that will not scan, and the plate is the one
/// place in this product where the palette answers to a camera rather than to
/// a person. The values are still read from the palette, not invented.
///
/// The payload is drawn and nothing else: it is not logged, not copied to the
/// clipboard, not put in a semantics label, and not held anywhere it could
/// outlive the pairing session.
class _QrPlate extends StatelessWidget {
  const _QrPlate({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pairing QR code for the phone to scan',
      image: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(DexSpace.md),
        decoration: BoxDecoration(
          color: DexColors.light.surface,
          borderRadius: BorderRadius.circular(DexRadius.card),
        ),
        child: QrImageView(
          data: payload,
          version: QrVersions.auto,
          size: 200,
          gapless: true,
          backgroundColor: DexColors.light.surface,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: DexColors.dark.bg,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: DexColors.dark.bg,
          ),
          errorStateBuilder: (BuildContext context, Object? _) => SizedBox(
            width: 200,
            height: 200,
            child: Center(
              child: Text(
                'This code could not be drawn. Pair by hand instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DexColors.dark.bg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How long the code on screen has left.
class _Expiry extends StatelessWidget {
  const _Expiry({required this.expiresAt, required this.clock});

  final DateTime? expiresAt;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final DateTime? at = expiresAt;
    if (at == null) {
      return Text(
        'Codes last about two minutes.',
        style: t.labelSmall?.copyWith(color: c.muted),
      );
    }
    final Duration left = at.difference(clock());
    if (left.isNegative || left == Duration.zero) {
      return Text(
        'Expired — choose “New code”.',
        style: t.labelLarge?.copyWith(color: c.fault),
      );
    }
    final String mmss =
        '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Expires in ', style: t.labelSmall?.copyWith(color: c.muted)),
        SwapText(mmss, style: DexTheme.data(c, size: 12, color: c.text)),
      ],
    );
  }
}
