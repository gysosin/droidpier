import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/workspace/window_geometry_store.dart';

/// Remembering where a window was, per application.
void main() {
  const WindowGeometry g = WindowGeometry(
    x: 100,
    y: 80,
    width: 600,
    height: 400,
  );
  const Size workspace = Size(1600, 900);

  test('remembers and recalls a placement by package', () {
    final Map<String, RememberedWindow> store = rememberWindow(
      const <String, RememberedWindow>{},
      'com.example.a',
      g,
      maximised: false,
    );
    final RememberedWindow? back = store['com.example.a'];
    expect(back, isNotNull);
    expect(back!.geometry.x, 100);
    expect(back.geometry.width, 600);
    expect(back.maximised, isFalse);
  });

  test('maximised travels with the rectangle', () {
    // Relaunching a maximised app and quietly losing that is a regression a
    // person notices immediately.
    final Map<String, RememberedWindow> store = rememberWindow(
      const <String, RememberedWindow>{},
      'com.example.a',
      g,
      maximised: true,
    );
    expect(store['com.example.a']!.maximised, isTrue);
  });

  test('re-remembering replaces rather than duplicating', () {
    Map<String, RememberedWindow> store = rememberWindow(
      const <String, RememberedWindow>{},
      'com.example.a',
      g,
      maximised: false,
    );
    store = rememberWindow(
      store,
      'com.example.a',
      const WindowGeometry(x: 5, y: 5, width: 300, height: 200),
      maximised: false,
    );
    expect(store, hasLength(1));
    expect(store['com.example.a']!.geometry.x, 5);
  });

  test('evicts the oldest entry past capacity', () {
    Map<String, RememberedWindow> store = const <String, RememberedWindow>{};
    for (int i = 0; i < maxRememberedWindows + 5; i++) {
      store = rememberWindow(store, 'com.example.$i', g, maximised: false);
    }
    expect(store, hasLength(maxRememberedWindows));
    expect(
      store.containsKey('com.example.0'),
      isFalse,
      reason: 'the oldest should have gone first',
    );
    expect(store.containsKey('com.example.68'), isTrue);
  });

  test('touching an entry keeps it from being evicted', () {
    Map<String, RememberedWindow> store = const <String, RememberedWindow>{};
    store = rememberWindow(store, 'keep.me', g, maximised: false);
    for (int i = 0; i < maxRememberedWindows; i++) {
      if (i == maxRememberedWindows ~/ 2) {
        store = rememberWindow(store, 'keep.me', g, maximised: false);
      }
      store = rememberWindow(store, 'com.example.$i', g, maximised: false);
    }
    expect(store.containsKey('keep.me'), isTrue);
  });

  group('recall', () {
    test('returns null for a package never seen', () {
      expect(
        recallWindow(const <String, RememberedWindow>{}, 'nope', workspace),
        isNull,
      );
    });

    test('clamps a placement that would land off-screen', () {
      // A rectangle saved on a large monitor must not restore out of reach on
      // a small one: the title bar is the only way to drag it back.
      final Map<String, RememberedWindow> store = rememberWindow(
        const <String, RememberedWindow>{},
        'com.example.a',
        const WindowGeometry(x: 5000, y: 4000, width: 600, height: 400),
        maximised: false,
      );
      final WindowGeometry? out = recallWindow(
        store,
        'com.example.a',
        const Size(1280, 800),
      );
      expect(out, isNotNull);
      expect(out!.x, lessThan(1280));
      expect(out.y, lessThan(800));
    });

    test('a placement already on screen is returned unchanged', () {
      final Map<String, RememberedWindow> store = rememberWindow(
        const <String, RememberedWindow>{},
        'com.example.a',
        g,
        maximised: false,
      );
      final WindowGeometry? out = recallWindow(
        store,
        'com.example.a',
        workspace,
      );
      expect(out!.x, 100);
      expect(out.y, 80);
      expect(out.width, 600);
    });
  });
}
