import 'package:open_dex_api/open_dex_api.dart';

import '../util/app_display_name.dart';

/// How often and how recently one package was launched.
///
/// A UI-side mirror of the bootstrap's `LaunchRecord`. Deliberately not an
/// import of it: `lib/ui` talks to the facade and to values passed in, never to
/// the bootstrap, and two fields are cheaper to restate than that boundary is
/// to blur.
class AppLaunchStats {
  const AppLaunchStats({required this.count, required this.lastLaunchedMs});

  final int count;

  /// Milliseconds since epoch, UTC.
  final int lastLaunchedMs;
}

/// Match strength, best first. The values are the score floor for each tier, so
/// no amount of habit can lift a weaker kind of match above a stronger one —
/// history breaks ties, it does not overrule the query.
abstract final class _Tier {
  static const double prefix = 4000;

  /// Initials: WhatsApp is WA, Google Maps is GM.
  ///
  /// Not a nicety — it is the only thing that makes the drawer's motivating
  /// case work. "wa" does not appear in "WhatsApp" at all (w-h-a-t-s-a-p-p),
  /// so on substring rules alone "Software Update" wins it on softWAre, which
  /// is exactly the behaviour being replaced.
  static const double acronym = 3500;

  static const double wordStart = 3000;
  static const double substring = 2000;
  static const double subsequence = 1000;

  /// A package-name hit always ranks under any label hit: a person searching
  /// "maps" means the app called Maps.
  static const double packagePenalty = 900;
}

/// The most the launch history can add, kept below one tier step.
const double _maxHistoryBonus = 900;

/// Ranks [apps] against [query], dropping anything that does not match.
///
/// An empty query returns everything in alphabetical order, which is what the
/// drawer shows when it opens.
///
/// [history] weights the score by how often and how recently each package was
/// launched, so the drawer learns your habits. It can only reorder matches; it
/// never promotes something the query did not match.
List<AndroidApplication> rankApps(
  List<AndroidApplication> apps,
  String query, {
  Map<String, AppLaunchStats> history = const <String, AppLaunchStats>{},
  int? now,
}) {
  final String q = query.trim().toLowerCase();

  if (q.isEmpty) {
    final List<AndroidApplication> all = List<AndroidApplication>.of(apps);
    all.sort(
      (AndroidApplication a, AndroidApplication b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return all;
  }

  final int nowMs = now ?? DateTime.now().millisecondsSinceEpoch;

  final List<(double, AndroidApplication)> scored = <(double, AndroidApplication)>[];
  for (final AndroidApplication a in apps) {
    final double? base = _score(a, q);
    if (base == null) continue;
    scored.add((base + _historyBonus(history[a.packageName], nowMs), a));
  }

  scored.sort(((double, AndroidApplication) x, (double, AndroidApplication) y) {
    final int byScore = y.$1.compareTo(x.$1);
    if (byScore != 0) return byScore;
    // Stable and predictable when scores tie, rather than input order.
    return x.$2.label.toLowerCase().compareTo(y.$2.label.toLowerCase());
  });

  return <AndroidApplication>[
    for (final (double, AndroidApplication) e in scored) e.$2,
  ];
}

/// The best score this app earns for [q], or null if it does not match.
double? _score(AndroidApplication a, String q) {
  // Rank on what the drawer actually displays: a placeholder label is shown as
  // its derived name, so it must be searchable by that name too.
  final String shown = isPlaceholderLabel(a.label, a.packageName)
      ? displayNameFor(a.packageName)
      : a.label;

  double? onLabel = _scoreText(shown.toLowerCase(), q);

  // Run-together names have no spaces, so their only word boundary is the
  // capital. WhatsApp -> wa, PayPal -> pp.
  final String camel = _camelAcronym(shown);
  if (q.length > 1 && camel.length > 1 && camel.startsWith(q)) {
    final double byCamel =
        _Tier.acronym + (100 - camel.length).toDouble().clamp(0, 100);
    if (onLabel == null || byCamel > onLabel) onLabel = byCamel;
  }
  final double? onPackage = _scoreText(a.packageName.toLowerCase(), q);

  if (onLabel == null && onPackage == null) return null;
  if (onPackage == null) return onLabel;
  final double package = onPackage - _Tier.packagePenalty;
  if (onLabel == null) return package;
  return onLabel >= package ? onLabel : package;
}

/// Initials of each word: "google maps" -> "gm".
///
/// Case is already folded by the time scoring runs, so this reads word starts
/// rather than capitals. [_camelAcronym] covers the run-together names where
/// the capital is the only word boundary there is.
String _acronym(String text) {
  final StringBuffer b = StringBuffer();
  bool atStart = true;
  for (int i = 0; i < text.length; i++) {
    final int c = text.codeUnitAt(i);
    if (c == 0x20 || c == 0x2E || c == 0x5F || c == 0x2D) {
      atStart = true;
      continue;
    }
    if (atStart) {
      b.writeCharCode(c);
      atStart = false;
    }
  }
  return b.toString();
}

/// Initials from capitals in the original casing: "WhatsApp" -> "wa".
String _camelAcronym(String raw) {
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    final int c = raw.codeUnitAt(i);
    final bool upper = c >= 0x41 && c <= 0x5A;
    if (upper || i == 0) b.writeCharCode(upper ? c + 32 : c);
  }
  return b.toString();
}

/// One pass over [text]. No regex, no repeated allocation — this runs for every
/// application on every keystroke.
double? _scoreText(String text, String q) {
  if (text.isEmpty) return null;

  final String acro = _acronym(text);
  if (q.length > 1 && acro.startsWith(q)) {
    return _Tier.acronym + (100 - acro.length).toDouble().clamp(0, 100);
  }

  final int at = text.indexOf(q);
  if (at == 0) {
    // A shorter host string is the better match: "Maps" beats "Google Maps
    // Go" for "maps".
    return _Tier.prefix + (100 - text.length).toDouble().clamp(0, 100);
  }
  if (at > 0) {
    final bool wordStart = text.codeUnitAt(at - 1) == 0x20; // space
    final double tier = wordStart ? _Tier.wordStart : _Tier.substring;
    // Earlier is better.
    return tier + (100 - at).toDouble().clamp(0, 100);
  }

  // Scattered letters, in order. "gmp" finds "google maps".
  int qi = 0;
  int gaps = 0;
  int? last;
  for (int i = 0; i < text.length && qi < q.length; i++) {
    if (text.codeUnitAt(i) == q.codeUnitAt(qi)) {
      if (last != null && i != last + 1) gaps++;
      last = i;
      qi++;
    }
  }
  if (qi < q.length) return null;
  return _Tier.subsequence + (100 - gaps * 10).toDouble().clamp(0, 100);
}

/// Frequency with a recency lift, bounded so habit can never outrank the query.
double _historyBonus(AppLaunchStats? stats, int nowMs) {
  if (stats == null) return 0;

  // Diminishing: the difference between 1 and 10 launches matters far more
  // than between 100 and 110.
  final double frequency = stats.count <= 0
      ? 0
      : (stats.count > 64 ? 64 : stats.count) / 64 * 600;

  // Full credit today, fading over a fortnight.
  const int fortnight = 14 * 24 * 60 * 60 * 1000;
  final int age = nowMs - stats.lastLaunchedMs;
  final double recency = age <= 0
      ? 300
      : age >= fortnight
      ? 0
      : (1 - age / fortnight) * 300;

  final double total = frequency + recency;
  return total > _maxHistoryBonus ? _maxHistoryBonus : total;
}
