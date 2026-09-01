import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/util/app_version.dart';

/// The version label shown in Settings → About.
///
/// It exists to answer one question a person actually asks: "am I running the
/// build I just installed?" The version string alone cannot answer that,
/// because several builds share one version, so the build time carries it.
void main() {
  test('shows version, build number and build time when all are known', () {
    expect(
      versionLabel(
        version: '0.1.0-beta.2',
        build: '2',
        builtAtIso: '2026-09-01T18:32:00Z',
      ),
      '0.1.0-beta.2 (build 2) · built 2026-09-01 18:32 UTC',
    );
  });

  test('omits the build number when it is absent', () {
    expect(
      versionLabel(
        version: '0.1.0-beta.2',
        build: '',
        builtAtIso: '2026-09-01T18:32:00Z',
      ),
      '0.1.0-beta.2 · built 2026-09-01 18:32 UTC',
    );
  });

  test('says so plainly when nothing was stamped in', () {
    // A `flutter run` from source, or a build that forgot the defines. Saying
    // "development build" is honest; printing a version that was never stamped
    // would be a lie in the one place someone goes to check.
    expect(
      versionLabel(version: '', build: '', builtAtIso: ''),
      'development build',
    );
  });

  test('degrades to the version when the timestamp is unusable', () {
    expect(
      versionLabel(
        version: '0.1.0-beta.2',
        build: '2',
        builtAtIso: 'not-a-date',
      ),
      '0.1.0-beta.2 (build 2)',
    );
  });
}
