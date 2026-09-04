import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// One step of the first-run tour.
@immutable
class TourStep {
  const TourStep({required this.title, required this.body, this.keys});

  final String title;
  final String body;

  /// The keys a person would press, shown as caps beside the text. Null where
  /// the step is about something pointed at rather than typed.
  final List<String>? keys;
}

/// What a new person is shown, once.
///
/// Four sentences, not a manual. The tour exists because the desk looks emptier
/// than it is: nothing on screen says that Ctrl+Space, edge snapping or the
/// control centre exist, so a beta user concludes the product does less than it
/// does.
///
/// The plan for this called for a spotlight cut out over each real widget. Two
/// of the four targets are not guaranteed to be on screen — step two spotlights
/// a window title bar, and there may be no window open — so a step that could
/// point at nothing describes the gesture instead. A spotlight over an empty
/// desk teaches less than a sentence does.
const List<TourStep> kTourSteps = <TourStep>[
  TourStep(
    title: 'Find an app by typing',
    body:
        'Open the launcher and start typing. Results are ranked by how well '
        'they match and by what you actually open, so a letter or two is '
        'usually enough.',
    keys: <String>['Ctrl', 'Space'],
  ),
  TourStep(
    title: 'Arrange windows by dragging',
    body:
        'Drag a window by its title bar to a screen edge to fill half, or a '
        'corner for a quarter. Right-click the title bar for the same choices, '
        'and to turn a window portrait or landscape.',
  ),
  TourStep(
    title: 'Switch between what is open',
    body:
        'Every running app has a place on the taskbar along the bottom. Hold '
        'Alt and press Tab to move between them.',
    keys: <String>['Alt', 'Tab'],
  ),
  TourStep(
    title: 'Your phone, from the desk',
    body:
        'The tray on the right carries clipboard sharing, volume, '
        'notifications and the battery. Settings holds the theme, the accent '
        'and the wallpaper.',
  ),
];

/// Shows [kTourSteps] once, over the desk.
class FirstRunTour extends StatefulWidget {
  const FirstRunTour({required this.onFinished, super.key});

  /// Called when the tour ends, however it ends — finished or skipped. The
  /// caller records that it has run; from its side the two are the same.
  final VoidCallback onFinished;

  @override
  State<FirstRunTour> createState() => _FirstRunTourState();
}

class _FirstRunTourState extends State<FirstRunTour> {
  int _step = 0;

  bool get _isLast => _step == kTourSteps.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final TourStep step = kTourSteps[_step];

    return Stack(
      children: <Widget>[
        // Dims the desk without hiding it: the point is that the person sees
        // where these things live, not that they read a modal.
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: DexSpace.xxxl,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Entrance(
                // Re-keyed per step so each one arrives rather than the text
                // swapping in place, which reads as a glitch.
                key: ValueKey<int>(_step),
                child: GlassPanel(
                  radius: DexRadius.panel,
                  padding: const EdgeInsets.all(DexSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // A rail of segments, one per step, filled up to this
                      // one — progress you can see without reading.
                      Row(
                        children: <Widget>[
                          for (int i = 0; i < kTourSteps.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: DexSpace.xs),
                            Expanded(
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i <= _step ? c.signal : c.line,
                                  borderRadius: BorderRadius.circular(
                                    DexRadius.pill,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: DexSpace.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: DexHit.comfortable,
                            height: DexHit.comfortable,
                            decoration: BoxDecoration(
                              color: c.signal.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                DexRadius.control,
                              ),
                            ),
                            child: Icon(
                              DexIcons.sparkles,
                              size: 18,
                              color: c.signal,
                            ),
                          ),
                          const SizedBox(width: DexSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'QUICK TOUR',
                                  style: DexTheme.data(
                                    c,
                                    size: 9,
                                    color: c.signal,
                                  ).copyWith(letterSpacing: 1.6),
                                ),
                                const SizedBox(height: 2),
                                Text(step.title, style: t.titleLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DexSpace.sm),
                      Text(
                        step.body,
                        style: t.bodyMedium?.copyWith(color: c.muted),
                      ),
                      if (step.keys case final List<String> keys) ...<Widget>[
                        const SizedBox(height: DexSpace.md),
                        Row(
                          children: <Widget>[
                            for (final String k in keys) ...<Widget>[
                              _Key(text: k, colors: c),
                              const SizedBox(width: DexSpace.xs),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: DexSpace.lg),
                      // Above the buttons, not beside them. Squeezed into the
                      // same row it overflowed by 20px at this width, and it
                      // would have overflowed at some width regardless.
                      if (_isLast) ...<Widget>[
                        Text(
                          'Press ? any time for every shortcut',
                          style: DexTheme.data(c, size: 11),
                        ),
                        const SizedBox(height: DexSpace.md),
                      ],
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              '${_step + 1} of ${kTourSteps.length}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DexTheme.data(c, size: 10),
                            ),
                          ),
                          const Spacer(),
                          // Always available. Someone who already knows the
                          // product must be able to leave from anywhere.
                          TextButton(
                            onPressed: widget.onFinished,
                            child: const Text('Skip'),
                          ),
                          const SizedBox(width: DexSpace.xs),
                          FilledButton(
                            onPressed: _next,
                            child: Text(_isLast ? 'Done' : 'Next'),
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
      ],
    );
  }
}

/// A key cap, matching the shortcut sheet's.
class _Key extends StatelessWidget {
  const _Key({required this.text, required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.sm,
        vertical: DexSpace.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(DexRadius.control),
        border: Border.all(color: colors.line, width: DexStroke.hairline),
      ),
      child: Text(
        text,
        style: DexTheme.data(colors, size: 12, color: colors.text),
      ),
    );
  }
}
