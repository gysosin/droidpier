import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';
import 'package:flutter/services.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'commands.dart';

/// One searchable list of everything the shell can do.
///
/// The cheapest home for every feature that has no natural surface of its own:
/// actions were previously reachable only from the surface that owned them, so
/// nothing was reachable *by name*.
///
/// Shares its matcher with the app drawer — see `scoreMatch` — so typing
/// behaves the same in both places rather than being subtly different in the
/// one you happen to be in.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    required this.commands,
    required this.onDismiss,
    super.key,
  });

  final List<DexCommand> commands;
  final VoidCallback onDismiss;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // Opens ready to type. Anything else costs a keystroke.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<DexCommand> get _results => searchCommands(widget.commands, _query.text);

  void _runSelected() {
    final List<DexCommand> results = _results;
    if (results.isEmpty) return;
    final DexCommand chosen = results[_selected.clamp(0, results.length - 1)];
    // Dismiss first: a command that opens another surface would otherwise be
    // covered by the palette it was launched from.
    widget.onDismiss();
    chosen.run();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final int count = _results.length;
    if (count == 0) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1 + count) % count);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String _groupLabel(DexCommandGroup g) => switch (g) {
    DexCommandGroup.app => 'APPS',
    DexCommandGroup.window => 'WINDOWS',
    DexCommandGroup.device => 'DEVICE',
    DexCommandGroup.shell => 'SHELL',
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final List<DexCommand> results = _results;
    final int selected = results.isEmpty
        ? 0
        : _selected.clamp(0, results.length - 1);

    return Padding(
      padding: const EdgeInsets.all(DexSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _query,
            focusNode: _focus,
            onChanged: (_) => setState(() => _selected = 0),
            onSubmitted: (_) => _runSelected(),
            style: t.bodyLarge,
            cursorColor: c.signal,
            decoration: InputDecoration(
              hintText: 'Type a command…',
              hintStyle: t.bodyLarge?.copyWith(color: c.muted),
              prefixIcon: Icon(DexIcons.forward, size: 18, color: c.muted),
              filled: true,
              fillColor: c.surface.withValues(alpha: 0.72),
              contentPadding: const EdgeInsets.symmetric(
                vertical: DexSpace.md,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DexRadius.control),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DexRadius.control),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DexRadius.control),
                borderSide: BorderSide(
                  color: c.signal,
                  width: DexStroke.focusRing,
                ),
              ),
            ),
          ),
          const SizedBox(height: DexSpace.md),
          if (results.isEmpty)
            // Never a blank panel: an empty result is a state, and it says
            // what happened and how to get out of it.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DexSpace.xl),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Text(
                      'Nothing matches “${_query.text.trim()}”',
                      style: t.bodyLarge,
                    ),
                    const SizedBox(height: DexSpace.xs),
                    Text(
                      'Try a shorter search.',
                      style: t.bodySmall?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(child: _Results(results: results, selected: selected, colors: c, groupLabel: _groupLabel, onRun: (int i) {
              setState(() => _selected = i);
              _runSelected();
            }, onHover: (int i) => setState(() => _selected = i))),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.selected,
    required this.colors,
    required this.groupLabel,
    required this.onRun,
    required this.onHover,
  });

  final List<DexCommand> results;
  final int selected;
  final DexColors colors;
  final String Function(DexCommandGroup) groupLabel;
  final ValueChanged<int> onRun;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    // Group headers appear where the group changes, so the list reads as
    // sections without needing a second pass to build them.
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (BuildContext context, int i) {
        final DexCommand command = results[i];
        final bool startsGroup = i == 0 || results[i - 1].group != command.group;
        final bool isSelected = i == selected;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (startsGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DexSpace.xs,
                  DexSpace.md,
                  0,
                  DexSpace.sm,
                ),
                child: Text(
                  groupLabel(command.group),
                  style: DexTheme.data(
                    colors,
                    size: 10,
                    color: colors.muted,
                  ).copyWith(letterSpacing: 1.6),
                ),
              ),
            Semantics(
              button: true,
              selected: isSelected,
              label: command.title,
              child: MouseRegion(
                onEnter: (_) => onHover(i),
                child: GestureDetector(
                  onTap: () => onRun(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: DexMotion.enabled(context)
                        ? DexDuration.micro
                        : Duration.zero,
                    curve: DexMotion.arrive,
                    margin: const EdgeInsets.only(bottom: DexSpace.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DexSpace.md,
                      vertical: DexSpace.sm,
                    ),
                    constraints: const BoxConstraints(
                      minHeight: DexHit.primary,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.signal.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(DexRadius.card),
                      border: Border.all(
                        color: isSelected ? colors.signal : Colors.transparent,
                        width: DexStroke.hairline,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                command.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(
                                  color: colors.text,
                                ),
                              ),
                              if (command.subtitle case final String s)
                                Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DexTheme.data(colors, size: 10),
                                ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Text(
                            'Enter',
                            style: DexTheme.data(
                              colors,
                              size: 10,
                              color: colors.signal,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
