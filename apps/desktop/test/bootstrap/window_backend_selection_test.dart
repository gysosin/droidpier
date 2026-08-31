import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/window_backend_selection.dart';

void main() {
  test('defaults to the direct backend', () {
    expect(resolveWindowBackend(const {}), WindowBackendSelection.direct);
    expect(
      resolveWindowBackend(const {'OPEN_DEX_WINDOW_BACKEND': ''}),
      WindowBackendSelection.direct,
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
