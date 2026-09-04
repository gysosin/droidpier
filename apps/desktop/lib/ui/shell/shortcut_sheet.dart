import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../util/app_version.dart';
import 'shortcuts.dart';

/// The keyboard cheat sheet.
///
/// A view over the registry and nothing else. Every row here is one
/// [DexShortcut]: the label is the entry's own `label`, and the keys are
/// rendered from its `stroke`. Nothing in this file types a shortcut name or a
/// key combination by hand, which is the whole reason the registry and this
/// sheet were built as one piece of work — two lists would disagree within a
/// release.
///
/// Adding a shortcut to `buildShortcuts` makes it appear here with no edit.
class ShortcutSheet extends StatelessWidget {
  const ShortcutSheet({required this.shortcuts, required this.onClose, super.key});

  final List<DexShortcut> shortcuts;
  final VoidCallback onClose;

  /// What each group is called on screen.
  static String _groupLabel(DexShortcutGroup g) => switch (g) {
    DexShortcutGroup.launcher => 'Launcher',
    DexShortcutGroup.windows => 'Windows',
    DexShortcutGroup.session => 'Session',
    DexShortcutGroup.diagnostics => 'Diagnostics',
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    // Grouped, in the order the groups first appear in the registry rather
    // than enum order — so the sheet reads in the same sequence the dispatcher
    // does, and a reader can map one to the other.
    final Map<DexShortcutGroup, List<DexShortcut>> grouped =
        <DexShortcutGroup, List<DexShortcut>>{};
    for (final DexShortcut s in shortcuts) {
      grouped.putIfAbsent(s.group, () => <DexShortcut>[]).add(s);
    }

    // One column of cards, as the reference lays it out, scrolling when the
    // window is short. An earlier two-column layout existed to dodge a scroll
    // nobody could see; the scroll is visible now because the cards give it
    // an edge to clip against.
    int i = 0;
    final List<Widget> cards = <Widget>[
      for (final MapEntry<DexShortcutGroup, List<DexShortcut>> e
          in grouped.entries)
        Entrance(
          order: i++,
          child: _Section(
            label: _groupLabel(e.key),
            entries: e.value,
            colors: c,
            glass: glass,
          ),
        ),
      Entrance(order: i, child: _EscapeLadder(colors: c, glass: glass)),
    ];

    return Padding(
      padding: const EdgeInsets.all(DexSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: DexHit.comfortable,
                height: DexHit.comfortable,
                decoration: BoxDecoration(
                  color: glass.fill,
                  borderRadius: BorderRadius.circular(DexRadius.control),
                ),
                child: Icon(DexIcons.keyboard, size: 18, color: c.signal),
              ),
              const SizedBox(width: DexSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Keyboard Shortcuts', style: t.titleLarge),
                    // Which build this is, one key press away. Settings is the
                    // conventional home for it, but "am I running what I just
                    // installed?" is a question you ask in a hurry.
                    Text(
                      'Desktop Accelerator Map · ${versionLabel()}',
                      style: t.bodySmall?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              // A panel with no visible way out is a dead end for anyone who
              // did not arrive by keyboard.
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
          const SizedBox(height: DexSpace.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cards,
              ),
            ),
          ),
          const SizedBox(height: DexSpace.sm),
          Divider(color: c.line, height: DexStroke.hairline),
          const SizedBox(height: DexSpace.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Anything not claimed here goes straight to the focused '
                  'Android window.',
                  style: DexTheme.data(c, size: 10),
                ),
              ),
              Text('Press Esc to close', style: DexTheme.data(c, size: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.entries,
    required this.colors,
    required this.glass,
  });

  final String label;
  final List<DexShortcut> entries;
  final DexColors colors;
  final DexGlass glass;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<DexShortcut>> rows = _byLabel(entries);

    return Container(
      margin: const EdgeInsets.only(bottom: DexSpace.md),
      padding: const EdgeInsets.fromLTRB(
        DexSpace.lg,
        DexSpace.md,
        DexSpace.lg,
        DexSpace.xs,
      ),
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
                  label.toUpperCase(),
                  style: DexTheme.data(
                    colors,
                    size: 10,
                    color: colors.muted,
                  ).copyWith(letterSpacing: 1.4),
                ),
              ),
              Text(
                '${rows.length}',
                style: DexTheme.data(colors, size: 10, color: colors.muted),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.xs),
          for (final MapEntry<String, List<DexShortcut>> row in rows.entries)
            _Row(
              label: row.key,
              strokes: row.value
                  .map((DexShortcut s) => s.stroke.label)
                  .toList(),
              colors: colors,
            ),
        ],
      ),
    );
  }
}

/// How Esc behaves, set apart because it is the one key that does something
/// different depending on what is open.
class _EscapeLadder extends StatelessWidget {
  const _EscapeLadder({required this.colors, required this.glass});

  final DexColors colors;
  final DexGlass glass;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: colors.signal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(
          color: colors.signal.withValues(alpha: 0.25),
          width: DexStroke.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Keycap(text: 'Esc', colors: colors),
          const SizedBox(width: DexSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'ESCAPE LADDER',
                  style: DexTheme.data(
                    colors,
                    size: 10,
                    color: colors.signal,
                  ).copyWith(letterSpacing: 1.4),
                ),
                const SizedBox(height: DexSpace.xs),
                Text(
                  'Esc closes whatever is open, one layer at a time: the '
                  'topmost panel first, then the one beneath it, and only '
                  'then does it reach the window.',
                  style: t.bodySmall?.copyWith(color: colors.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per distinct action, however many keys reach it.
///
/// Ctrl+/, F1 and ? all open this sheet. Listed one per entry they filled a
/// third of the panel with the same sentence three times, which reads as a bug.
Map<String, List<DexShortcut>> _byLabel(List<DexShortcut> entries) {
  final Map<String, List<DexShortcut>> out = <String, List<DexShortcut>>{};
  for (final DexShortcut s in entries) {
    out.putIfAbsent(s.label, () => <DexShortcut>[]).add(s);
  }
  return out;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.strokes,
    required this.colors,
  });

  final String label;
  final List<String> strokes;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DexSpace.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.line.withValues(alpha: 0.6),
            width: DexStroke.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: t.bodyMedium?.copyWith(color: colors.text),
            ),
          ),
          const SizedBox(width: DexSpace.md),
          for (final String k in strokes) ...<Widget>[
            const SizedBox(width: DexSpace.xs),
            _Keycap(text: k, colors: colors),
          ],
        ],
      ),
    );
  }
}

/// The stroke, set as a key rather than as prose.
///
/// Monospace on purpose: a key combination is a machine value, and the token
/// rules put serials, ports and telemetry in [DexType.data] for the same
/// reason.
class _Keycap extends StatelessWidget {
  const _Keycap({required this.text, required this.colors});

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
