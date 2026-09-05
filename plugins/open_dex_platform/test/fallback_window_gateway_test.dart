import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

/// Falling back when the preferred video path will not start.
///
/// Measured on two real phones: the direct pipeline streams happily on a Redmi
/// Note 7 Pro (Android 13) and dies on a Galaxy F41 (Android 12) with "the
/// scrcpy video stream ended before session metadata" — while the legacy path
/// streams that same phone without complaint. scrcpy's own client creates a
/// virtual display on the Galaxy without trouble, so this is not the device
/// refusing; it is our direct pipeline not coping with it.
///
/// Until that is understood, an app that cannot open is a worse outcome than an
/// app opened by the older path.
class _StubGateway implements WindowGateway {
  _StubGateway({required this.name, required this.failLaunch});

  final String name;
  final bool failLaunch;
  final List<String> launched = <String>[];
  bool disposed = false;

  @override
  Stream<WindowBackendExit> get exits =>
      const Stream<WindowBackendExit>.empty();

  @override
  Stream<WindowBackendTelemetry> get telemetry =>
      const Stream<WindowBackendTelemetry>.empty();

  @override
  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  }) async {
    launched.add(application.packageName);
    if (failLaunch) {
      throw StateError('$name refused to start');
    }
    return WindowBackendSession(id: sessionId ?? '$name-1', displayId: 1);
  }

  @override
  Future<void> close(String sessionId) async {}

  @override
  Future<void> sendPointer(
    String sessionId,
    WindowPointerSample sample,
  ) async {}

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A stub that can also open web addresses.
class _UrlStubGateway extends _StubGateway implements UrlWindowGateway {
  _UrlStubGateway({
    required super.name,
    super.failLaunch = false,
    this.failUrl = false,
  });
  final bool failUrl;
  final List<String> resolved = <String>[];
  final List<(String, String)> urls = <(String, String)>[];
  @override
  Future<String?> resolveBrowser(DeviceSummary device, String url) async {
    resolved.add(url);
    return 'com.android.chrome';
  }

  @override
  Future<WindowBackendSession> launchUrl(
    DeviceSummary device,
    AndroidApplication browser,
    String url, {
    String? sessionId,
  }) async {
    urls.add((browser.packageName, url));
    if (failUrl) throw StateError('$name could not open the address');
    return WindowBackendSession(id: sessionId ?? '$name-url-1', displayId: 2);
  }
}

void main() {
  const DeviceSummary device = DeviceSummary(
    id: 'serial',
    name: 'Phone',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
  );
  const AndroidApplication app = AndroidApplication(
    packageName: 'com.example.notes',
    label: 'Notes',
  );

  test('the preferred path is used when it works, and only it', () async {
    final _StubGateway preferred = _StubGateway(
      name: 'direct',
      failLaunch: false,
    );
    final _StubGateway fallback = _StubGateway(
      name: 'legacy',
      failLaunch: false,
    );
    final gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );

    await gateway.launch(device, app);
    expect(preferred.launched, hasLength(1));
    expect(
      fallback.launched,
      isEmpty,
      reason: 'no reason to try the older path',
    );
  });

  test('a refused launch is retried on the other path', () async {
    final _StubGateway preferred = _StubGateway(
      name: 'direct',
      failLaunch: true,
    );
    final _StubGateway fallback = _StubGateway(
      name: 'legacy',
      failLaunch: false,
    );
    final gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );

    final WindowBackendSession session = await gateway.launch(device, app);
    expect(session.id, isNotEmpty);
    expect(fallback.launched, hasLength(1));
  });

  test(
    'once it has fallen back it stops trying the path that failed',
    () async {
      // Retrying a pipeline that has already failed on this phone costs the
      // person the whole start-up timeout every single time they open an app.
      final _StubGateway preferred = _StubGateway(
        name: 'direct',
        failLaunch: true,
      );
      final _StubGateway fallback = _StubGateway(
        name: 'legacy',
        failLaunch: false,
      );
      final gateway = FallbackWindowGateway(
        preferred: preferred,
        fallback: fallback,
      );

      await gateway.launch(device, app);
      await gateway.launch(device, app);
      await gateway.launch(device, app);

      expect(
        preferred.launched,
        hasLength(1),
        reason:
            'the failing path is tried once per device, not once per launch',
      );
      expect(fallback.launched, hasLength(3));
    },
  );

  test(
    'both failing reports the original failure, not the fallback one',
    () async {
      // The preferred path is the one the product means to use; its reason is
      // the one worth surfacing.
      final gateway = FallbackWindowGateway(
        preferred: _StubGateway(name: 'direct', failLaunch: true),
        fallback: _StubGateway(name: 'legacy', failLaunch: true),
      );

      await expectLater(
        gateway.launch(device, app),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('direct'),
          ),
        ),
      );
    },
  );

  const AndroidApplication browser = AndroidApplication(
    packageName: 'com.android.chrome',
    label: 'Chrome',
  );

  test('a web address takes the preferred path when it can open one', () async {
    final _UrlStubGateway preferred = _UrlStubGateway(name: 'direct');
    final _StubGateway fallback = _StubGateway(
      name: 'legacy',
      failLaunch: false,
    );
    final FallbackWindowGateway gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );
    expect(
      await gateway.resolveBrowser(device, 'https://a.example'),
      'com.android.chrome',
    );
    final WindowBackendSession session = await gateway.launchUrl(
      device,
      browser,
      'https://a.example',
      sessionId: 's1',
    );
    expect(session.id, 's1');
    expect(preferred.urls, [('com.android.chrome', 'https://a.example')]);
    expect(fallback.launched, isEmpty);
    // Closing routes to the owner, as for any other session.
    await gateway.close('s1');
  });

  test('a failed address launch throws through and demotes nothing', () async {
    final _UrlStubGateway preferred = _UrlStubGateway(
      name: 'direct',
      failUrl: true,
    );
    final _StubGateway fallback = _StubGateway(
      name: 'legacy',
      failLaunch: false,
    );
    final FallbackWindowGateway gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );
    await expectLater(
      gateway.launchUrl(device, browser, 'https://a.example'),
      throwsA(isA<StateError>()),
    );
    // An ordinary launch still tries the preferred path: the browser failing
    // to open an address says nothing about the video pipeline.
    await gateway.launch(device, app);
    expect(preferred.launched, [app.packageName]);
    expect(fallback.launched, isEmpty);
  });

  test('only the fallback can open addresses, so it does', () async {
    final _StubGateway preferred = _StubGateway(
      name: 'direct',
      failLaunch: false,
    );
    final _UrlStubGateway fallback = _UrlStubGateway(name: 'legacy');
    final FallbackWindowGateway gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );
    final WindowBackendSession session = await gateway.launchUrl(
      device,
      browser,
      'https://a.example',
    );
    expect(session.id, 'legacy-url-1');
    expect(fallback.urls, hasLength(1));
  });

  test('neither path opening addresses is a capability gap, named', () async {
    final FallbackWindowGateway gateway = FallbackWindowGateway(
      preferred: _StubGateway(name: 'direct', failLaunch: false),
      fallback: _StubGateway(name: 'legacy', failLaunch: false),
    );
    await expectLater(
      gateway.resolveBrowser(device, 'https://a.example'),
      throwsA(
        isA<BackendFailure>().having(
          (BackendFailure f) => f.error.capability,
          'capability',
          'phone-browser',
        ),
      ),
    );
  });

  test('disposing disposes both', () async {
    final _StubGateway preferred = _StubGateway(
      name: 'direct',
      failLaunch: false,
    );
    final _StubGateway fallback = _StubGateway(
      name: 'legacy',
      failLaunch: false,
    );
    final gateway = FallbackWindowGateway(
      preferred: preferred,
      fallback: fallback,
    );
    await gateway.dispose();
    expect(preferred.disposed, isTrue);
    expect(fallback.disposed, isTrue);
  });
}
