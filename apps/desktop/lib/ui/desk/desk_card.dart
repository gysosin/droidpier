import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// Widget sizes, following the desktop convention people already know from
/// macOS and DeX: medium is a glance plus a control,
/// is a short list.
enum DeskCardSize {
  medium(340, 160),
  feature(300, 320);

  const DeskCardSize(this.width, this.height);

  final double width;
  final double height;
}

/// A desk widget.
///
/// Both macOS Sonoma and One UI 8 land on the same behaviour: widgets sit on
/// the wallpaper permanently and *recede* when the person is working in an app,
/// rather than competing with it. [recessive] is that state — the card keeps
/// its shape and loses its contrast, so the desk stays readable without
/// shouting.
class DeskCard extends StatelessWidget {
  const DeskCard({
    required this.label,
    required this.child,
    this.size = DeskCardSize.medium,
    this.recessive = false,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;
  final DeskCardSize size;
  final bool recessive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;

    return AnimatedOpacity(
      duration: DexDuration.standard,
      curve: DexMotion.arrive,
      opacity: recessive ? 0.5 : 1,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: GlassPanel(
          radius: DexRadius.panel,
          // Borderless: desk widgets read as soft glass over the wallpaper, set
          // apart by fill and shadow rather than a hairline edge.
          stroke: Colors.transparent,
          padding: const EdgeInsets.all(DexSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: DexTheme.data(
                      c,
                      size: 9,
                      color: c.muted,
                    ).copyWith(letterSpacing: 1.4),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
              const SizedBox(height: DexSpace.sm),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
