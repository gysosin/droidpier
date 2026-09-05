import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_tokens.dart';
import '../theme/dex_glass.dart';
import '../theme/glass.dart';

/// The Link Rail — the signature element of DroidPier.
///
/// It renders the real transport topology as a single instrument: `ADB` →
/// `Device` → `Agent :3698` → `Companion :3699` → `Applications`. Stations come
/// straight from [BootState.stages], so the rail is driven by the contract
/// rather than by a UI-local guess.
///
/// It has one expanded form (used during boot and recovery) and one collapsed
/// form (a live trace once connected), so the user learns a single object.
class LinkRail extends StatelessWidget {
  const LinkRail({required this.stages, super.key});

  final List<BootStage> stages;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < stages.length; i++)
          _Station(stage: stages[i], colors: c, isLast: i == stages.length - 1),
      ],
    );
  }
}

class _Station extends StatelessWidget {
  const _Station({
    required this.stage,
    required this.colors,
    required this.isLast,
  });

  final BootStage stage;
  final DexColors colors;
  final bool isLast;

  Color get _color => switch (stage.status) {
    StageStatus.complete => colors.signal,
    StageStatus.active => colors.signal,
    StageStatus.failed => colors.fault,
    StageStatus.pending => colors.muted,
  };

  /// The station's state, spoken the way a person would read the rail.
  String get _semanticStatus => switch (stage.status) {
    StageStatus.complete => 'connected',
    StageStatus.active => 'connecting',
    StageStatus.failed => 'failed',
    StageStatus.pending => 'waiting',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${stage.label}, $_semanticStatus',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                _StationNode(
                  color: _color,
                  status: stage.status,
                  colors: colors,
                ),
                if (!isLast)
                  Expanded(
                    // The rail is one continuous line, not a stack of dashes.
                    // A completed segment fills with signal — the fill is the
                    // progress, so it animates rather than snapping.
                    child: _RailSegment(
                      filled: stage.status == StageStatus.complete,
                      colors: colors,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: DexSpace.md),
            Expanded(
              child: Padding(
                // The reference spaces stations at pb-7; the node is 28 so the
                // label sits on its centre line.
                padding: const EdgeInsets.only(top: 4, bottom: DexSpace.xl + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // Station labels carry ports, so they are machine
                        // values, but the reference sets them in the body face
                        // at medium weight and keeps mono for the detail line.
                        Expanded(
                          child: Text(
                            stage.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: switch (stage.status) {
                                    StageStatus.pending => colors.muted,
                                    StageStatus.active => colors.signal,
                                    StageStatus.failed => colors.fault,
                                    StageStatus.complete => colors.text,
                                  },
                                ),
                          ),
                        ),
                        // The status word, spelled out. A ring and a disc
                        // already say it; this is for anyone who cannot tell
                        // the two apart at a glance.
                        Text(
                          stage.status.name.toUpperCase(),
                          style: DexTheme.data(colors, size: 11),
                        ),
                      ],
                    ),
                    if (stage.detail != null) ...<Widget>[
                      const SizedBox(height: DexSpace.xs),
                      Text(
                        stage.detail!,
                        style: DexTheme.data(colors, size: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single station. Complete is filled and calm, active is haloed and
/// breathing, pending is a hollow ring. The three must never look alike — the
/// rail's whole job is to show which one you are waiting on.
class _StationNode extends StatefulWidget {
  const _StationNode({
    required this.color,
    required this.status,
    required this.colors,
  });

  final Color color;
  final StageStatus status;
  final DexColors colors;

  @override
  State<_StationNode> createState() => _StationNodeState();
}

class _StationNodeState extends State<_StationNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _isActive => widget.status == StageStatus.active;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StationNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_isActive) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animate = _isActive && !MediaQuery.disableAnimationsOf(context);

    final DexColors c = widget.colors;
    // 28px discs, not 9px dots. The rail is the one place this design spends
    // boldness, and a station you cannot see from across the room is not
    // spending it. Complete is a filled disc with a check; active is a ring over
    // a tint with a breathing core; failed is a filled disc with a fault mark;
    // pending is a slate ring around a dot.
    final Widget core = switch (widget.status) {
      StageStatus.pending => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface.withValues(alpha: 0.5),
          border: Border.all(color: c.line, width: DexStroke.focusRing),
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.line),
        ),
      ),
      StageStatus.complete => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: widget.color.withValues(alpha: 0.40),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(DexIcons.check, size: DexIconSize.tray, color: c.bg),
      ),
      StageStatus.failed => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: widget.color.withValues(alpha: 0.40),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(
          DexIcons.fault,
          size: DexIconSize.tray,
          color: Colors.white,
        ),
      ),
      StageStatus.active => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.20),
          border: Border.all(color: widget.color, width: DexStroke.focusRing),
        ),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(alpha: 0.40),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ),
    };

    return SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: animate
            ? FadeTransition(
                opacity: Tween<double>(begin: 0.45, end: 1).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
                ),
                child: core,
              )
            : core,
      ),
    );
  }
}

/// One length of rail between two stations. Fills from the top as the stage
/// above it completes.
///
/// The fill is an animated gradient stop rather than a sized child: the rail
/// lives inside an [IntrinsicHeight], and fractional sizing cannot report an
/// intrinsic height.
class _RailSegment extends StatelessWidget {
  const _RailSegment({required this.filled, required this.colors});

  final bool filled;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final Duration duration = DexMotion.enabled(context)
        ? const Duration(milliseconds: 520)
        : Duration.zero;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: filled ? 1 : 0),
      duration: duration,
      curve: DexMotion.arrive,
      builder: (BuildContext context, double t, Widget? child) {
        return Container(
          width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.signal,
                colors.signal,
                colors.line,
                colors.line,
              ],
              stops: <double>[0, t, t, 1],
            ),
          ),
        );
      },
    );
  }
}

/// The Link Rail, collapsed.
///
/// Once the link is up the rail stops being a list of stations and becomes a
/// single live trace: a 4 px band carrying the measurements that say the link
/// is still there. Same instrument, third state — the one the user sees most,
/// so it stays quiet.
class LinkRailTrace extends StatelessWidget {
  const LinkRailTrace({required this.telemetry, this.live = true, super.key});

  final DeviceTelemetry telemetry;

  /// False while recovering: the trace stops travelling and goes to fault.
  final bool live;

  /// Units are formatted here, not in the backend — the contract carries the
  /// value and its unit separately so the UI can say it in the user's terms.
  static String format(TelemetryMeasurement m) {
    switch (m.unit) {
      case TelemetryUnit.milliseconds:
        // Non-breaking space glues the number to its unit.
        return '${m.value.round()} ms';
      case TelemetryUnit.framesPerSecond:
        // Not "fps": Android emits a frame when the screen changes, and
        // the decoder passes through exactly those. A still screen reads
        // single digits legitimately, and calling that "fps" made a
        // working stream look broken.
        return '${m.value.round()}/s';
      case TelemetryUnit.bytesPerSecond:
        final double mb = m.value / (1024 * 1024);
        if (mb >= 1) {
          return '${mb.toStringAsFixed(1)} MB/s';
        }
        return '${(m.value / 1024).round()} kB/s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final Color tint = live ? c.signal : c.fault;

    final List<(String, TelemetryMeasurement?)> readings =
        <(String, TelemetryMeasurement?)>[
          ('latency', telemetry.linkLatency),
          ('throughput', telemetry.throughput),
          ('frames', telemetry.framesPerSecond),
        ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TraceBand(tint: tint, live: live),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DexSpace.xxl,
            vertical: DexSpace.sm,
          ),
          // Readings are dropped as the window narrows rather than allowed to
          // overflow: latency is the one that says whether the link is healthy,
          // so it is the last to go.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int room = constraints.maxWidth >= 820
                  ? 3
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final List<(String, TelemetryMeasurement)> shown =
                  <(String, TelemetryMeasurement)>[
                    for (final (String label, TelemetryMeasurement? m)
                        in readings)
                      if (m != null) (label, m),
                  ].take(room).toList();

              return Row(
                children: <Widget>[
                  Text(
                    live ? 'linked' : 'link lost',
                    style: DexTheme.data(c, size: 11, color: tint),
                  ),
                  const Spacer(),
                  for (final (String label, TelemetryMeasurement m) in shown)
                    Padding(
                      padding: const EdgeInsets.only(left: DexSpace.xl),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(label, style: DexTheme.data(c, size: 11)),
                          const SizedBox(width: DexSpace.sm),
                          // Tabular figures: these change constantly and must
                          // not make the row jitter.
                          SwapText(
                            format(m),
                            style: DexTheme.data(c, size: 11, color: c.text),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The Link Rail, collapsed into a chip — the desk's form of the third state.
///
/// [LinkRailTrace] is the full-width bench strip the boot screen ends on. The
/// desk has no full width to give it: the top edge is where the search bar and
/// the clock live. So the same third state is drawn as a compact instrument
/// chip in the corner, carrying the same three machine values from the same
/// [LinkRailTrace.format].
///
/// It is the first thing on the desk, deliberately. The rail is the one object
/// this product asks a user to learn, and until now the state they see most —
/// a healthy link, quietly reporting — was the state the desk never showed.
///
/// Nothing here animates. [SwapText] cross-fades a value only when the value
/// itself changes, which is what `idle_cost_test` requires of anything living
/// permanently on a connected desk.
class LinkRailChip extends StatelessWidget {
  const LinkRailChip({
    required this.telemetry,
    this.live = true,
    this.readings = 3,
    super.key,
  });

  final DeviceTelemetry telemetry;

  /// False while recovering: the chip goes to fault and says so.
  final bool live;

  /// How many readouts there is room for. Latency is the one that says whether
  /// the link is healthy, so it is the last to be dropped.
  final int readings;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final Color tint = live ? c.signal : c.fault;

    // Labels are the reference's — short, uppercase, the same width class as
    // the numbers beside them, so the row reads as instrumentation rather than
    // as a sentence. The units come from LinkRailTrace.format, which renders
    // the frame rate as "/s" rather than "fps" on purpose: Android emits a
    // frame when the screen changes, so a still screen reports single digits
    // legitimately, and calling that "fps" made a working stream look broken.
    final List<(String, TelemetryMeasurement?, Color)> all =
        <(String, TelemetryMeasurement?, Color)>[
          ('RTT', telemetry.linkLatency, c.text),
          ('TX', telemetry.throughput, c.trace),
          ('RATE', telemetry.framesPerSecond, c.text),
        ];
    // Every readout is present, always, as the reference draws the chip. A
    // measurement the phone has not reported renders as an em dash: an idle
    // link is a state the chip must show, not a reason to lose its shape.
    final List<(String, TelemetryMeasurement?, Color)> shown = all
        .take(readings.clamp(1, all.length))
        .toList();

    return GlassPanel(
      radius: DexRadius.card,
      fill: glass.substrate,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.md,
        vertical: DexSpace.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A short run of the same trace the boot screen ends on, at the same
          // committed stroke, so the two readings of the rail are one object.
          Container(
            width: DexSpace.xxl,
            // Twice the rail stroke. The 4px token is the boot screen's
            // full-width trace; the chip's segment is a badge, and at 4px in a
            // 28px-tall pill it read as a hairline rather than as a signal.
            height: DexStroke.railTrace * 2,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(DexRadius.pill),
            ),
          ),
          const SizedBox(width: DexSpace.sm),
          Text(
            live ? 'LINK' : 'LINK LOST',
            style: DexTheme.data(c, size: 11, color: live ? c.text : c.fault),
          ),
          const SizedBox(width: DexSpace.md),
          Container(width: 1, height: 12, color: glass.stroke),
          for (final (String label, TelemetryMeasurement? m, Color colour)
              in shown)
            Padding(
              padding: const EdgeInsets.only(left: DexSpace.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: DexTheme.data(c, size: 11)),
                  const SizedBox(width: DexSpace.xs),
                  // Tabular figures: these change constantly and the row must
                  // not jitter as they do.
                  SwapText(
                    m == null ? '\u2014' : LinkRailTrace.format(m),
                    style: DexTheme.data(c, size: 11, color: colour),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The 4 px band. A signal travels it while the link is live; it goes flat and
/// red when the link is lost.
/// The link rail's signal band.
///
/// Static, deliberately. This used to run a 2.6 s gradient pulse on
/// `AnimationController.repeat()` for the **entire connected session**, which
/// rebuilt and repainted every frame forever. On its own that is a thin band;
/// stacked under a desk of `BackdropFilter` glass and a live video texture it
/// forced the whole tree to re-blur at 60 fps, and it was measured holding
/// roughly 72% host CPU with one embedded window.
///
/// Nothing is lost by stopping it. The band already distinguishes live from
/// down by colour, and the numbers beside it — latency, throughput, frames —
/// are real values that change on their own. A perpetual decorative animation
/// beside a video stream is not a trade worth making.
class _TraceBand extends StatelessWidget {
  const _TraceBand({required this.tint, required this.live});

  final Color tint;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DexStroke.railTrace,
      decoration: BoxDecoration(
        // A gradient still reads as a run of signal rather than a flat stripe;
        // it simply does not move.
        gradient: LinearGradient(
          colors: <Color>[
            tint.withValues(alpha: live ? 0.35 : 0.6),
            tint.withValues(alpha: live ? 0.95 : 0.9),
            tint.withValues(alpha: live ? 0.35 : 0.6),
          ],
        ),
      ),
    );
  }
}
