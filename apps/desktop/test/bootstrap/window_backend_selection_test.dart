import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/window_backend_selection.dart';

void main() {
  test('defaults to the legacy backend', () {
    expect(resolveWindowBackend(const {}), WindowBackendSelection.legacy);
    expect(
      resolveWindowBackend(const {'OPEN_DEX_WINDOW_BACKEND': ''}),
      WindowBackendSelection.legacy,
    );
  });

  test('selects direct and legacy explicitly', () {
    expect(
      resolveWindowBackend(const {'OPEN_DEX_WINDOW_BACKEND': 'direct'}),
      WindowBackendSelection.direct,
    );
    expect(
      resolveWindowBackend(const {'OPEN_DEX_WINDOW_BACKEND': 'legacy'}),
      WindowBackendSelection.legacy,
    );
  });

  test('rejects an unknown backend instead of silently changing behavior', () {
    expect(
      () => resolveWindowBackend(const {'OPEN_DEX_WINDOW_BACKEND': 'external'}),
      throwsArgumentError,
    );
  });
}
