import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../util/app_display_name.dart';
import '../widgets/link_rail.dart';
import 'health_hud.dart';

/// What each streaming window is actually doing, on demand.
///
/// Two reported faults here turned out to be the product working — a still
/// screen reading as low fps, and a frame counter labelled as though it were a
/// speed. The fix for the labels was to say less in the
/// chrome. This is where the numbers went instead: out of the way, but reachable
/// without asking anyone, so "is it actually streaming?" is a keypress rather
/// than a support conversation.
///
/// Deliberately not a debug dump. Every row is something a person could act on:
/// what the phone is sending, at what size, and what went wrong last.
class StreamDiagnostics extends StatelessWidget {
  const StreamDiagnostics({
    required this.snapshot,
    required this.recentExits,
    required this.onClose,
    this.onCopyDiagnostics,
    super.key,
  });

  final OpenDexSnapshot snapshot;

  /// Most recent first. Kept by the shell because a closed window is gone from
  /// the snapshot, and "what happened to the one that vanished" is exactly the
  /// question this is for.
  final List<String> recentExits;

  final VoidCallback onClose;

  /// Puts a paste-ready report on the desktop clipboard.
  ///
  /// Null where the host has not supplied a clipboard, in which case the button
  /// is absent rather than inert — `lib/ui` never touches the system clipboard
  /// itself, that belongs to the bootstrap lane.
  final VoidCallback? onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final List<WindowSessionState> windows = snapshot.windows
        .where((WindowSessionState w) => w.status != WindowSessionStatus.closed)
        .toList();

    return Semantics(
      container: true,
      label: 'Stream diagnostics',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.35),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: DexSpace.xxl),
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: GlassPanel(
                    radius: DexRadius.dialog,
                    fill: glass.substrate,
                    // Opened while apps stream, so it must not blur video.
                    blurred: false,
                    padding: const EdgeInsets.all(DexSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(DexIcons.activity, size: 22, color: c.trace),
                            const SizedBox(width: DexSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'Stream Diagnostics',
                                    style: t.titleLarge,
                                  ),
                                  Text(
                                    'Deliberately not a debug dump. Every row '
                                    'is something you can act on.',
                                    style: t.bodySmall?.copyWith(
                                      color: c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: onClose,
                              icon: const Icon(DexIcons.close, size: 18),
                              color: c.muted,
                              tooltip: 'Close',
                              constraints: const BoxConstraints(
                                minWidth: DexHit.comfortable,
                                minHeight: DexHit.comfortable,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DexSpace.md),
                        // The link, before the streams that ride it. Reading
                        // per-window frame rates without knowing the latency
                        // and throughput under them is how a healthy link gets
                        // blamed for a slow app, and the reverse.
                        Container(
                          padding: const EdgeInsets.all(DexSpace.xs),
                          decoration: BoxDecoration(
                            color: glass.fillSubtle,
                            borderRadius: BorderRadius.circular(DexRadius.card),
                            border: Border.all(
                              color: glass.stroke,
                              width: DexStroke.hairline,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              _LinkSummary(
                                label: 'LINK LATENCY',
                                measurement: snapshot.telemetry.linkLatency,
                                grade: _latencyGrade(
                                  snapshot.telemetry.linkLatency,
                                  c,
                                ),
                                colors: c,
                                glass: glass,
                              ),
                              const SizedBox(width: DexSpace.sm),
                              _LinkSummary(
                                label: 'THROUGHPUT',
                                measurement: snapshot.telemetry.throughput,
                                grade: null,
                                colors: c,
                                glass: glass,
                                value: c.trace,
                              ),
                              const SizedBox(width: DexSpace.sm),
                              _LinkSummary(
                                label: 'COMPOSITOR RATE',
                                measurement: snapshot.telemetry.framesPerSecond,
                                grade: null,
                                colors: c,
                                glass: glass,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: DexSpace.lg),
                        Text(
                          'ACTIVE VIDEO SURFACES (${windows.length})',
                          style: DexTheme.data(
                            c,
                            size: 10,
                          ).copyWith(letterSpacing: 1.4),
                        ),
                        const SizedBox(height: DexSpace.sm),
                        if (windows.isEmpty)
                          Text(
                            'No app windows are open.',
                            style: t.bodyMedium?.copyWith(color: c.muted),
                          )
                        else
                          for (final WindowSessionState w in windows)
                            _Row(window: w, colors: c, glass: glass),
                        if (recentExits.isNotEmpty) ...<Widget>[
                          const SizedBox(height: DexSpace.lg),
                          Row(
                            children: <Widget>[
                              Icon(DexIcons.clock, size: 12, color: c.muted),
                              const SizedBox(width: 6),
                              Text(
                                'RECENTLY CLOSED SESSIONS (LAST 8)',
                                style: DexTheme.data(
                                  c,
                                  size: 10,
                                ).copyWith(letterSpacing: 1.4),
                              ),
                            ],
                          ),
                          const SizedBox(height: DexSpace.sm),
                          for (final String line in recentExits.take(5))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                line,
                                style: DexTheme.data(c, size: 11),
                              ),
                            ),
                        ],
                        const SizedBox(height: DexSpace.lg),
                        Divider(
                          color: glass.stroke,
                          height: DexStroke.hairline,
                        ),
                        const SizedBox(height: DexSpace.md),
                        // The footer the reference closes with: the report on
                        // the left, the way out on the right.
                        Row(
                          children: <Widget>[
                            if (onCopyDiagnostics case final VoidCallback copy)
                              Flexible(
                                child: OutlinedButton.icon(
                                  onPressed: copy,
                                  icon: const Icon(DexIcons.copy, size: 14),
                                  label: const Text(
                                    'Copy diagnostics report',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            const SizedBox(width: DexSpace.md),
                            Expanded(
                              child: Text(
                                'Press Ctrl+Shift+D to close',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: DexTheme.data(c, size: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
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

/// Grades the link's round trip against the thresholds the health readout
/// already uses, so the two surfaces cannot disagree about what "good" is.
({String text, Color colour})? _latencyGrade(
  TelemetryMeasurement? m,
  DexColors c,
) {
  if (m == null) return null;
  return switch (gradeLatency(m.value)) {
    HealthGrade.good => (text: 'optimal', colour: c.trace),
    HealthGrade.fair => (text: 'usable', colour: c.warn),
    HealthGrade.poor => (text: 'degraded', colour: c.fault),
    // Ungraded is a state, not a fault: painting it red teaches people to
    // ignore red.
    HealthGrade.unknown => null,
  };
}

/// One of the three link readouts across the top of the panel.
///
/// A measurement the phone has not reported renders as an em dash. Never a
/// zero: a meter with an invented number in it is worse than an empty one.
class _LinkSummary extends StatelessWidget {
  const _LinkSummary({
    required this.label,
    required this.measurement,
    required this.grade,
    required this.colors,
    required this.glass,
    this.value,
  });

  final String label;
  final TelemetryMeasurement? measurement;
  final ({String text, Color colour})? grade;
  final DexColors colors;
  final DexGlass glass;
  final Color? value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: DexTheme.data(
                colors,
                size: 9,
              ).copyWith(letterSpacing: 1.4),
            ),
            const SizedBox(height: DexSpace.xs),
            Text(
              measurement == null ? '—' : LinkRailTrace.format(measurement!),
              style: DexTheme.data(
                colors,
                size: 15,
                color: value ?? colors.text,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
            if (grade case final ({String text, Color colour}) g) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                g.text,
                style: DexTheme.data(colors, size: 10, color: g.colour),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.window, required this.colors, required this.glass});

  final WindowSessionState window;
  final DexColors colors;
  final DexGlass glass;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String name =
        isPlaceholderLabel(
          window.application.label,
          window.application.packageName,
        )
        ? displayNameFor(window.application.packageName)
        : window.application.label;
    final WindowPixelSize? size = window.surfaceSize;
    final double? presented = window.presentedFramesPerSecond;
    final double? produced = window.producedFramesPerSecond;
    final double? dropped = window.droppedFramesPerSecond;

    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DexSpace.md),
        decoration: BoxDecoration(
          color: glass.fillSubtle,
          borderRadius: BorderRadius.circular(DexRadius.card),
          border: Border.all(color: glass.stroke, width: DexStroke.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelLarge?.copyWith(color: colors.text),
                  ),
                ),
                Text(
                  _statusWord(window.status),
                  style: DexTheme.data(
                    colors,
                    size: 11,
                    color: window.status == WindowSessionStatus.failed
                        ? colors.fault
                        : colors.trace,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                if (size != null) '${size.width}x${size.height}',
                if (window.displayId != null) 'display ${window.displayId}',
              ].join('  ·  '),
              style: DexTheme.data(colors, size: 11),
            ),
            if (presented != null || produced != null) ...<Widget>[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(DexSpace.sm),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(DexRadius.control),
                ),
                child: _Rates(
                  presented: presented,
                  produced: produced,
                  dropped: dropped,
                  colors: colors,
                ),
              ),
            ],
            if (window.error != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                window.error!.message,
                style: t.bodySmall?.copyWith(color: colors.fault),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusWord(WindowSessionStatus status) => switch (status) {
    WindowSessionStatus.streaming => 'live',
    WindowSessionStatus.starting => 'opening',
    WindowSessionStatus.reconnecting => 'reconnecting',
    WindowSessionStatus.suspended => 'paused',
    WindowSessionStatus.failed => 'stopped',
    WindowSessionStatus.closed => 'closed',
  };
}

/// The three frame rates, shown together so the gap between them is the thing
/// you read first.
///
/// Produced and presented were conflated into a single `framesPerSecond` for
/// most of this project's life, and the two gateways disagreed about which one
/// it held. On 25 Aug the pipeline produced 72 frames a second and put 15 of
/// them on screen; every number anyone quoted was the 72. Showing one rate
/// invites that mistake again, so this widget will not render a lone figure —
/// if only one rate is known it still says which one it is.
class _Rates extends StatelessWidget {
  const _Rates({
    required this.presented,
    required this.produced,
    required this.dropped,
    required this.colors,
  });

  final double? presented;
  final double? produced;
  final double? dropped;
  final DexColors colors;

  /// Whether enough frames are being lost that the gap is the story.
  ///
  /// A few dropped frames a second is ordinary — the reader coalesces whatever
  /// arrives between two rasters. A fifth of everything decoded is a pipeline
  /// that cannot keep up with itself, and it should not read as calmly as the
  /// rest of the line.
  bool get _bleeding {
    final double? made = produced;
    final double? lost = dropped;
    if (made == null || lost == null || made < 1) return false;
    return lost / made > 0.2;
  }

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];

    void add(String text, {Color? color}) {
      if (spans.isNotEmpty) {
        spans.add(
          TextSpan(
            text: '  ·  ',
            style: DexTheme.data(colors, size: 11, color: colors.trace),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text,
          style: DexTheme.data(colors, size: 11, color: color),
        ),
      );
    }

    final double? onScreen = presented;
    if (onScreen != null) {
      add(
        '${onScreen.round()}/s on screen',
        color: _bleeding ? colors.fault : colors.text,
      );
    }
    final double? made = produced;
    if (made != null) add('${made.round()}/s produced');
    final double? lost = dropped;
    if (lost != null && lost >= 0.5) {
      add('${lost.round()}/s dropped', color: _bleeding ? colors.fault : null);
    }

    return Text.rich(TextSpan(children: spans));
  }
}
