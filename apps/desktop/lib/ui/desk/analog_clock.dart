import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/dex_colors.dart';

/// A drawn analog clock face: a dark disc with tick marks, white hour and
/// minute hands, and a blue second hand.
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
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _ClockPainter(
            now: _now,
            signal: c.signal,
            seconds: widget.showSeconds,
          ),
        ),
      ),
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

    // Face: a dark disc with a faint lift toward the top-left and a hairline rim.
    final Rect face = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: <Color>[const Color(0xFF23272E), const Color(0xFF0E1116)],
        ).createShader(face),
    );
    canvas.drawCircle(
      center,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    // Ticks: 60 minor; the 12/3/6/9 quarters are the thickest and longest,
    // other fifths medium, the rest hairline — as in the reference face.
    for (int i = 0; i < 60; i++) {
      final double a = i * math.pi / 30 - math.pi / 2;
      final bool quarter = i % 15 == 0;
      final bool major = i % 5 == 0;
      final double inner = r * (quarter ? 0.78 : (major ? 0.83 : 0.88));
      final double outer = r * 0.93;
      canvas.drawLine(
        center + Offset(math.cos(a) * inner, math.sin(a) * inner),
        center + Offset(math.cos(a) * outer, math.sin(a) * outer),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = quarter
              ? r * 0.032
              : (major ? r * 0.016 : r * 0.008)
          ..color = Colors.white.withValues(
            alpha: quarter ? 0.9 : (major ? 0.6 : 0.25),
          ),
      );
    }

    void hand(double angle, double length, double width, Color color) {
      canvas.drawLine(
        center - Offset(math.cos(angle) * length * 0.18, math.sin(angle) * length * 0.18),
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
    hand(hourAngle, r * 0.50, r * 0.055, Colors.white);
    hand(minuteAngle, r * 0.74, r * 0.038, Colors.white);

    if (seconds) {
      final double secondAngle = now.second * math.pi / 30 - math.pi / 2;
      hand(secondAngle, r * 0.80, r * 0.014, signal);
    }

    // Centre cap.
    canvas.drawCircle(center, r * 0.045, Paint()..color = Colors.white);
    canvas.drawCircle(center, r * 0.022, Paint()..color = signal);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.now.minute != now.minute ||
      old.now.second != now.second ||
      old.signal != signal ||
      old.seconds != seconds;
}
