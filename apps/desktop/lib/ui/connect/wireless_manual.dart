import 'package:flutter/material.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_tokens.dart';
import 'connection_parts.dart';

/// The address, port and six digits the phone is showing.
///
/// The controllers are owned by the screen, not by this widget: the code one
/// holds a one-time secret that must be cleared the moment it is submitted,
/// and that lifetime belongs with the state that issues the command.
class ManualBody extends StatelessWidget {
  const ManualBody({
    required this.host,
    required this.pairingPort,
    required this.code,
    required this.codeFocus,
    required this.busy,
    required this.canPair,
    required this.onHostChanged,
    required this.onChanged,
    required this.onPair,
    super.key,
  });

  final TextEditingController host;
  final TextEditingController pairingPort;
  final TextEditingController code;
  final FocusNode codeFocus;
  final bool busy;
  final bool canPair;

  /// The address field carries a port after the colon; the screen splits it
  /// across both fields rather than making the person do it.
  final ValueChanged<String> onHostChanged;

  /// Any other keystroke. Only re-evaluates whether Pair can be pressed.
  final VoidCallback onChanged;

  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'On the phone, tap “Pair device with pairing code”. Paste the '
          'address it shows — the port after the colon comes across with it — '
          'then type the six digits.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        ConnectFieldRow(
          children: <Widget>[
            ConnectField(
              label: 'Phone address',
              hint: '192.168.1.42:37105',
              controller: host,
              enabled: !busy,
              onChanged: onHostChanged,
            ),
            ConnectField(
              label: 'Pairing port',
              hint: '37105',
              controller: pairingPort,
              digitsOnly: true,
              maxLength: 5,
              enabled: !busy,
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
        const SizedBox(height: DexSpace.md),
        ConnectField(
          label: 'Pairing code',
          hint: 'six digits',
          controller: code,
          focusNode: codeFocus,
          obscure: true,
          digitsOnly: true,
          maxLength: 6,
          enabled: !busy,
          onChanged: (_) => onChanged(),
          onSubmitted: onPair,
        ),
        const SizedBox(height: DexSpace.sm),
        Text(
          'Leading zeros count — 004821 is a different code from 4821. '
          'It is used once and is not kept.',
          style: t.labelSmall?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        Row(
          children: <Widget>[
            const Spacer(),
            FilledButton(
              onPressed: canPair ? onPair : null,
              child: const Text('Pair'),
            ),
          ],
        ),
      ],
    );
  }
}
