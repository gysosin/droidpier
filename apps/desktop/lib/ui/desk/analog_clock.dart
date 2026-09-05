import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/glass.dart';

/// The desk clock: a glass disc, twelve marks, and an accent second hand.
///
/// The reference's geometry at 280px — a 70% slate face under a 12px blur, an
/// inset hairline, twelve marks with every third one long, hour and minute
/// hands in ink, a signal second hand with an 18px counterbalance behind the
/// pin, and a quiet DROIDPIER / DESK wordmark above centre.
///
/// The hands *move*, and that is the whole feel of it. The reference ticks
/// once a second and lets CSS carry each hand to its new angle — the second
/// hand in 100ms, linear; the hour and minute hands in 200ms, eased — so the
/// clock sweeps instead of jumping. This does the same: every tick starts a
/// short animation from the previous angles to the new ones, and the minute
/// hand creeps with the seconds as the reference's does. Between ticks nothing
/// repaints. Reduced motion turns the glide off and the hands step.
///
/// When [live], it runs its own one-second ticker; otherwise it follows [now]
/// and animates when that changes (the shell feeds it a clock), or paints the
/// fixed time (tests, goldens) and never ticks.
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

class _AnalogClockState extends State<AnalogClock>
    with SingleTickerProviderStateMixin {
  Timer? _timer;

  /// The angles being left and the angles being reached. Between ticks they
  /// are equal, and the painter draws [_to].
  late _Hands _from = _Hands.of(widget.now);
  late _Hands _to = _Hands.of(widget.now);

  /// One glide per tick. 200ms is the reference's hour and minute transition;
  /// the second hand uses the first half of it, which is its 100ms.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

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
      if (widget.now != oldWidget.now) _advanceTo(widget.now);
    }
  }

  void _startTicking() {
    _advanceTo(DateTime.now(), glide: false);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _advanceTo(DateTime.now());
    });
  }

  /// Moves the hands to [time]: with a glide when motion is on, in one step
  /// when it is not. A glide that is still running is simply retargeted from
  /// where the hands are now, so a late tick never snaps back.
  void _advanceTo(DateTime time, {bool glide = true}) {
    final _Hands next = _Hands.of(time);
    if (next == _to) return;
    final bool animate = glide && mounted && DexMotion.enabled(context);
    setState(() {
      _from = animate ? _current : next;
      _to = next;
    });
    if (animate) {
      _glide.forward(from: 0);
    } else {
      _glide.value = 1;
    }
  }

  /// Where the hands are at this instant of the glide.
  _Hands get _current => _Hands.lerp(_from, _to, _glide.value);

  @override
  void dispose() {
    _timer?.cancel();
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    // The face blurs what is behind it, and stops while a window streams, for
    // the same reason every other panel does.
    final DexGlass glass = DexGlass.of(context);
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
                    AnimatedBuilder(
                      animation: _glide,
                      builder: (BuildContext context, Widget? _) => CustomPaint(
                        painter: _ClockPainter(
                          hands: _Hands.lerp(_from, _to, _glide.value),
                          signal: c.signal,
                          // The dial is glass, so it flips with the theme like
                          // every other panel. The reference hardcodes it
                          // dark, which is part of its light mode being
                          // unfinished — a near-black disc on pale paper is
                          // the single most obvious thing wrong with that
                          // screen.
                          face: glass.substrate,
                          ink: c.text,
                          seconds: widget.showSeconds,
                        ),
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
                            style:
                                DexTheme.data(
                                  c,
                                  size: 10 * k,
                                  color: c.text.withValues(alpha: 0.40),
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
                              color: c.text.withValues(alpha: 0.20),
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

/// The three hands as angles in radians, measured clockwise from twelve.
///
/// Kept as a value so a glide can interpolate between two of them, and so
/// "the hands did not move" is one equality check rather than three.
@immutable
class _Hands {
  const _Hands({
    required this.hour,
    required this.minute,
    required this.second,
  });

  /// The reference's angles: the minute hand creeps with the seconds and the
  /// hour hand with the minutes, so neither ever sits on a mark it has
  /// already passed.
  factory _Hands.of(DateTime t) => _Hands(
    hour: (t.hour % 12 + t.minute / 60) * (2 * math.pi / 12),
    minute: (t.minute + t.second / 60) * (2 * math.pi / 60),
    second: t.second * (2 * math.pi / 60),
  );

  final double hour;
  final double minute;
  final double second;

  /// Between [a] and [b], always turning clockwise — a hand crossing twelve
  /// goes forward through it, never the long way back.
  static _Hands lerp(_Hands a, _Hands b, double t) {
    // The second hand takes the first half of the glide, linear, which is the
    // reference's 100ms of its 200ms; the others use the whole of it, eased.
    final double ts = (t * 2).clamp(0.0, 1.0);
    final double te = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    return _Hands(
      hour: _forward(a.hour, b.hour, te),
      minute: _forward(a.minute, b.minute, te),
      second: _forward(a.second, b.second, ts),
    );
  }

  static double _forward(double from, double to, double t) {
    final double delta = (to - from) % (2 * math.pi);
    return from + delta * t;
  }

  @override
  bool operator ==(Object other) =>
      other is _Hands &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

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
    required this.hands,
    required this.signal,
    required this.face,
    required this.ink,
    required this.seconds,
  });

  final _Hands hands;
  final Color signal;
  final Color face;
  final Color ink;
  final bool seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final double k = r / 140;
    final Rect bounds = Rect.fromCircle(center: center, radius: r);

    // Glass: slate at 70%, with the wallpaper showing through, plus the
    // reference's faint radial sheen.
    canvas.drawCircle(center, r, Paint()..color = face);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            ink.withValues(alpha: 0.04),
            ink.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    // The inset hairline ring from the reference's second box-shadow.
    canvas.drawCircle(
      center,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.12),
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
          ..color = ink.withValues(alpha: major ? 0.70 : 0.25),
      );
    }

    // Angles are clockwise from twelve; the canvas measures from three.
    void hand(
      double angle,
      double length,
      double width,
      Color color, {
      double tail = 0,
    }) {
      final double a = angle - math.pi / 2;
      canvas.drawLine(
        center - Offset(math.cos(a) * tail, math.sin(a) * tail),
        center + Offset(math.cos(a) * length, math.sin(a) * length),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color,
      );
    }

    hand(hands.hour, 62 * k, 6 * k, ink);
    hand(hands.minute, 92 * k, 4 * k, ink.withValues(alpha: 0.90));
    if (seconds) hand(hands.second, 108 * k, 2 * k, signal, tail: 18 * k);

    // Centre pin: a dark cap ringed in white, with the accent at its middle.
    canvas.drawCircle(center, 7 * k, Paint()..color = face);
    canvas.drawCircle(
      center,
      6 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..color = ink,
    );
    canvas.drawCircle(center, 2 * k, Paint()..color = signal);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.hands != hands ||
      old.signal != signal ||
      old.face != face ||
      old.ink != ink ||
      old.seconds != seconds;
}
