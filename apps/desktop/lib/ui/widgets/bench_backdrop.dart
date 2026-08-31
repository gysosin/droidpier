import 'package:flutter/material.dart';

import '../theme/dex_colors.dart';
import '../theme/glass.dart';

/// The wallpaper — the single ground every full-screen surface sits on.
///
/// Boot and the desk share it deliberately: when the link comes up the ground
/// stays put and only the content changes, instead of the whole screen
/// swapping out from under the person.
///
/// Drawn rather than shipped as an image: it stays sharp at any window size,
/// adds nothing to the bundle, and follows the theme. Blue falling through
/// indigo to violet, lit from the top-right and darkened toward the taskbar.
class BenchBackdrop extends StatelessWidget {
  const BenchBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[const DexWallpaper(), child],
    );
  }
}

class DexWallpaper extends StatelessWidget {
  const DexWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    // The gradient, bloom and vignette all live in [DeskWallpaper] so the
    // phone mirror can paint the same ground at a different size.
    return const DeskWallpaper(child: SizedBox.expand());
  }
}

/// The product mark: a link between two bodies. Drawn, not an icon font, so it
/// carries the same signal semantics as the rest of the chrome.
class DexMark extends StatelessWidget {
  const DexMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(c.signal, c.muted)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.signal, this.muted);

  final Color signal;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 24;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..strokeCap = StrokeCap.round
      ..color = muted;

    // Two bodies: the phone (small) and the desk (large).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2 * u, 6 * u, 7 * u, 12 * u),
        Radius.circular(1.5 * u),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(14 * u, 4 * u, 8 * u, 11 * u),
        Radius.circular(1.5 * u),
      ),
      stroke,
    );
    // The link, in signal.
    canvas.drawLine(
      Offset(9 * u, 12 * u),
      Offset(14 * u, 9.5 * u),
      Paint()
        ..strokeWidth = 2 * u
        ..strokeCap = StrokeCap.round
        ..color = signal,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.signal != signal || old.muted != muted;
}
