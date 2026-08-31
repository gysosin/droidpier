import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/dex_tokens.dart';

/// Shows [child] only once [visible] has held for [delay], and then keeps it
/// on screen for at least [floor].
///
/// This is the rule already encoded in [DexDuration.loadingDelay] and
/// [DexDuration.loadingFloor], applied to full-screen state rather than only to
/// spinners. A transport that dips in and out of recovery for 80 ms should not
/// tear the desk away and put it back — from the person's side that is not
/// information, it is a blink.
///
/// Deliberately asymmetric: appearing is delayed, disappearing is delayed only
/// by whatever remains of [floor]. A surface that is genuinely needed should
/// still arrive quickly, and one that is no longer needed should not linger
/// beyond the moment it stops being readable.
class Sustained extends StatefulWidget {
  const Sustained({
    required this.visible,
    required this.child,
    this.delay = DexDuration.loadingDelay,
    this.floor = DexDuration.loadingFloor,
    super.key,
  });

  final bool visible;
  final Widget child;
  final Duration delay;
  final Duration floor;

  @override
  State<Sustained> createState() => _SustainedState();
}

class _SustainedState extends State<Sustained> {
  bool _shown = false;
  Timer? _appear;
  Timer? _hold;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Sustained old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _sync();
  }

  void _sync() {
    _appear?.cancel();
    if (widget.visible) {
      if (_shown) return;
      _appear = Timer(widget.delay, () {
        if (!mounted || !widget.visible) return;
        setState(() {
          _shown = true;
          _held = true;
        });
        _hold?.cancel();
        _hold = Timer(widget.floor, () {
          if (!mounted) return;
          _held = false;
          // The condition may have cleared while the floor was running; this
          // is where a surface that is no longer needed finally goes.
          if (!widget.visible) setState(() => _shown = false);
        });
      });
      return;
    }
    if (_shown && !_held) {
      setState(() => _shown = false);
    }
  }

  @override
  void dispose() {
    _appear?.cancel();
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _shown ? widget.child : const SizedBox.shrink();
}
