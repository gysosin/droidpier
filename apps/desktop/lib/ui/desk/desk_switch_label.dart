import 'dart:async';

import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';

/// Names the desk just switched to, for a moment, then leaves for good.
///
/// A keyboard switch has no visible target: the windows change under the
/// pointer and nothing says why. This says "Desk 2" above the taskbar for
/// [hold], fades, and then removes itself entirely, so an idle desk carries
/// no timer, no animation and no extra widget from it. It never appears on
/// first build: the desk you started on needs no announcing.
class DeskSwitchLabel extends StatefulWidget {
  const DeskSwitchLabel({
    required this.workspace,
    this.hold = const Duration(milliseconds: 900),
    super.key,
  });

  final int workspace;
  final Duration hold;

  @override
  State<DeskSwitchLabel> createState() => _DeskSwitchLabelState();
}

class _DeskSwitchLabelState extends State<DeskSwitchLabel> {
  Timer? _timer;
  bool _visible = false;
  int? _shown;

  @override
  void didUpdateWidget(DeskSwitchLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace == widget.workspace) return;
    _timer?.cancel();
    setState(() {
      _visible = true;
      _shown = widget.workspace;
    });
    _timer = Timer(widget.hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: DexMotion.enabled(context)
              ? DexDuration.standard
              : Duration.zero,
          curve: DexMotion.arrive,
          // Once faded, the label is not hidden but gone, so nothing about it
          // is left in the tree to cost a frame.
          onEnd: () {
            if (!_visible && mounted) setState(() => _shown = null);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.lg,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              color: glass.substrate,
              borderRadius: BorderRadius.circular(DexRadius.pill),
              border: Border.all(
                color: glass.strokeStrong,
                width: DexStroke.hairline,
              ),
            ),
            child: Text(
              'Desk $shown',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: c.text),
            ),
          ),
        ),
      ),
    );
  }
}
