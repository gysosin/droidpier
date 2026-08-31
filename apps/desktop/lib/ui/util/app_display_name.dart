/// Presentation-only fallback for an application with no real label.
///
/// The Android agent currently sends `label = packageName` (see `Main.java`),
/// so the drawer was showing `com.android.settings` where a person expects
/// "Settings". This derives something readable from the package instead.
///
/// It is a **stopgap and a guess**, so the full package name stays visible
/// beside it rather than being replaced: `com.google.android.gm` derives to
/// "Gm", which is wrong — it is Gmail. Showing both means the guess can never
/// hide the truth. When the agent sends real labels this whole file goes away.
library;

/// True when [label] carries no more information than the package name.
bool isPlaceholderLabel(String label, String packageName) =>
    label.trim() == packageName.trim();

/// A readable name derived from a package name.
///
/// Takes the last meaningful segment and title-cases it, skipping segments that
/// carry no meaning on their own.
String displayNameFor(String packageName) {
  const Set<String> noise = <String>{
    'android',
    'app',
    'apps',
    'client',
    'com',
    'google',
    'main',
    'mobile',
    'net',
    'org',
    'ui',
  };
  final List<String> parts = packageName
      .split('.')
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return packageName;
  }
  String chosen = parts.last;
  if (noise.contains(chosen.toLowerCase()) && parts.length > 1) {
    chosen = parts[parts.length - 2];
  }
  // Split camelCase and underscores so `mediaPlayer` reads as "Media Player".
  final String spaced = chosen
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp('([a-z0-9])([A-Z])'),
        (Match m) => '${m[1]} ${m[2]}',
      );
  return spaced
      .split(' ')
      .where((String w) => w.isNotEmpty)
      .map((String w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
