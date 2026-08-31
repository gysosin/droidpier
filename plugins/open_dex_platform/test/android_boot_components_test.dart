import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';
import 'package:test/test.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  const device = DeviceSummary(
    id: 'test-device',
    name: 'Test phone',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
  );

  test('agent component reports a typed missing-artifact failure', () async {
    final component = AgentBootComponent(
      adb: AdbClient(executor: _UnusedExecutor()),
      sessionToken: 'a' * 43,
      agentJarPath: '/definitely/missing/open-dex-agent.jar',
    );

    await expectLater(
      component.start(device),
      throwsA(
        isA<BackendFailure>().having(
          (failure) => failure.error.code,
          'error code',
          OpenDexErrorCode.deploymentFailed,
        ),
      ),
    );
  });

  test(
    'companion component reports a typed missing-artifact failure',
    () async {
      final component = CompanionBootComponent(
        adb: AdbClient(executor: _UnusedExecutor()),
        sessionToken: 'b' * 43,
        companionApkPath: '/definitely/missing/open-dex-companion.apk',
      );

      await expectLater(
        component.start(device),
        throwsA(
          isA<BackendFailure>().having(
            (failure) => failure.error.code,
            'error code',
            OpenDexErrorCode.deploymentFailed,
          ),
        ),
      );
    },
  );

  test('application catalog rejects malformed rows and sorts labels', () {
    final applications = ApplicationCatalogBootComponent.parseApplications([
      {'packageName': 'com.example.zed', 'label': 'Zed'},
      {
        'packageName': 'com.example.alpha',
        'label': 'Alpha',
        'iconPngBase64': _onePixelPng,
        'isSystemApp': true,
      },
      {'packageName': 'not a package', 'label': 'Unsafe'},
      {'label': 'Missing package'},
    ]);

    expect(applications.map((application) => application.packageName), [
      'com.example.alpha',
      'com.example.zed',
    ]);
    expect(applications.first.iconPng, isNotEmpty);
    expect(applications.first.isSystemApp, isTrue);
  });

  test('application catalog rejects malformed and oversized icons', () {
    final applications = ApplicationCatalogBootComponent.parseApplications([
      {
        'packageName': 'com.example.invalid',
        'label': 'Invalid',
        'iconPngBase64': 'not png',
      },
      {
        'packageName': 'com.example.oversized',
        'label': 'Oversized',
        'iconPngBase64': 'a' * 131073,
      },
    ]);

    expect(applications, hasLength(2));
    expect(
      applications.every((application) => application.iconPng == null),
      isTrue,
    );
  });

  test(
    'clipboard capability negotiation does not read until opted in',
    () async {
      final agent = _ClipboardAgent();
      final component = AgentClipboardBootComponent(agent: agent);
      addTearDown(() => component.stop(device));

      await component.start(device);

      expect(component.clipboard.syncEnabled, isFalse);
      expect(agent.requests, isEmpty);

      component.setSyncEnabled(true);
      await Future<void>.delayed(Duration.zero);

      expect(agent.requests, ['clipboard.get']);
      expect(component.clipboard.text, 'opt-in text');
    },
  );

  test(
    'companion notification actions use bounded protocol commands',
    () async {
      final companion = _NotificationCompanion();

      await companion.dismiss('notification-key');
      await companion.activate('notification-key', displayId: 14);
      await companion.dismissAll();

      expect(companion.requests.map((request) => request.$1), [
        'notification.dismiss',
        'notification.activate',
        'notification.dismissAll',
      ]);
      expect(companion.requests[0].$2, {'key': 'notification-key'});
      expect(companion.requests[1].$2, {
        'key': 'notification-key',
        'displayId': 14,
      });
      expect(companion.requests[2].$2, isEmpty);
      await expectLater(companion.dismiss(''), throwsA(isA<BackendFailure>()));
    },
  );
}

class _UnusedExecutor implements ProcessExecutor {
  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) => throw StateError('ADB must not run when the artifact is missing.');
}

class _ClipboardAgent extends AgentBootComponent {
  _ClipboardAgent()
    : super(
        adb: AdbClient(executor: _UnusedExecutor()),
        sessionToken: 'c' * 43,
        agentJarPath: '/unused',
      );

  final requests = <String>[];

  @override
  Set<String> get capabilities => const {'clipboard.get', 'clipboard.set'};

  @override
  Future<ProtocolEnvelope> request(
    String type, {
    Map<String, Object?> data = const {},
    String responseType = 'command.result',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    requests.add(type);
    return ProtocolEnvelope(
      id: 'response',
      type: responseType,
      timestamp: DateTime.utc(2026, 8, 25),
      data: const {'success': true, 'text': 'opt-in text'},
    );
  }
}

class _NotificationCompanion extends CompanionBootComponent {
  _NotificationCompanion()
    : super(
        adb: AdbClient(executor: _UnusedExecutor()),
        sessionToken: 'd' * 43,
        companionApkPath: '/unused',
      );

  final requests = <(String, Map<String, Object?>)>[];

  @override
  Future<ProtocolEnvelope> request(
    String type, {
    Map<String, Object?> data = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    requests.add((type, data));
    return ProtocolEnvelope(
      id: 'response',
      type: 'notification.command.result',
      timestamp: DateTime.utc(2026, 8, 25),
      data: const {'success': true},
    );
  }
}
