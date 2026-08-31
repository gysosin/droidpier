import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// Pair with the endpoint and one-time code the phone is showing.
///
/// Returns whether ADB accepted the pairing. The failure itself is reported by
/// the bootstrap's error decorator, so this surface never sees an
/// [OpenDexError] and cannot leak one into the tree.
typedef PairWireless = Future<bool> Function({
  required String host,
  required int pairingPort,
  required String pairingCode,
});

/// Connect to the separately advertised debugging endpoint. Null means the
/// connection did not come up.
typedef ConnectWireless = Future<DeviceSummary?> Function({
  required String host,
  required int port,
});

/// Drop a paired network device.
typedef ForgetWireless = Future<bool> Function(String deviceId);

/// Where the person is in the flow.
///
/// Android 11+ genuinely splits pairing from connecting — two endpoints, and
/// only the first takes a code — so the flow shows the split rather than
/// pretending one step failed twice.
enum WirelessStep { pair, connect, linked }

/// The guided Wi-Fi surface: pair, connect, forget.
///
/// It reads like the phone's own screens because that is where every value on
/// it comes from: *Wireless debugging → Pair device with pairing code* gives
/// the pairing endpoint and the six-digit code, and the screen behind it gives
/// the connect port, which is a different number. Naming both makes the one
/// confusing part of ADB wireless legible instead of a failed attempt.
///
/// The pairing code is a one-time secret. It is typed into an obscured field,
/// read once at submit, cleared from that field before the command is awaited,
/// and never stored in state, echoed into any other widget, or logged.
class WirelessPairingDialog extends StatefulWidget {
  const WirelessPairingDialog({
    required this.devices,
    required this.onPair,
    required this.onConnect,
    required this.onForget,
    required this.onClose,
    super.key,
  });

  /// Binds the surface to the facade.
  ///
  /// The only place the UI touches the three wireless commands, so the shell
  /// and the preview drive exactly the same thing.
  factory WirelessPairingDialog.forFacade({
    required OpenDexFacade facade,
    required List<DeviceSummary> devices,
    required VoidCallback onClose,
    Key? key,
  }) {
    return WirelessPairingDialog(
      key: key,
      devices: devices,
      onClose: onClose,
      onPair:
          ({
            required String host,
            required int pairingPort,
            required String pairingCode,
          }) async {
            final VoidResult result = await facade.pairWirelessDevice(
              host: host,
              pairingPort: pairingPort,
              pairingCode: pairingCode,
            );
            return result.isSuccess;
          },
      onConnect: ({required String host, required int port}) async {
        final CommandResult<DeviceSummary> result = await facade
            .connectWirelessDevice(host: host, port: port);
        return switch (result) {
          CommandSuccess<DeviceSummary>(:final DeviceSummary value) => value,
          CommandFailure<DeviceSummary>() => null,
        };
      },
      onForget: (String deviceId) async {
        final VoidResult result = await facade.forgetWirelessDevice(deviceId);
        return result.isSuccess;
      },
    );
  }

  /// Every known device. Wi-Fi entries are the ones that can be forgotten.
  final List<DeviceSummary> devices;
  final PairWireless onPair;
  final ConnectWireless onConnect;
  final ForgetWireless onForget;
  final VoidCallback onClose;

  @override
  State<WirelessPairingDialog> createState() => _WirelessPairingDialogState();
}

class _WirelessPairingDialogState extends State<WirelessPairingDialog> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _pairingPort = TextEditingController();
  final TextEditingController _connectPort = TextEditingController();

  /// Holds the one-time code only between keystroke and submit. Cleared the
  /// moment the command is issued, and again on dispose.
  final TextEditingController _code = TextEditingController();

  WirelessStep _step = WirelessStep.pair;
  bool _busy = false;
  bool _pairFailed = false;
  bool _connectFailed = false;
  String? _forgetting;
  DeviceSummary? _linked;

  @override
  void dispose() {
    _host.dispose();
    _pairingPort.dispose();
    _connectPort.dispose();
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  List<DeviceSummary> get _wifiDevices => <DeviceSummary>[
    for (final DeviceSummary d in widget.devices)
      if (d.connectionKind == DeviceConnectionKind.wifi) d,
  ];

  static int? _port(String raw) {
    final int? value = int.tryParse(raw.trim());
    if (value == null || value < 1 || value > 65535) {
      return null;
    }
    return value;
  }

  bool get _canPair =>
      !_busy &&
      _host.text.trim().isNotEmpty &&
      _port(_pairingPort.text) != null &&
      _code.text.length == 6;

  bool get _canConnect =>
      !_busy &&
      _host.text.trim().isNotEmpty &&
      _port(_connectPort.text) != null;

  Future<void> _pair() async {
    if (!_canPair) {
      return;
    }
    final String host = _host.text.trim();
    final int pairingPort = _port(_pairingPort.text)!;
    // Read once, then clear: the code must not survive submission, must not
    // sit in a field while the command is in flight, and must not enter state.
    final String code = _code.text;
    _code.clear();
    setState(() {
      _busy = true;
      _pairFailed = false;
    });
    final bool ok = await widget.onPair(
      host: host,
      pairingPort: pairingPort,
      pairingCode: code,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _pairFailed = !ok;
      if (ok) {
        _step = WirelessStep.connect;
      }
    });
  }

  Future<void> _connect() async {
    if (!_canConnect) {
      return;
    }
    final String host = _host.text.trim();
    final int port = _port(_connectPort.text)!;
    setState(() {
      _busy = true;
      _connectFailed = false;
    });
    final DeviceSummary? device = await widget.onConnect(
      host: host,
      port: port,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _connectFailed = device == null;
      if (device != null) {
        _linked = device;
        _step = WirelessStep.linked;
      }
    });
  }

  Future<void> _forget(String deviceId) async {
    setState(() {
      _busy = true;
      _forgetting = deviceId;
    });
    await widget.onForget(deviceId);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _forgetting = null;
      // A device that was just dropped is no longer the one we linked.
      if (_linked?.id == deviceId) {
        _linked = null;
        _step = WirelessStep.pair;
      }
    });
  }

  /// Start again without leaving the surface — pairing a second phone is a
  /// normal thing to want, and closing to reopen is not an answer.
  void _restart() {
    _code.clear();
    setState(() {
      _step = WirelessStep.pair;
      _pairFailed = false;
      _connectFailed = false;
      _linked = null;
      _connectPort.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    final Widget body = Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(DexSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Entrance(
                  child: Text('Add a phone over Wi-Fi', style: t.titleLarge),
                ),
                const SizedBox(height: DexSpace.xs),
                Entrance(
                  order: 1,
                  child: Text(
                    'On the phone, open Developer options, then Wireless '
                    'debugging. '
                    'Keep that screen open — its numbers change when it closes.',
                    style: t.bodyMedium?.copyWith(color: c.muted),
                  ),
                ),
                const SizedBox(height: DexSpace.lg),
                Entrance(
                  order: 2,
                  child: _StepRail(step: _step, colors: c),
                ),
                const SizedBox(height: DexSpace.lg),
                Entrance(order: 3, child: _stepBody(c, t)),
                const SizedBox(height: DexSpace.lg),
                Entrance(order: 4, child: _pairedDevices(c, t)),
                const SizedBox(height: DexSpace.lg),
                Entrance(order: 5, child: _actions(c)),
              ],
            ),
          ),
        ),
      ),
    );

    // Escape leaves. A modal you cannot dismiss from the keyboard is a trap,
    // and this one can be opened before any device exists.
    return FocusTraversalGroup(
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                widget.onClose();
                return null;
              },
            ),
          },
          child: body,
        ),
      ),
    );
  }

  Widget _stepBody(DexColors c, TextTheme t) {
    return AnimatedSwitcher(
      duration: DexMotion.enabled(context)
          ? DexDuration.standard
          : Duration.zero,
      switchInCurve: DexMotion.arrive,
      child: switch (_step) {
        WirelessStep.pair => _pairStep(c, t),
        WirelessStep.connect => _connectStep(c, t),
        WirelessStep.linked => _linkedStep(c, t),
      },
    );
  }

  Widget _pairStep(DexColors c, TextTheme t) {
    return Column(
      key: const ValueKey<String>('step-pair'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Tap “Pair device with pairing code”. Copy the address, the port '
          'after the colon, and the six digits it shows.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        _FieldRow(
          children: <Widget>[
            _Field(
              label: 'Phone address',
              hint: '192.168.1.42',
              controller: _host,
              autofocus: true,
              enabled: !_busy,
              onChanged: _rebuild,
              colors: c,
            ),
            _Field(
              label: 'Pairing port',
              hint: '37105',
              controller: _pairingPort,
              digitsOnly: true,
              maxLength: 5,
              enabled: !_busy,
              onChanged: _rebuild,
              colors: c,
            ),
          ],
        ),
        const SizedBox(height: DexSpace.md),
        _Field(
          label: 'Pairing code',
          hint: 'six digits',
          controller: _code,
          obscure: true,
          digitsOnly: true,
          maxLength: 6,
          enabled: !_busy,
          onChanged: _rebuild,
          onSubmitted: _pair,
          colors: c,
        ),
        const SizedBox(height: DexSpace.sm),
        Text(
          'The code is used once and is not kept.',
          style: t.labelSmall?.copyWith(color: c.muted),
        ),
        if (_pairFailed) ...<Widget>[
          const SizedBox(height: DexSpace.md),
          // The reason came through as a toast from the facade's error
          // reporting. What is left to say is what to do next, which is
          // specific to this screen: the code expires.
          _Guidance(
            text:
                'Pairing did not complete. The phone shows a new code each '
                'time that dialog opens — read it again and retry.',
            colors: c,
          ),
        ],
      ],
    );
  }

  Widget _connectStep(DexColors c, TextTheme t) {
    return Column(
      key: const ValueKey<String>('step-connect'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Paired. Now go back one screen: “Wireless debugging” shows a '
          'different port for connecting.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: DexSpace.md),
        _FieldRow(
          children: <Widget>[
            _Readout(
              label: 'Phone address',
              value: _host.text.trim(),
              colors: c,
            ),
            _Field(
              label: 'Connect port',
              hint: '41234',
              controller: _connectPort,
              digitsOnly: true,
              maxLength: 5,
              autofocus: true,
              enabled: !_busy,
              onChanged: _rebuild,
              onSubmitted: _connect,
              colors: c,
            ),
          ],
        ),
        if (_connectFailed) ...<Widget>[
          const SizedBox(height: DexSpace.md),
          _Guidance(
            text:
                'No connection on that port. The connect port is not the '
                'pairing port — check the number on the Wireless debugging '
                'screen itself.',
            colors: c,
          ),
        ],
      ],
    );
  }

  Widget _linkedStep(DexColors c, TextTheme t) {
    final DeviceSummary? device = _linked;
    return Column(
      key: const ValueKey<String>('step-linked'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Linked over Wi-Fi', style: t.bodyLarge),
        const SizedBox(height: DexSpace.xs),
        if (device != null)
          Text(
            '${device.name}  ·  ${device.id}',
            style: DexTheme.data(c, color: c.text),
          ),
        const SizedBox(height: DexSpace.sm),
        Text(
          'It is in the phone list now. Choose it there to open the '
          'workspace, or unplug the cable and keep working.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
      ],
    );
  }

  Widget _pairedDevices(DexColors c, TextTheme t) {
    final List<DeviceSummary> wifi = _wifiDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Paired over Wi-Fi', style: t.labelLarge),
            const SizedBox(width: DexSpace.sm),
            Text('${wifi.length}', style: DexTheme.data(c, size: 11)),
          ],
        ),
        const SizedBox(height: DexSpace.sm),
        if (wifi.isEmpty)
          Text(
            'No phones are paired over Wi-Fi yet.',
            style: t.bodyMedium?.copyWith(color: c.muted),
          )
        else
          for (final DeviceSummary d in wifi)
            Padding(
              padding: const EdgeInsets.only(bottom: DexSpace.sm),
              child: _PairedRow(
                device: d,
                busy: _forgetting == d.id,
                onForget: _busy ? null : () => _forget(d.id),
                colors: c,
              ),
            ),
      ],
    );
  }

  Widget _actions(DexColors c) {
    return Row(
      children: <Widget>[
        _Working(busy: _busy, colors: c),
        const Spacer(),
        if (_step == WirelessStep.connect)
          OutlinedButton(
            onPressed: _busy ? null : _restart,
            child: const Text('Start over'),
          )
        else if (_step == WirelessStep.linked)
          OutlinedButton(
            onPressed: _busy ? null : _restart,
            child: const Text('Pair another'),
          )
        else
          OutlinedButton(onPressed: widget.onClose, child: const Text('Close')),
        const SizedBox(width: DexSpace.sm),
        switch (_step) {
          WirelessStep.pair => FilledButton(
            onPressed: _canPair ? _pair : null,
            child: const Text('Pair'),
          ),
          WirelessStep.connect => FilledButton(
            onPressed: _canConnect ? _connect : null,
            child: const Text('Connect'),
          ),
          WirelessStep.linked => FilledButton(
            onPressed: widget.onClose,
            child: const Text('Done'),
          ),
        },
      ],
    );
  }

  /// Field edits change which buttons are live, so the frame has to be rebuilt
  /// — but nothing typed is copied into state to do it.
  void _rebuild() => setState(() {});
}

/// Two fields side by side on a wide dialog, stacked when it is narrow.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: DexSpace.md),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: DexSpace.md),
              Expanded(flex: i == 0 ? 3 : 2, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// A machine value the person copies off the phone. Mono, because that is what
/// it is, and because addresses and ports are compared digit by digit.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.colors,
    this.obscure = false,
    this.digitsOnly = false,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final DexColors colors;
  final bool obscure;
  final bool digitsOnly;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DexRadius.control),
      borderSide: BorderSide(color: colors.line, width: DexStroke.hairline),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelLarge),
        const SizedBox(height: DexSpace.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DexHit.primary),
          child: TextField(
            controller: controller,
            enabled: enabled,
            autofocus: autofocus,
            obscureText: obscure,
            // A one-time code is not a password to remember and not a word to
            // correct: keep it away from suggestion, autofill, and IME
            // learning stores entirely.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const <String>[],
            keyboardType: digitsOnly
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: <TextInputFormatter>[
              if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
              if (maxLength != null)
                LengthLimitingTextInputFormatter(maxLength),
            ],
            textInputAction: onSubmitted == null
                ? TextInputAction.next
                : TextInputAction.done,
            style: DexTheme.data(colors, color: colors.text),
            onChanged: (_) => onChanged?.call(),
            onSubmitted: (_) => onSubmitted?.call(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.raised,
              hintText: hint,
              hintStyle: DexTheme.data(colors),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DexSpace.md,
                vertical: DexSpace.md,
              ),
              border: border,
              enabledBorder: border,
              // Focus out-contrasts rest, always visibly.
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DexRadius.control),
                borderSide: BorderSide(
                  color: colors.signal,
                  width: DexStroke.focusRing,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A value carried over from an earlier step. Shown, not re-asked.
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
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelLarge),
        const SizedBox(height: DexSpace.xs),
        Container(
          height: DexHit.primary,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: DexSpace.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(DexRadius.control),
            border: Border.all(color: colors.line, width: DexStroke.hairline),
          ),
          child: Text(value, style: DexTheme.data(colors, color: colors.text)),
        ),
      ],
    );
  }
}

/// Pair → Connect → Linked, drawn like the Link Rail because it is the same
/// idea at a smaller scale: a real transport with stations you can be at.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.step, required this.colors});

  final WirelessStep step;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    const List<(WirelessStep, String)> stations = <(WirelessStep, String)>[
      (WirelessStep.pair, 'Pair'),
      (WirelessStep.connect, 'Connect'),
      (WirelessStep.linked, 'Linked'),
    ];

    return Semantics(
      label:
          'Step ${step.index + 1} of ${stations.length}: ${switch (step) {
            WirelessStep.pair => 'pair',
            WirelessStep.connect => 'connect',
            WirelessStep.linked => 'linked',
          }}',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (int i = 0; i < stations.length; i++) ...<Widget>[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: DexStroke.hairline,
                    margin: const EdgeInsets.symmetric(horizontal: DexSpace.sm),
                    color: stations[i].$1.index <= step.index
                        ? colors.signal
                        : colors.line,
                  ),
                ),
              _StepNode(
                label: stations[i].$2,
                done: stations[i].$1.index < step.index,
                active: stations[i].$1 == step,
                colors: colors,
                style: t.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.label,
    required this.done,
    required this.active,
    required this.colors,
    required this.style,
  });

  final String label;
  final bool done;
  final bool active;
  final DexColors colors;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final Color color = done || active ? colors.signal : colors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Scale, not size: the only properties this product animates are
        // transform and opacity.
        AnimatedScale(
          duration: DexMotion.enabled(context)
              ? DexDuration.standard
              : Duration.zero,
          curve: DexMotion.arrive,
          scale: active ? 1 : 0.7,
          child: Container(
            width: DexSpace.sm,
            height: DexSpace.sm,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done || active ? colors.signal : colors.line,
            ),
          ),
        ),
        const SizedBox(width: DexSpace.sm),
        Text(label, style: style?.copyWith(color: color)),
      ],
    );
  }
}

/// A paired Wi-Fi device, with the only destructive control on this surface.
class _PairedRow extends StatelessWidget {
  const _PairedRow({
    required this.device,
    required this.busy,
    required this.onForget,
    required this.colors,
  });

  final DeviceSummary device;
  final bool busy;
  final VoidCallback? onForget;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(DexSpace.md),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: colors.line, width: DexStroke.hairline),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.wifi, size: 18, color: colors.text),
          const SizedBox(width: DexSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(device.name, style: t.bodyLarge),
                const SizedBox(height: 2),
                Text(device.id, style: DexTheme.data(colors, size: 11)),
              ],
            ),
          ),
          const SizedBox(width: DexSpace.md),
          Tooltip(
            message: 'Drop this pairing. The phone will ask to pair again.',
            child: OutlinedButton(
              onPressed: busy ? null : onForget,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, DexHit.comfortable),
                foregroundColor: colors.fault,
              ),
              child: Semantics(
                label: 'Forget ${device.name}',
                child: const Text('Forget'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// UI-authored next step. Never the backend's message — typed failures are
/// already reported once, by the facade decorator, as a toast.
class _Guidance extends StatelessWidget {
  const _Guidance({required this.text, required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DexSpace.md),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: colors.fault, width: DexStroke.hairline),
      ),
      child: Text(text, style: t.bodyMedium?.copyWith(color: colors.text)),
    );
  }
}

/// Work in flight.
///
/// Held back for [DexDuration.loadingDelay] so a fast pair does not flash an
/// indicator, then kept for at least [DexDuration.loadingFloor] so it is
/// readable rather than a blink.
class _Working extends StatefulWidget {
  const _Working({required this.busy, required this.colors});

  final bool busy;
  final DexColors colors;

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> {
  Timer? _delay;
  Timer? _floor;
  bool _visible = false;
  bool _hideWhenFloorEnds = false;

  @override
  void didUpdateWidget(_Working oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _start();
    } else if (!widget.busy && oldWidget.busy) {
      _stop();
    }
  }

  void _start() {
    _delay?.cancel();
    _hideWhenFloorEnds = false;
    _delay = Timer(DexDuration.loadingDelay, () {
      if (!mounted) {
        return;
      }
      setState(() => _visible = true);
      _floor = Timer(DexDuration.loadingFloor, () {
        _floor = null;
        if (mounted && _hideWhenFloorEnds) {
          setState(() {
            _visible = false;
            _hideWhenFloorEnds = false;
          });
        }
      });
    });
  }

  void _stop() {
    _delay?.cancel();
    _delay = null;
    if (!_visible) {
      return;
    }
    if (_floor != null) {
      _hideWhenFloorEnds = true;
    } else {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _floor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    // Reserve the height either way so revealing the indicator never shifts
    // the buttons beside it.
    if (!_visible) {
      return const SizedBox(height: DexHit.minimum);
    }
    return Entrance(
      rise: 4,
      child: SizedBox(
        height: DexHit.minimum,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: DexSpace.md,
              height: DexSpace.md,
              child: CircularProgressIndicator(
                strokeWidth: DexStroke.focusRing,
                color: widget.colors.signal,
              ),
            ),
            const SizedBox(width: DexSpace.sm),
            Text(
              'Talking to the phone…',
              style: t.labelSmall?.copyWith(color: widget.colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
