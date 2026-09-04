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
                    radius: DexRadius.dialog,
                    fill: glass.substrate,
                    padding: const EdgeInsets.all(DexSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          windows.length == 1
                              ? '1 app open'
                              : '${windows.length} apps open',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: c.muted),
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
                          Text(
                            'Release Alt to focus '
                            '${windows[selected.clamp(0, windows.length - 1)]
                                .session.application.label}',
                            style: DexTheme.data(c, size: 10),
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
            width: 148,
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
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // The same dot the dock draws, so one glance reads the
                    // same in both places.
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
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: DexSpace.xs),
                AppGlyph(app: app, size: 44),
                const SizedBox(height: DexSpace.sm),
                Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: c.text),
                ),
                Text(
                  state,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: window.session.status == WindowSessionStatus.failed
                        ? c.fault
                        : c.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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
