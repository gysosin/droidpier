import 'package:flutter/material.dart';

import '../theme/dex_tokens.dart';

/// Motion vocabulary.
///
/// Dials for this product: variance 6, motion 5, density 6 — an instrument for
/// technical users. Motion is used to show *state changing*, never to decorate.
/// Only `transform` and `opacity` are animated.
abstract final class DexMotion {
  /// Settling curve: fast out, gentle in. Used for anything arriving.
  static const Curve arrive = Curves.easeOutCubic;

  /// Symmetric curve for values that move both ways.
  static const Curve settle = Curves.easeInOut;

  /// Gap between staggered siblings.
  static const Duration stagger = Duration(milliseconds: 55);

  /// Whether motion is permitted at all in this context.
  ///
  /// The platform's own reduce-motion setting always wins, and the in-app
  /// preference can only add to it. There is deliberately no way to express
  /// "animate anyway": reducing motion is an accessibility choice, and an
  /// application setting does not get a vote on reversing one.
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context) &&
      !ReduceMotionScope.of(context);
}

/// Staggered entrance: fade plus a short rise.
///
/// Screens read as assembling rather than snapping into place. [order] is the
/// element's position in the choreography, so a screen declares its own rhythm
/// instead of every widget guessing.
class Entrance extends StatefulWidget {
  const Entrance({
    required this.child,
    this.order = 0,
    this.rise = 10,
    super.key,
  });

  final Widget child;
  final int order;
  final double rise;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DexDuration.enter,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Beyond this the stagger stops accumulating.
  ///
  /// The delay is `stagger * order`, which is right for the four desk widgets
  /// it was written for. The desk icon grid passes an index, and a phone with
  /// 77 apps made the last icons arrive seconds after the first — a staggered
  /// entrance became a slow load. Capping keeps the sense of the sequence
  /// without letting it run away with the list length.
  static const int _maxStaggerSteps = 10;

  Future<void> _start() async {
    final int steps = widget.order.clamp(0, _maxStaggerSteps);
    await Future<void>.delayed(DexMotion.stagger * steps);
    if (mounted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DexMotion.enabled(context)) {
      return widget.child;
    }
    final Animation<double> t = CurvedAnimation(
      parent: _controller,
      curve: DexMotion.arrive,
    );
    return AnimatedBuilder(
      animation: t,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: t.value,
          child: Transform.translate(
            offset: Offset(0, widget.rise * (1 - t.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A value that cross-fades when it changes.
///
/// Used for readouts: the number swaps without the row jumping, which matters
/// because these update continuously.
class SwapText extends StatelessWidget {
  const SwapText(this.value, {required this.style, super.key});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (!DexMotion.enabled(context)) {
      return Text(value, style: style);
    }
    return AnimatedSwitcher(
      duration: DexDuration.standard,
      switchInCurve: DexMotion.arrive,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(value, key: ValueKey<String>(value), style: style),
    );
  }
}

/// Desktop hover response. A pointer is a first-class input here, so surfaces
/// answer it — brightening and lifting by a hair, never bouncing.
class HoverLift extends StatefulWidget {
  const HoverLift({required this.builder, this.enabled = true, super.key});

  final Widget Function(BuildContext context, bool hovered) builder;
  final bool enabled;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _hovered && widget.enabled;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        duration: DexDuration.micro,
        curve: DexMotion.arrive,
        offset: active && DexMotion.enabled(context)
            ? const Offset(0, -0.012)
            : Offset.zero,
        child: widget.builder(context, active),
      ),
    );
  }
}

/// Carries the in-app reduce-motion preference down the tree.
///
/// A scope rather than a parameter because motion is checked deep inside
/// individual widgets — [Entrance], [SwapText], [HoverLift] — and threading a
/// flag through every one of them would guarantee that some widget was missed.
class ReduceMotionScope extends InheritedWidget {
  const ReduceMotionScope({
    required this.reduce,
    required super.child,
    super.key,
  });

  final bool reduce;

  /// False when no scope is present, so the platform setting decides alone —
  /// which is what every existing caller already relied on.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReduceMotionScope>()?.reduce ??
      false;

  @override
  bool updateShouldNotify(ReduceMotionScope oldWidget) =>
      oldWidget.reduce != reduce;
}

/// One short entrance for anything that opens over the desk.
///
/// The reference names two animations on every overlay — `fade-in` for the
/// scrim, `scale-up` for the card — and defines neither, so its surfaces
/// snap. This is the motion those names describe: the scrim fades over
/// [DexDuration.standard]; the card fades and grows from 96% over
/// [DexDuration.enter], on [DexMotion.arrive]. Opacity and transform only.
/// It runs once, when the surface first appears, and then nothing repaints;
/// closing is instant, because a dismiss must not lag the key that asked for
/// it. Reduced motion arrives at once.
class OverlayEntrance extends StatefulWidget {
  /// A panel or modal card: fades and scales in.
  const OverlayEntrance.card({required this.child, super.key})
    : scales = true,
      duration = DexDuration.enter;

  /// A full-screen tint: fades in only.
  const OverlayEntrance.scrim({required this.child, super.key})
    : scales = false,
      duration = DexDuration.standard;

  final Widget child;
  final bool scales;
  final Duration duration;

  @override
  State<OverlayEntrance> createState() => _OverlayEntranceState();
}

class _OverlayEntranceState extends State<OverlayEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DexMotion.enabled(context)) {
      _t.forward();
    } else {
      _t.value = 1;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double v = DexMotion.arrive.transform(_t.value);
        final Widget faded = Opacity(opacity: v, child: child);
        if (!widget.scales) return faded;
        return Transform.scale(scale: 0.96 + 0.04 * v, child: faded);
      },
    );
  }
}
