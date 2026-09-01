/// What build this is.
///
/// Stamped in at compile time by the build scripts. There is no
/// `package_info_plus` dependency, and adding one would mean a pubspec change
/// in another lane for a string, so compile-time defines carry it instead.
///
/// The build *time* is the part that matters. Several builds share one version
/// — `0.1.0-beta.2` has been the version across every build this week — so a
/// version string alone cannot answer "am I running the one I just installed?",
/// which is the only question this is here to answer.
library;

const String kAppVersion = String.fromEnvironment('DROIDPIER_VERSION');
const String kAppBuild = String.fromEnvironment('DROIDPIER_BUILD');
const String kAppBuiltAt = String.fromEnvironment('DROIDPIER_BUILT_AT');

/// The label shown in Settings → About.
String versionLabel({
  String version = kAppVersion,
  String build = kAppBuild,
  String builtAtIso = kAppBuiltAt,
}) {
  if (version.isEmpty) {
    // A run from source, or a build that forgot the defines. Saying so is
    // honest; printing a version that was never stamped would be a lie in the
    // one place somebody goes to check.
    return 'development build';
  }

  final StringBuffer out = StringBuffer(version);
  if (build.isNotEmpty) out.write(' (build $build)');

  final DateTime? at = DateTime.tryParse(builtAtIso);
  if (at != null) {
    final DateTime utc = at.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    out.write(
      ' · built ${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC',
    );
  }
  return out.toString();
}
