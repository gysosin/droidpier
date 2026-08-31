import 'package:open_dex_api/open_dex_api.dart';
import 'package:test/test.dart';

void main() {
  test('initial snapshot is safe for immediate UI rendering', () {
    const snapshot = OpenDexSnapshot();

    expect(snapshot.boot.phase, BootPhase.idle);
    expect(snapshot.boot.stages.map((stage) => stage.id), [
      'adb',
      'device',
      'agent',
      'companion',
      'applications',
    ]);
    expect(snapshot.devices, isEmpty);
    expect(snapshot.windows, isEmpty);
    expect(snapshot.recovery.phase, RecoveryPhase.idle);
  });

  test('command failures expose user-safe recovery metadata', () {
    const result = CommandFailure<void>(
      OpenDexError(
        code: OpenDexErrorCode.deviceOffline,
        message: 'The Android device is offline.',
        retryable: true,
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.error.retryable, isTrue);
  });

  test('window sessions expose compositor and input coordinates', () {
    const session = WindowSessionState(
      id: 'window-1',
      application: AndroidApplication(
        packageName: 'com.example.demo',
        label: 'Demo',
      ),
      status: WindowSessionStatus.streaming,
      surface: WindowSurface(
        textureId: 42,
        pixelSize: WindowPixelSize(width: 1280, height: 720),
      ),
      producedFramesPerSecond: 60,
      presentedFramesPerSecond: 59.8,
      droppedFramesPerSecond: 0.2,
    );

    expect(session.geometry.width, 640);
    expect(session.displayState, WindowDisplayState.normal);
    expect(session.surface?.textureId, 42);
    expect(session.surfaceSize?.height, 720);
    expect(session.producedFramesPerSecond, 60);
    expect(session.presentedFramesPerSecond, 59.8);
    expect(session.droppedFramesPerSecond, 0.2);
  });
}
