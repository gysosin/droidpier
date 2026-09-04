import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// Recovery overlay. The Link Rail's third state: when the link drops, the
/// same instrument the user watched during boot comes back, so waiting is
/// legible rather than opaque.
class RecoveryOverlay extends StatelessWidget {
  const RecoveryOverlay({
    required this.recovery,
    required this.onReconnect,
    required this.onDisconnect,
    super.key,
  });

  final RecoveryState recovery;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  /// Phase in the user's words, never the system's.
  String get _headline => switch (recovery.phase) {
    RecoveryPhase.idle => 'Connected',
    RecoveryPhase.detecting => 'Checking the connection…',
    RecoveryPhase.reconnecting => 'Reconnecting…',
    RecoveryPhase.restartingServices => 'Restarting phone services…',
    RecoveryPhase.recovered => 'Reconnected',
    RecoveryPhase.failed => 'Phone disconnected',
  };

  String get _detail => switch (recovery.phase) {
    RecoveryPhase.failed => 'Check the cable, then choose “Reconnect”.',
    RecoveryPhase.recovered => 'Your workspace is back.',
    _ => 'Keep the cable connected.',
  };

  bool get _isFailed => recovery.phase == RecoveryPhase.failed;
  bool get _isWorking =>
      recovery.phase == RecoveryPhase.detecting ||
      recovery.phase == RecoveryPhase.reconnecting ||
      recovery.phase == RecoveryPhase.restartingServices;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    // Material ancestor: this overlay is placed over arbitrary content and is
    // not inside a Scaffold, so nothing else provides one. Without it, Text
    // loses its default style and renders with the debug underline.
    return Material(
      color: c.bg.withValues(alpha: 0.92),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.all(DexSpace.xl),
            padding: const EdgeInsets.all(DexSpace.xl),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(DexRadius.dialog),
              border: Border.all(
                color: _isFailed ? c.fault : c.line,
                width: DexStroke.hairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // A ring carrying the phase, above the headline, as the
                // reference lays this card out. Colour alone is not a signal,
                // so the shape changes too: a cable while reconnecting, a
                // check once recovered, a fault mark when it has given up.
                _PhaseRing(phase: recovery.phase, colors: c),
                const SizedBox(height: DexSpace.lg),
                Text(
                  _headline,
                  textAlign: TextAlign.center,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: DexSpace.xs),
                // What happened, then what to do — in that order.
                if (recovery.error != null) ...<Widget>[
                  Text(
                    recovery.error!.message,
                    style: t.bodyMedium?.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: DexSpace.sm),
                ],
                Text(_detail, style: t.bodyMedium?.copyWith(color: c.text)),
                if (recovery.attempt > 0) ...<Widget>[
                  const SizedBox(height: DexSpace.md),
                  Text(
                    'attempt ${recovery.attempt}',
                    style: DexTheme.data(c, size: 11),
                  ),
                ],
                const SizedBox(height: DexSpace.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (_isFailed)
                      OutlinedButton(
                        onPressed: onDisconnect,
                        child: const Text('Disconnect'),
                      ),
                    if (_isFailed) const SizedBox(width: DexSpace.sm),
                    FilledButton(
                      onPressed: _isWorking ? null : onReconnect,
                      child: const Text('Reconnect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed Link Rail trace, travelling while recovery is in progress.
/// The phase, as a ringed mark.
///
/// Static. The reference spins and bounces this one, and it would be safe
/// here — the overlay is unmounted on an idle desk, so `idle_cost_test` never
/// sees it — but the pulse trace beside the headline already carries the fact
/// that something is happening, and two moving things saying one thing is
/// decoration. The colour and the shape carry the phase.
class _PhaseRing extends StatelessWidget {
  const _PhaseRing({required this.phase, required this.colors});

  final RecoveryPhase phase;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour) = switch (phase) {
      RecoveryPhase.recovered => (DexIcons.check, colors.trace),
      RecoveryPhase.failed => (DexIcons.fault, colors.fault),
      RecoveryPhase.reconnecting => (DexIcons.usb, colors.warn),
      _ => (DexIcons.wifiTethering, colors.signal),
    };
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.20),
        border: Border.all(color: colour, width: DexStroke.focusRing),
      ),
      child: Icon(icon, size: 24, color: colour),
    );
  }
}

class _PulseTrace extends StatefulWidget {
  const _PulseTrace({required this.color});

  final Color color;

  @override
  State<_PulseTrace> createState() => _PulseTraceState();
}

class _PulseTraceState extends State<_PulseTrace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double height = 28;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: DexStroke.railTrace,
        height: height,
        color: widget.color,
      );
    }
    return SizedBox(
      width: DexStroke.railTrace,
      height: height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _TracePainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint track = Paint()..color = color.withValues(alpha: 0.2);
    canvas.drawRect(Offset.zero & size, track);

    const double runLength = 0.4;
    final double top = (progress * (1 + runLength) - runLength) * size.height;
    final Paint run = Paint()..color = color;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, size.height * runLength),
      run,
    );
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.progress != progress || old.color != color;
}
