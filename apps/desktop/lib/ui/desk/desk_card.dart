import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// A desk widget: 310 wide, as tall as what it holds.
///
/// Every card in the column shares one header idiom — an icon and an uppercase
/// mono label on the left, a chip or readout on the right, a hairline rule
/// under both — so the three read as one instrument rather than three panels
/// that happen to be stacked. That header used to be a bare 9px label, and the
/// cards had fixed heights that left the Now Playing card half empty and cut
/// the notifications card short.
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
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.recessive = false,
    super.key,
  });

  /// The reference's column width.
  static const double width = 310;

  final String label;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;

  /// Opens the surface this card previews. A card that is a preview of
  /// somewhere is a door to it.
  final VoidCallback? onTap;
  final bool recessive;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);

    final Widget body = GlassPanel(
      radius: DexRadius.panel,
      padding: const EdgeInsets.all(DexSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: DexIconSize.chrome,
                  color: iconColor ?? c.signal,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // tracking-wider is 0.05em, not 1.4px: at 1.4 "NOW PLAYING"
                  // no longer fit beside its chip and truncated to "NOW PLAYI…".
                  style: DexTheme.data(
                    c,
                    size: 11,
                    color: c.muted,
                  ).copyWith(letterSpacing: 0.55),
                ),
              ),
              const Spacer(),
              const SizedBox(width: DexSpace.sm),
              // Flexible, not a Spacer and a bare child: the right-hand slot
              // carries a device identity that can run long, and a header
              // that overflows its card is the first thing anyone would see.
              if (trailing != null) Flexible(child: trailing!),
            ],
          ),
          Container(
            height: DexStroke.hairline,
            margin: const EdgeInsets.only(top: DexSpace.sm, bottom: 10),
            color: glass.stroke,
          ),
          child,
        ],
      ),
    );

    return AnimatedOpacity(
      duration: DexDuration.standard,
      curve: DexMotion.arrive,
      opacity: recessive ? 0.4 : 1,
      child: SizedBox(
        width: width,
        child: onTap == null
            ? body
            : HoverLift(
                builder: (BuildContext context, bool hovered) => InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(DexRadius.panel),
                  child: body,
                ),
              ),
      ),
    );
  }
}
