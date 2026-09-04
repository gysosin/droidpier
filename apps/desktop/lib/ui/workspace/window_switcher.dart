import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_glyph.dart';
import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../util/app_display_name.dart';
import 'window_model.dart';

/// Alt+Tab, made visible.
///
/// The shortcut already swapped focus to the window beneath; it just did so
/// silently, which makes it feel like a bug on the first press and useless with
/// more than two windows open. This shows what is about to receive focus while
/// Alt is held, and commits when it is released.
class WindowSwitcher extends StatelessWidget {
  const WindowSwitcher({
    required this.windows,
    required this.selected,
    required this.onPick,
    required this.onDismiss,
    super.key,
  });

  /// Most recently used first, which is the order Alt+Tab walks.
  final List<WorkspaceWindow> windows;

  /// Index into [windows] that will receive focus if Alt is released now.
  final int selected;

  final ValueChanged<String> onPick;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);

    return Semantics(
      container: true,
      label: 'Switch window. ${windows.length} open.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Entrance(
              rise: 8,
              child: GestureDetector(
                // Clicking a card must not fall through to the dismiss layer.
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: GlassPanel(
                    radius: 24,
                    fill: glass.substrate,
                    padding: const EdgeInsets.all(DexSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // The reference heads this with what it is and the
                        // key that summoned it, and counts the stack on the
                        // right — the number is the readout, not the title.
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'WINDOW SWITCHER (ALT + TAB)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DexTheme.data(
                                  c,
                                  size: 10,
                                  color: c.text,
                                ).copyWith(letterSpacing: 1.4),
                              ),
                            ),
                            const SizedBox(width: DexSpace.md),
                            Text(
                              'Z-Order Stack (${windows.length} active)',
                              style: DexTheme.data(c, size: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: DexSpace.sm),
                        Divider(
                          color: glass.stroke,
                          height: DexStroke.hairline,
                        ),
                        const SizedBox(height: DexSpace.md),
                        Wrap(
                          spacing: DexSpace.md,
                          runSpacing: DexSpace.md,
                          children: <Widget>[
                            for (int i = 0; i < windows.length; i++)
                              _Card(
                                window: windows[i],
                                current: i == selected,
                                onPick: () => onPick(windows[i].id),
                              ),
                          ],
                        ),
                        if (windows.isNotEmpty) ...<Widget>[
                          const SizedBox(height: DexSpace.md),
                          Center(
                            child: Text.rich(
                              TextSpan(
                                text: 'Release Alt to focus ',
                                style: DexTheme.data(c, size: 10),
                                children: <InlineSpan>[
                                  TextSpan(
                                    text:
                                        windows[selected.clamp(
                                              0,
                                              windows.length - 1,
                                            )]
                                            .session
                                            .application
                                            .label,
                                    style: DexTheme.data(
                                      c,
                                      size: 10,
                                      color: c.text,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
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

class _Card extends StatelessWidget {
  const _Card({
    required this.window,
    required this.current,
    required this.onPick,
  });

  final WorkspaceWindow window;
  final bool current;
  final VoidCallback onPick;

  /// Streaming is emerald, a fault is rose, anything paused or minimised is
  /// muted. The taskbar reads the same way.
  Color _dotColour(DexColors c) => switch (window.session.status) {
    WindowSessionStatus.failed => c.fault,
    WindowSessionStatus.reconnecting => c.signal,
    _ when window.isMinimised => c.muted.withValues(alpha: 0.5),
    WindowSessionStatus.streaming => c.trace,
    _ => c.muted,
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final AndroidApplication app = window.session.application;
    final String shown = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;

    final String state = switch (window.session.status) {
      WindowSessionStatus.failed => 'Stopped',
      WindowSessionStatus.starting => 'Opening',
      WindowSessionStatus.reconnecting => 'Reconnecting',
      WindowSessionStatus.suspended => 'Paused',
      _ => window.isMinimised ? 'Minimised' : 'Running',
    };

    return Semantics(
      button: true,
      selected: current,
      label: 'Switch to $shown, $state',
      child: HoverLift(
        builder: (BuildContext context, bool hovered) => InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            width: 176,
            padding: const EdgeInsets.all(DexSpace.md),
            decoration: BoxDecoration(
              color: current
                  ? c.signal.withValues(alpha: 0.24)
                  : hovered
                  ? glass.fillStrong
                  : glass.fill,
              borderRadius: BorderRadius.circular(DexRadius.card),
              border: Border.all(
                color: current
                    ? c.signal
                    : hovered
                    ? glass.strokeStrong
                    : glass.stroke,
                width: current ? DexStroke.focusRing : DexStroke.hairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Glyph and name top-left, the state dot top-right, a preview
                // slot between, the package under it — the reference's card,
                // which reads as a window and not as a launcher tile.
                Row(
                  children: <Widget>[
                    AppGlyph(app: app, size: 20),
                    const SizedBox(width: DexSpace.sm),
                    Expanded(
                      child: Text(
                        shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: c.text),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColour(c),
                        boxShadow:
                            window.session.status ==
                                    WindowSessionStatus.streaming &&
                                !window.isMinimised
                            ? <BoxShadow>[
                                BoxShadow(color: c.trace, blurRadius: 6),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DexSpace.sm),
                Container(
                  height: 72,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: glass.readout,
                    borderRadius: BorderRadius.circular(DexRadius.control),
                  ),
                  child: Text(
                    state,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: window.session.status == WindowSessionStatus.failed
                          ? c.fault
                          : c.muted,
                    ),
                  ),
                ),
                const SizedBox(height: DexSpace.sm),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DexTheme.data(c, size: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
