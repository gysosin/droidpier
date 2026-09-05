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
    expect(snapshot.displayMirror.status, DisplayMirrorStatus.idle);
    expect(snapshot.displayMirror.surface, isNull);
    expect(snapshot.displayMirror.isStreaming, isFalse);
  });

  test('the display mirror streams only with a surface to draw', () {
    const surface = WindowSurface(
      textureId: 7,
      pixelSize: WindowPixelSize(width: 540, height: 1170),
    );
    const streaming = DisplayMirrorState(
      status: DisplayMirrorStatus.streaming,
      surface: surface,
    );
    expect(streaming.isStreaming, isTrue);
    expect(
      const DisplayMirrorState(
        status: DisplayMirrorStatus.streaming,
      ).isStreaming,
      isFalse,
    );
    final stopped = streaming.copyWith(
      status: DisplayMirrorStatus.idle,
      surface: null,
    );
    expect(stopped.surface, isNull);
    expect(
      streaming.copyWith(status: DisplayMirrorStatus.failed).surface,
      surface,
    );
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

  test('a window belongs to a workspace, a scale and an orientation', () {
    const session = WindowSessionState(
      id: 'window-1',
      application: AndroidApplication(
        packageName: 'com.example.demo',
        label: 'Demo',
      ),
      status: WindowSessionStatus.streaming,
    );

    // Defaults keep every existing caller on the first workspace, unscaled and
    // portrait, so adding these fields cannot move a window that never asked.
    expect(session.workspace, 1);
    expect(session.scale, 1.0);
    expect(session.isLandscape, isFalse);
  });

  test('copyWith carries every field a window transition must not drop', () {
    const source = WindowSessionState(
      id: 'window-1',
      application: AndroidApplication(
        packageName: 'com.example.demo',
        label: 'Demo',
      ),
      status: WindowSessionStatus.streaming,
      workspace: 3,
      scale: 1.25,
      isLandscape: true,
      zOrder: 7,
      producedFramesPerSecond: 60,
    );

    // A transition that only raises the window must preserve the rest. This is
    // the bug the two hand-rolled copy helpers were one field away from.
    final raised = source.copyWith(zOrder: 9);

    expect(raised.zOrder, 9);
    expect(raised.workspace, 3);
    expect(raised.scale, 1.25);
    expect(raised.isLandscape, isTrue);
    expect(raised.producedFramesPerSecond, 60);
    expect(raised.application.packageName, 'com.example.demo');
  });

  test('the snapshot opens on the first workspace', () {
    const snapshot = OpenDexSnapshot();

    expect(snapshot.currentWorkspace, 1);
    expect(kWorkspaceCount, 4);
    expect(snapshot.copyWith(currentWorkspace: 3).currentWorkspace, 3);
  });
}
