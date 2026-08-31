import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../util/app_display_name.dart';

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
    super.key,
  });

  final OpenDexSnapshot snapshot;

  /// Most recent first. Kept by the shell because a closed window is gone from
  /// the snapshot, and "what happened to the one that vanished" is exactly the
  /// question this is for.
  final List<String> recentExits;

  final VoidCallback onClose;

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
                          children: <Widget>[
                            Expanded(
                              child: Text('Streams', style: t.titleLarge),
                            ),
                            Text(
                              'Ctrl+Shift+D to close',
                              style: DexTheme.data(c, size: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: DexSpace.md),
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
                          Text(
                            'Recently closed',
                            style: t.labelLarge?.copyWith(color: c.muted),
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
              _Rates(
                presented: presented,
                produced: produced,
                dropped: dropped,
                colors: colors,
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
