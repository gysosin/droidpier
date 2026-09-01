import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/diagnostics/diagnostics_report.dart';

/// The paste-ready bug report.
///
/// Every performance complaint currently arrives as "it feels slow", because a
/// person has no way to see or send what their session was actually doing. This
/// turns one button into a report a maintainer can act on.
void main() {
  OpenDexSnapshot snapshotWith({
    DeviceSummary? device,
    DeviceTelemetry telemetry = const DeviceTelemetry(),
    List<WindowSessionState> windows = const <WindowSessionState>[],
    BootState boot = const BootState(),
    AgentConnectionStatus agent = AgentConnectionStatus.connected,
  }) => OpenDexSnapshot(
    boot: boot,
    selectedDevice: device,
    telemetry: telemetry,
    windows: windows,
    agentStatus: agent,
  );

  const DeviceSummary device = DeviceSummary(
    id: 'ABC123',
    name: 'Redmi Note 7 Pro',
    connectionKind: DeviceConnectionKind.usb,
    status: DeviceStatus.authorized,
    model: 'Redmi Note 7 Pro',
    androidVersion: '10',
  );

  test('carries the build so a report can be matched to a version', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(device: device),
      buildLabel: '0.1.0-beta.2 (build 2) · built 2026-09-01 14:21 UTC',
      platform: 'Linux',
    );
    expect(out, contains('0.1.0-beta.2 (build 2)'));
    expect(out, contains('Linux'));
  });

  test('names the phone and its Android version', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(device: device),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('Redmi Note 7 Pro'));
    expect(out, contains('10'));
  });

  test('reports latency and throughput when the phone supplies them', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(
        device: device,
        telemetry: const DeviceTelemetry(
          linkLatency: TelemetryMeasurement(
            value: 12.5,
            unit: TelemetryUnit.milliseconds,
          ),
          throughput: TelemetryMeasurement(
            value: 4200,
            unit: TelemetryUnit.bytesPerSecond,
          ),
        ),
      ),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('12.5'));
    expect(out, contains('4200'));
  });

  test('says a measurement is unavailable rather than inventing a zero', () {
    // A report that prints "0 ms" for a latency nobody measured sends a
    // maintainer after the wrong thing.
    final String out = diagnosticsReport(
      snapshot: snapshotWith(device: device),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('not measured'));
    expect(out, isNot(contains('0.0 ms')));
  });

  test('lists each open window with its presented frame rate', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(
        device: device,
        windows: <WindowSessionState>[
          const WindowSessionState(
            id: 'w1',
            application: AndroidApplication(
              packageName: 'com.google.android.youtube',
              label: 'YouTube',
            ),
            status: WindowSessionStatus.streaming,
            geometry: WindowGeometry(x: 0, y: 0, width: 640, height: 480),
            presentedFramesPerSecond: 41.2,
          ),
        ],
      ),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('YouTube'));
    expect(out, contains('41.2'));
    expect(out, contains('streaming'));
  });

  test('includes a boot error, which is the thing worth reporting', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(
        device: device,
        boot: const BootState(
          phase: BootPhase.failed,
          message: 'agent did not start',
          error: OpenDexError(
            code: OpenDexErrorCode.connectionFailed,
            message: 'no frame produced',
          ),
        ),
      ),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('no frame produced'));
    expect(out, contains('failed'));
  });

  test('survives having no phone connected at all', () {
    // Someone reporting "it never connects" has no device, and that is exactly
    // when they most need to send a report.
    final String out = diagnosticsReport(
      snapshot: snapshotWith(),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, contains('No phone'));
    expect(out, isNotEmpty);
  });

  test('is markdown, so it pastes into an issue readably', () {
    final String out = diagnosticsReport(
      snapshot: snapshotWith(device: device),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(out, startsWith('### '));
    expect(out, contains('| '));
  });

  test('carries no device serial', () {
    // A bug report goes into a public issue tracker. The serial identifies the
    // hardware and is never needed to diagnose anything here.
    final String out = diagnosticsReport(
      snapshot: snapshotWith(device: device),
      buildLabel: 'x',
      platform: 'Linux',
    );
    expect(
      out,
      isNot(contains('ABC123')),
      reason: 'the serial must not travel into a public issue',
    );
  });
}
