import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_glyph.dart';
import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';
import '../util/app_display_name.dart';

/// Apps on the desk itself.
///
/// The reference fills the left of the desk with a column-major grid of app
/// icons, and it is the thing that makes the desk read as a desktop rather than
/// as a wallpaper with a taskbar. Without it the whole left two-thirds of the
/// screen is dead space.
///
/// A single column down the left edge, which is what the reference shows. The
/// drawer holds every app and has search; the desk is for the few you reach for
/// without thinking.
class DeskIcons extends StatelessWidget {
  const DeskIcons({
    required this.applications,
    required this.onLaunch,
    super.key,
  });

  final List<AndroidApplication> applications;
  final ValueChanged<AndroidApplication> onLaunch;

  /// One tile plus its label. Public because the desk has to reserve room for
  /// this column before deciding whether the phone mirror also fits.
  static const double tileWidth = 92;

  /// 104, not 96.
  ///
  /// The tile holds a 48px glyph, a gap, and up to two lines of label. At 96
  /// that came to six pixels more than the box on a two-line name — "Ball Sort
  /// Puzzle" is enough to trigger it — and the person got a striped overflow
  /// banner where their app should be. Found by running the product rather
  /// than by any widget test, because every test that renders this passes a
  /// name short enough to fit on one line.
  static const double _tileHeight = 104;

  @override
  Widget build(BuildContext context) {
    final List<AndroidApplication> apps = applications
        .where((AndroidApplication a) => !a.isSystemApp)
        .toList();
    if (apps.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A short single column of a few favourites, not a wall of every app
        // the phone owns — the drawer holds all of them and has search. Kept
        // deliberately small so the desk stays a desk, not a second launcher.
        final int rows = ((constraints.maxHeight - DexSpace.xl) / _tileHeight)
            .floor()
            .clamp(1, 6);
        final List<AndroidApplication> shown = apps.take(rows).toList();

        return Padding(
          padding: const EdgeInsets.all(DexSpace.xl),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: rows * _tileHeight,
              child: Wrap(
                direction: Axis.vertical,
                children: <Widget>[
                  for (int i = 0; i < shown.length; i++)
                    Entrance(
                      // Staggered along the reading order of the grid, so the
                      // desk assembles rather than appearing all at once.
                      order: i,
                      child: _DeskIcon(
                        app: shown[i],
                        onLaunch: () => onLaunch(shown[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeskIcon extends StatelessWidget {
  const _DeskIcon({required this.app, required this.onLaunch});

  final AndroidApplication app;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final String shown = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;

    return Semantics(
      button: true,
      label: 'Open $shown',
      child: Tooltip(
        message: shown,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onLaunch,
            borderRadius: BorderRadius.circular(DexRadius.dialog),
            child: AnimatedContainer(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              width: DeskIcons.tileWidth,
              height: DeskIcons._tileHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: DexSpace.xs,
                vertical: DexSpace.sm,
              ),
              decoration: BoxDecoration(
                // At rest the tile is invisible — icons sit on the wallpaper,
                // not in boxes. The glass appears under the pointer.
                color: hovered ? glass.fill : Colors.transparent,
                borderRadius: BorderRadius.circular(DexRadius.dialog),
                border: Border.all(
                  color: hovered ? glass.stroke : Colors.transparent,
                  width: DexStroke.hairline,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedScale(
                    duration: DexDuration.micro,
                    curve: DexMotion.arrive,
                    scale: hovered ? 1.06 : 1,
                    child: AppGlyph(app: app, size: 48),
                  ),
                  const SizedBox(height: DexSpace.sm),
                  // Flexible as well as taller. The height above is sized for
                  // this app's own fonts, and a system fallback face with
                  // taller metrics would put it back over the edge — which is
                  // exactly how a clock overflowed here once before. Yielding
                  // costs a clipped second line; not yielding costs a striped
                  // banner across the icon.
                  Flexible(
                    child: Text(
                      shown,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: c.text,
                        height: 1.25,
                        // The wallpaper is bright in places; without a shadow the
                        // label loses its edge over the lit corner.
                        shadows: const <Shadow>[
                          Shadow(color: Color(0x99000000), blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
