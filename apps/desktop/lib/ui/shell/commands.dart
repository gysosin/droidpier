import 'package:flutter/foundation.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_ranking.dart';

/// Where a command comes from, for the group headers in the palette.
enum DexCommandGroup { app, window, device, shell }

/// One thing the shell can do, named so a person can find it by typing.
@immutable
class DexCommand {
  const DexCommand({
    required this.id,
    required this.title,
    required this.group,
    required this.run,
    this.subtitle,
    this.keywords = const <String>[],
  });

  /// Stable across rebuilds, so recency can be recorded against it.
  final String id;

  final String title;
  final String? subtitle;
  final DexCommandGroup group;
  final VoidCallback run;

  /// Words a person might type that the title does not contain. "night" should
  /// find the dark theme; the title says Theme.
  final List<String> keywords;
}

/// A shell action contributed by the caller, before it becomes a [DexCommand].
///
/// The shell owns its own actions — opening settings, toggling diagnostics —
/// and this keeps `commands.dart` from having to know about any of them.
@immutable
class DexCommandEntry {
  const DexCommandEntry({
    required this.title,
    required this.run,
    this.subtitle,
    this.keywords = const <String>[],
  });

  final String title;
  final String? subtitle;
  final VoidCallback run;
  final List<String> keywords;
}

/// Everything the shell can do right now.
///
/// Assembled from live state rather than declared once, so the palette can
/// never offer a command that cannot run: an app that is not installed or a
/// window that has closed simply is not in the list.
List<DexCommand> buildCommands({
  required List<AndroidApplication> applications,
  required List<WindowSessionState> windows,
  required List<DexCommandEntry> shellEntries,
  required ValueChanged<String> onLaunchApplication,
  required ValueChanged<String> onFocusWindow,
}) {
  return <DexCommand>[
    for (int i = 0; i < shellEntries.length; i++)
      DexCommand(
        // Indexed rather than derived from the title, so renaming an action
        // does not silently orphan its recency history.
        id: 'shell:$i',
        title: shellEntries[i].title,
        subtitle: shellEntries[i].subtitle,
        group: DexCommandGroup.shell,
        keywords: shellEntries[i].keywords,
        run: shellEntries[i].run,
      ),
    for (final WindowSessionState w in windows)
      DexCommand(
        id: 'window:${w.id}',
        title: 'Switch to ${w.application.label}',
        subtitle: 'Open window',
        group: DexCommandGroup.window,
        keywords: const <String>['focus', 'window'],
        run: () => onFocusWindow(w.id),
      ),
    for (final AndroidApplication a in applications)
      DexCommand(
        id: 'app:${a.packageName}',
        title: a.label,
        subtitle: a.packageName,
        group: DexCommandGroup.app,
        keywords: const <String>['launch', 'open'],
        run: () => onLaunchApplication(a.packageName),
      ),
  ];
}

/// [commands] that match [query], best first.
///
/// Scored with the same matcher the app drawer uses, so typing behaves
/// identically in both places. Keywords are scored below the title: a command
/// whose *name* you typed should beat one that merely lists the word.
List<DexCommand> searchCommands(List<DexCommand> commands, String query) {
  final String q = query.trim();
  if (q.isEmpty) return List<DexCommand>.of(commands);

  const double keywordPenalty = 500;
  final List<(double, DexCommand)> scored = <(double, DexCommand)>[];

  for (final DexCommand c in commands) {
    double? best = scoreMatch(q, c.title);
    for (final String k in c.keywords) {
      final double? viaKeyword = scoreMatch(q, k);
      if (viaKeyword == null) continue;
      final double weighted = viaKeyword - keywordPenalty;
      if (best == null || weighted > best) best = weighted;
    }
    if (best == null) continue;
    scored.add((best, c));
  }

  scored.sort(((double, DexCommand) a, (double, DexCommand) b) {
    final int byScore = b.$1.compareTo(a.$1);
    if (byScore != 0) return byScore;
    return a.$2.title.toLowerCase().compareTo(b.$2.title.toLowerCase());
  });

  return <DexCommand>[for (final (double, DexCommand) e in scored) e.$2];
}
