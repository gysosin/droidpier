import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';

/// The reference's switch: a 40×24 pill with a 20px knob that slides 16px,
/// signal when on and glass when off. Material's switch is wider, taller and
/// carries an outline and a state layer this design does not have.
///
/// Exposes the same semantics a switch does — toggled, enabled, a label — so
/// the row it sits in reads correctly and its tests can find it by name.
class DexToggle extends StatelessWidget {
  const DexToggle({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;

  /// Null disables the toggle.
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final bool enabled = onChanged != null;
    final Duration d = DexMotion.enabled(context)
        ? DexDuration.micro
        : Duration.zero;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            // The pill is 40×24; the box around it is the 24px minimum hit
            // target either way, and a touch of width so a miss still lands.
            width: 44,
            height: DexHit.minimum,
            child: Center(
              child: AnimatedContainer(
                duration: d,
                curve: DexMotion.arrive,
                width: 40,
                height: 24,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: value ? c.signal : glass.fillStrong,
                  borderRadius: BorderRadius.circular(DexRadius.pill),
                ),
                child: AnimatedAlign(
                  duration: d,
                  curve: DexMotion.arrive,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: c.bg.computeLuminance() > 0.5
                          ? c.bg
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
