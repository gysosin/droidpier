import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/glass.dart';

/// The desk clock: a glass disc, twelve marks, and an accent second hand.
///
/// Drawn to the reference's geometry, which is specified at 280px and scaled
/// from there — twelve marks rather than sixty, hands of 62 / 92 / 108, a 2px
/// second hand with an 18px counterbalance behind the pin, and a quiet
/// DROIDPIER / DESK block set above centre.
///
/// The face is glass, not a painted gradient. It used to be an opaque
/// `#23272E` to `#0E1116` disc, which is the one thing on the desk that did
/// not let the wallpaper through, and in light mode it stayed black.
///
/// Painted rather than shipped as an image so it stays crisp at any size and
/// follows the theme's signal colour for the second hand.
///
/// When [live], it runs its own one-second ticker and repaints only itself
/// (wrapped in a `RepaintBoundary`), so the second hand is truly live without
/// the whole shell — which ticks far more slowly — rebuilding behind it. When
/// not live (tests, goldens) it paints the fixed [now] and never ticks.
class AnalogClock extends StatefulWidget {
  const AnalogClock({
    required this.now,
    this.showSeconds = true,
    this.live = false,
    super.key,
  });

  final DateTime now;
  final bool showSeconds;
  final bool live;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock> {
  Timer? _timer;
  late DateTime _now = widget.now;

  @override
  void initState() {
    super.initState();
    if (widget.live) _startTicking();
  }

  @override
  void didUpdateWidget(AnalogClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live && _timer == null) {
      _startTicking();
    } else if (!widget.live) {
      _timer?.cancel();
      _timer = null;
      _now = widget.now;
    }
  }

  void _startTicking() {
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    // The face blurs what is behind it, and stops while a window streams, for
    // the same reason every other panel does.
    final bool blurred = GlassBlurScope.of(context);
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipOval(
          child: _Backdrop(
            blurred: blurred,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Everything below is the reference's geometry at 280px.
                final double k = constraints.maxWidth / 280;
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: _ClockPainter(
                        now: _now,
                        signal: c.signal,
                        seconds: widget.showSeconds,
                      ),
                    ),
                    // Set above centre so the hands do not run through it.
                    Align(
                      alignment: Alignment(0, -40 * k / (140 * k)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'DROIDPIER',
                            style: DexTheme.data(
                              c,
                              size: 10 * k,
                              color: Colors.white.withValues(alpha: 0.40),
                            ).copyWith(
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2 * k,
                            ),
                          ),
                          Text(
                            'DESK',
                            style: DexTheme.data(
                              c,
                              size: 8 * k,
                              color: Colors.white.withValues(alpha: 0.20),
                            ).copyWith(letterSpacing: 1 * k),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Blurs the wallpaper behind the dial when the desk allows it.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.blurred, required this.child});

  final bool blurred;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!blurred) return child;
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: child,
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.now,
    required this.signal,
    required this.seconds,
  });

  final DateTime now;
  final Color signal;
  final bool seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final double k = r / 140;
    final Rect face = Rect.fromCircle(center: center, radius: r);

    // Glass: slate at 70%, with the wallpaper showing through, plus the
    // reference's faint radial sheen.
    canvas.drawCircle(
      center,
      r,
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.70),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(face),
    );
    // The inset hairline ring from the reference's second box-shadow.
    canvas.drawCircle(
      center,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // Twelve marks, every third one long and bright. Each sits 12px in from
    // the rim, and runs 12px or 6px inward from there.
    for (int i = 0; i < 12; i++) {
      final double a = i * math.pi / 6 - math.pi / 2;
      final bool major = i % 3 == 0;
      final double outer = r - 12 * k;
      final double inner = outer - (major ? 12 : 6) * k;
      canvas.drawLine(
        center + Offset(math.cos(a) * inner, math.sin(a) * inner),
        center + Offset(math.cos(a) * outer, math.sin(a) * outer),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2 * k
          ..color = Colors.white.withValues(alpha: major ? 0.70 : 0.25),
      );
    }

    void hand(
      double angle,
      double length,
      double width,
      Color color, {
      double tail = 0,
    }) {
      canvas.drawLine(
        center - Offset(math.cos(angle) * tail, math.sin(angle) * tail),
        center + Offset(math.cos(angle) * length, math.sin(angle) * length),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color,
      );
    }

    final double hourAngle =
        (now.hour % 12 + now.minute / 60) * math.pi / 6 - math.pi / 2;
    final double minuteAngle =
        (now.minute + now.second / 60) * math.pi / 30 - math.pi / 2;
    hand(hourAngle, 62 * k, 6 * k, Colors.white);
    hand(
      minuteAngle,
      92 * k,
      4 * k,
      Colors.white.withValues(alpha: 0.90),
    );

    if (seconds) {
      final double secondAngle = now.second * math.pi / 30 - math.pi / 2;
      hand(secondAngle, 108 * k, 2 * k, signal, tail: 18 * k);
    }

    // Centre pin: a dark cap ringed in white, with the accent at its middle.
    canvas.drawCircle(center, 7 * k, Paint()..color = const Color(0xFF0B1120));
    canvas.drawCircle(
      center,
      6 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..color = Colors.white,
    );
    canvas.drawCircle(center, 2 * k, Paint()..color = signal);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.now.minute != now.minute ||
      old.now.second != now.second ||
      old.signal != signal ||
      old.seconds != seconds;
}
