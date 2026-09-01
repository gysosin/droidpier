import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
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
    final TextTheme t = Theme.of(context).textTheme;

    // Grouped, in the order the groups first appear in the registry rather
    // than enum order — so the sheet reads in the same sequence the dispatcher
    // does, and a reader can map one to the other.
    final Map<DexShortcutGroup, List<DexShortcut>> grouped =
        <DexShortcutGroup, List<DexShortcut>>{};
    for (final DexShortcut s in shortcuts) {
      grouped.putIfAbsent(s.group, () => <DexShortcut>[]).add(s);
    }

    // Two columns. A single column overflowed the panel and quietly hid the
    // last three rows below a scroll nobody could see — on a cheat sheet, a
    // shortcut you cannot see is the only kind that matters.
    final List<Widget> left = <Widget>[];
    final List<Widget> right = <Widget>[];
    int i = 0;
    for (final MapEntry<DexShortcutGroup, List<DexShortcut>> e
        in grouped.entries) {
      final Widget section = Entrance(
        order: i,
        child: _Section(
          label: _groupLabel(e.key),
          entries: e.value,
          colors: c,
        ),
      );
      (i.isEven ? left : right).add(section);
      i++;
    }

    return Padding(
      padding: const EdgeInsets.all(DexSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Keyboard shortcuts', style: t.titleMedium),
              ),
              // A panel with no visible way out is a dead end for anyone who
              // did not arrive by keyboard.
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
                color: c.muted,
                tooltip: 'Close',
                constraints: const BoxConstraints(
                  minWidth: DexHit.comfortable,
                  minHeight: DexHit.comfortable,
                ),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.xs),
          Text(
            'Esc closes whatever is open, one layer at a time.',
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
          const SizedBox(height: DexSpace.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: left,
                    ),
                  ),
                  const SizedBox(width: DexSpace.xxl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: right,
                    ),
                  ),
                ],
              ),
            ),
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
  });

  final String label;
  final List<DexShortcut> entries;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: DexSpace.sm),
            child: Text(
              label.toUpperCase(),
              style: DexTheme.data(
                colors,
                size: 11,
                color: colors.muted,
              ).copyWith(letterSpacing: 1.6),
            ),
          ),
          for (final MapEntry<String, List<DexShortcut>> row
              in _byLabel(entries).entries)
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DexSpace.xs),
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
