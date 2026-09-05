import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'connection_commands.dart';
import 'connection_parts.dart';
import 'pairing_progress.dart';
import 'phone_list.dart';
import 'wireless_manual.dart';
import 'wireless_nearby.dart';
import 'wireless_qr.dart';

/// The one place a phone is added and chosen.
///
/// It replaces a phone list with a pairing dialog stacked on top of it. That
/// arrangement asked the person to answer "which phone?" before they had one,
/// then buried the way to get one behind a second modal. Here both halves are
/// on screen at once: the transports ADB already has on the left, and the three
/// ways to add one over Wi-Fi on the right.
///
/// The three ways are genuinely different, which is why they are segments and
/// not steps:
///
///   * **Nearby phones** — advertisements picked up on the network. Hints only.
///     Nothing here proves a phone is paired, or even that it is the phone it
///     claims to be, so nothing is ever attempted automatically.
///   * **QR code** — the phone scans us. Android's own *Pair device with QR
///     code* screen is the scanner; DroidPier only displays the payload.
///   * **Manual** — the address, port and six digits the phone is showing.
///
/// Discovery runs for exactly as long as this screen is open: started in
/// [initState], stopped in [dispose] along with any pairing in flight.
///
/// The screen never touches the facade. Everything it can do is a
/// [ConnectionCommands] callback, so it has no route to a socket or to ADB.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    required this.deviceStatus,
    required this.devices,
    required this.discovery,
    required this.pairing,
    required this.commands,
    required this.selectedId,
    required this.onSelect,
    required this.onConnectSelected,
    required this.onRefreshDevices,
    required this.onClose,
    this.clock = DateTime.now,
    super.key,
  });

  /// Binds the surface to the contract, snapshot and all.
  ///
  /// The only place the shell and the preview differ is what they do when a
  /// phone is finally chosen, so that stays a callback.
  factory ConnectionScreen.forFacade({
    required OpenDexFacade facade,
    required OpenDexSnapshot snapshot,
    required String? selectedId,
    required ValueChanged<String> onSelect,
    required VoidCallback onConnectSelected,
    required VoidCallback onRefreshDevices,
    required VoidCallback onClose,
    DateTime Function() clock = DateTime.now,
    Key? key,
  }) {
    return ConnectionScreen(
      key: key,
      deviceStatus: snapshot.deviceStatus,
      devices: snapshot.devices,
      discovery: snapshot.wirelessDiscovery,
      pairing: snapshot.wirelessPairing,
      commands: ConnectionCommands.forFacade(facade),
      selectedId: selectedId,
      onSelect: onSelect,
      onConnectSelected: onConnectSelected,
      onRefreshDevices: onRefreshDevices,
      onClose: onClose,
      clock: clock,
    );
  }

  final LoadStatus deviceStatus;
  final List<DeviceSummary> devices;

  /// Live from the snapshot, so an advertisement appearing or a pairing phase
  /// moving redraws this screen without it polling anything.
  final WirelessDiscoveryState discovery;
  final WirelessPairingState pairing;

  final ConnectionCommands commands;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onConnectSelected;
  final VoidCallback onRefreshDevices;
  final VoidCallback onClose;

  /// Reads the wall clock, for the QR countdown and advertisement expiry.
  /// Injected so a test can hold time still.
  final DateTime Function() clock;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _pairingPort = TextEditingController();
  final TextEditingController _connectPort = TextEditingController();

  /// Holds the one-time code only between keystroke and submit. Cleared the
  /// moment the command is issued, and again on dispose. It is never copied
  /// into state, never echoed anywhere, and never logged.
  final TextEditingController _code = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  WirelessMode _mode = WirelessMode.nearby;
  bool _busy = false;

  /// The last typed failure, shown where it happened. Cleared by the next
  /// attempt, so it never outlives the thing it describes.
  OpenDexError? _error;

  /// A transport this screen brought up itself. The coordinator reports one on
  /// the snapshot for the automatic path; this covers the manual one.
  DeviceSummary? _linked;

  String? _disconnecting;

  /// Ticks once a second, and only while something on screen is counting down.
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    // Opening the screen is the consent to look. Nothing was listening before.
    scheduleMicrotask(() {
      if (mounted) unawaited(_start());
    });
    _syncCountdown();
  }

  Future<void> _start() async {
    final OpenDexError? error = await widget.commands.startDiscovery();
    if (!mounted || error == null) {
      return;
    }
    setState(() => _error = error);
  }

  @override
  void didUpdateWidget(ConnectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    // Closing withdraws it again: the pairing session goes first so no payload
    // is left live, then the listeners stop.
    final commands = widget.commands;
    // Facade commands can synchronously notify the parent StreamBuilder.
    // Finish unmounting before emitting those state changes.
    unawaited(
      Future<void>.microtask(() async {
        await commands.cancelPairing();
        await commands.stopDiscovery();
      }),
    );
    _host.dispose();
    _pairingPort.dispose();
    _connectPort.dispose();
    _code.clear();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// A second-resolution timer, but only while a QR code is on screen. A modal
  /// that rebuilds once a second for nothing is a modal that costs battery.
  void _syncCountdown() {
    final bool needed =
        widget.pairing.phase == WirelessPairingPhase.waitingForScan &&
        widget.pairing.expiresAt != null;
    if (needed && _countdown == null) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!needed) {
      _countdown?.cancel();
      _countdown = null;
    }
  }

  WirelessPairingState get _pairing => widget.pairing;

  /// True while the backend is mid-exchange and the person should not be
  /// offered another way in.
  bool get _pairingInFlight => switch (_pairing.phase) {
    WirelessPairingPhase.pairing ||
    WirelessPairingPhase.findingConnection ||
    WirelessPairingPhase.needsConnectionPort ||
    WirelessPairingPhase.connected => true,
    WirelessPairingPhase.idle ||
    WirelessPairingPhase.waitingForScan ||
    WirelessPairingPhase.failed ||
    WirelessPairingPhase.expired => false,
  };

  /// The transport that came up, from either path.
  DeviceSummary? get _connected => _pairing.device ?? _linked;

  // ---------------------------------------------------------------- parsing

  static int? _port(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final int? value = int.tryParse(trimmed);
    if (value == null || value < 1 || value > 65535) {
      return null;
    }
    return value;
  }

  /// Splits a pasted `address:port` across two fields.
  ///
  /// The phone shows one string — `192.168.1.42:37105` — and people paste it
  /// whole, which used to land in the address field and quietly fail
  /// validation. A single colon, or a bracketed IPv6 literal, is a split; a
  /// bare `fe80::1` is not, because its tail is not a port.
  void _spread(String raw, TextEditingController port) {
    final int cut = raw.lastIndexOf(':');
    if (cut <= 0 || cut == raw.length - 1) {
      return;
    }
    final String head = raw.substring(0, cut).trim();
    final String tail = raw.substring(cut + 1).trim();
    final bool splittable =
        head.endsWith(']') || ':'.allMatches(raw).length == 1;
    if (!splittable || head.isEmpty || _port(tail) == null) {
      return;
    }
    _host.value = TextEditingValue(
      text: head,
      selection: TextSelection.collapsed(offset: head.length),
    );
    port.text = tail;
  }

  // --------------------------------------------------------------- commands

  bool get _canPair =>
      !_busy &&
      _host.text.trim().isNotEmpty &&
      _port(_pairingPort.text) != null &&
      _code.text.length == 6;

  Future<void> _pairManually() async {
    if (!_canPair) {
      return;
    }
    final String host = _host.text.trim();
    final int port = _port(_pairingPort.text)!;
    // Read once, then clear: the code must not survive submission, must not
    // sit in a field while the command is in flight, and must not enter state.
    final String code = _code.text;
    _code.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    final OpenDexError? error = await widget.commands.pair(
      host: host,
      pairingPort: port,
      pairingCode: code,
    );
    if (!mounted) {
      return;
    }
    // The command already includes the follow-on connection attempt, so the
    // phase — connected, needsConnectionPort, or failed — is the answer. There
    // is deliberately no assumption here that a second step is required.
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _connectTo(String host, int port) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final CommandResult<DeviceSummary> result = await widget.commands.connect(
      host: host,
      port: port,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      switch (result) {
        case CommandSuccess<DeviceSummary>(:final DeviceSummary value):
          // An authorized ADB transport, not a session. The person still
          // chooses it and connects, the same as any other phone.
          _linked = value;
        case CommandFailure<DeviceSummary>(:final OpenDexError error):
          _error = error;
      }
    });
  }

  Future<void> _connectFromField() async {
    final String host = _host.text.trim().isEmpty
        ? (_pairing.host ?? '')
        : _host.text.trim();
    final int? port = _port(_connectPort.text);
    if (host.isEmpty || port == null) {
      return;
    }
    await _connectTo(host, port);
  }

  Future<void> _startQr() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final OpenDexError? error = await widget.commands.startQrPairing();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final OpenDexError? error = await widget.commands.cancelPairing();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _linked = null;
      _error = error;
      _connectPort.clear();
    });
  }

  Future<void> _disconnect(String deviceId) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _disconnecting = deviceId;
      _error = null;
    });
    final OpenDexError? error = await widget.commands.disconnectWireless(
      deviceId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _disconnecting = null;
      _error = error;
      if (_linked?.id == deviceId) {
        _linked = null;
      }
    });
  }

  /// Fills the manual form from an advertisement and puts the caret on the
  /// code. Deliberately not a pairing attempt: an advertisement is a hint, and
  /// the six digits only the phone knows are still required.
  void _useHint(WirelessAdvertisement ad) {
    _host.text = ad.host;
    _pairingPort.text = '${ad.port}';
    _code.clear();
    setState(() {
      _mode = WirelessMode.manual;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _codeFocus.requestFocus();
      }
    });
  }

  void _setMode(WirelessMode mode) {
    if (mode == _mode) {
      return;
    }
    // Leaving the QR tab ends the QR session rather than leaving a live
    // payload behind a tab nobody is looking at.
    if (_mode == WirelessMode.qr &&
        _pairing.phase == WirelessPairingPhase.waitingForScan) {
      unawaited(widget.commands.cancelPairing());
    }
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  void _openWorkspace(DeviceSummary device) {
    widget.onSelect(device.id);
    widget.onConnectSelected();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;

    final Widget body = Dialog(
      insetPadding: const EdgeInsets.all(DexSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(DexSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Entrance(child: _header(c)),
              const SizedBox(height: DexSpace.lg),
              Flexible(child: Entrance(order: 1, child: _columns())),
              const SizedBox(height: DexSpace.lg),
              Entrance(order: 2, child: _footer()),
            ],
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

  Widget _header(DexColors c) {
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'HARDWARE MANAGER',
                style: DexTheme.data(
                  c,
                  size: 9,
                  color: c.signal,
                ).copyWith(letterSpacing: 1.6),
              ),
              const SizedBox(height: DexSpace.xs),
              Text('Manage Android Phones', style: t.titleLarge),
              const SizedBox(height: DexSpace.xs),
              Text(
                'Plug in over USB with USB debugging on, or add one over '
                'Wi-Fi. Both end up in the same list.',
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: DexSpace.md),
        IconButton(
          onPressed: widget.onClose,
          tooltip: 'Close',
          icon: const Icon(DexIcons.close),
        ),
      ],
    );
  }

  Widget _columns() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget phones = PhoneList(
          status: widget.deviceStatus,
          devices: widget.devices,
          selectedId: widget.selectedId,
          onSelect: widget.onSelect,
          onRefresh: widget.onRefreshDevices,
          onConnect: widget.onConnectSelected,
          onDisconnect: _disconnect,
          busy: _busy,
          busyDeviceId: _disconnecting,
        );
        final Widget wireless = _wirelessPanel();

        if (constraints.maxWidth < 760) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                phones,
                const SizedBox(height: DexSpace.lg),
                wireless,
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 5, child: SingleChildScrollView(child: phones)),
            const SizedBox(width: DexSpace.lg),
            Expanded(flex: 6, child: SingleChildScrollView(child: wireless)),
          ],
        );
      },
    );
  }

  Widget _footer() {
    return Row(
      children: <Widget>[
        Working(busy: _busy),
        const Spacer(),
        TextButton(onPressed: widget.onClose, child: const Text('Close')),
      ],
    );
  }

  // --------------------------------------------------------------- wireless

  Widget _wirelessPanel() {
    return ConnectPanel(
      title: 'Add over Wi-Fi',
      subtitle: _pairingInFlight
          ? 'Working with the phone.'
          : 'Android 11 and later. Wireless debugging must be on.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The switch disappears while an exchange is in flight. Leaving it
          // up would offer a way to walk out of a half-finished pairing into a
          // fresh QR code, which is exactly the confusion the single screen is
          // meant to remove.
          if (!_pairingInFlight) ...<Widget>[
            WirelessModeBar(mode: _mode, onChanged: _setMode),
            const SizedBox(height: DexSpace.lg),
          ],
          AnimatedSwitcher(
            duration: DexMotion.enabled(context)
                ? DexDuration.standard
                : Duration.zero,
            switchInCurve: DexMotion.arrive,
            child: _wirelessBody(),
          ),
        ],
      ),
    );
  }

  Widget _wirelessBody() {
    // A pairing in flight owns the panel: the QR, the nearby list and the
    // manual form all step aside, which is what makes "the code disappears the
    // moment pairing begins" a structural fact rather than a rule to remember.
    if (_pairingInFlight) {
      return KeyedSubtree(
        key: const ValueKey<String>('wireless-progress'),
        child: PairingProgressBody(
          pairing: _pairing,
          error: _error,
          host: _pairing.host ?? _host.text.trim(),
          connectPort: _connectPort,
          device: _connected,
          busy: _busy,
          canConnect: _port(_connectPort.text) != null,
          onCancel: _cancel,
          onConnect: _connectFromField,
          onChanged: () => setState(() {}),
          onOpenWorkspace: _openWorkspace,
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey<String>('wireless-${_mode.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_pairing.phase == WirelessPairingPhase.expired) ...<Widget>[
            const ConnectNotice(
              title: 'That code expired',
              detail:
                  'Pairing codes last about two minutes. Generate a new one, '
                  'or read the fresh digits off the phone.',
            ),
            const SizedBox(height: DexSpace.md),
          ],
          if (_pairing.phase == WirelessPairingPhase.failed &&
              _pairing.error != null) ...<Widget>[
            InlineError(
              error: _pairing.error!,
              guidance:
                  'The phone shows a new code each time that screen opens — '
                  'read it again and retry.',
            ),
            const SizedBox(height: DexSpace.md),
          ],
          if (_error != null) ...<Widget>[
            InlineError(error: _error!),
            const SizedBox(height: DexSpace.md),
          ],
          switch (_mode) {
            WirelessMode.nearby => NearbyBody(
              discovery: widget.discovery,
              clock: widget.clock,
              busy: _busy,
              onPairManually: () => _setMode(WirelessMode.manual),
              onUseHint: _useHint,
              onConnect: _connectTo,
            ),
            WirelessMode.qr => QrBody(
              pairing: _pairing,
              clock: widget.clock,
              busy: _busy,
              onStart: _startQr,
              onCancel: _cancel,
            ),
            WirelessMode.manual => ManualBody(
              host: _host,
              pairingPort: _pairingPort,
              code: _code,
              codeFocus: _codeFocus,
              busy: _busy,
              canPair: _canPair,
              onHostChanged: (String value) {
                _spread(value, _pairingPort);
                setState(() {});
              },
              onChanged: () => setState(() {}),
              onPair: _pairManually,
            ),
          },
        ],
      ),
    );
  }
}
