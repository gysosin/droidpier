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
  Stream<WindowBackendExit> get exits => const Stream<WindowBackendExit>.empty();

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
  Future<void> sendPointer(String sessionId, WindowPointerSample sample) async {}

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
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
    expect(fallback.launched, isEmpty, reason: 'no reason to try the older path');
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

  test('once it has fallen back it stops trying the path that failed', () async {
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
      reason: 'the failing path is tried once per device, not once per launch',
    );
    expect(fallback.launched, hasLength(3));
  });

  test('both failing reports the original failure, not the fallback one', () async {
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
