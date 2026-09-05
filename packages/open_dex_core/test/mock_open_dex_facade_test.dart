import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:test/test.dart';

void main() {
  test('ready scenario exposes deterministic UI data', () {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    expect(facade.snapshot.boot.phase, BootPhase.ready);
    expect(facade.snapshot.applications, hasLength(3));
    expect(facade.snapshot.selectedDevice?.name, 'Demo Android device');
  });

  test('launch and close update window state', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    final result = await facade.launchApplication('com.android.chrome');
    expect(result, isA<CommandSuccess<String>>());
    expect(facade.snapshot.windows, hasLength(1));

    final id = (result as CommandSuccess<String>).value;
    await facade.closeWindow(id);
    expect(facade.snapshot.windows, isEmpty);
  });

  test('failure scenario supplies a retryable safe error', () {
    final facade = MockOpenDexFacade(scenario: MockScenario.failure);
    addTearDown(facade.dispose);

    expect(
      facade.snapshot.boot.error?.code,
      OpenDexErrorCode.deviceUnauthorized,
    );
    expect(facade.snapshot.boot.error?.retryable, isTrue);
    expect(
      facade.snapshot.boot.stages
          .singleWhere((stage) => stage.id == 'device')
          .status,
      StageStatus.failed,
    );
  });

  test('notification actions keep mock previews interactive', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    expect(
      (await facade.activateNotification('demo-notification')).isSuccess,
      isTrue,
    );
    expect(
      (await facade.dismissNotification('demo-notification')).isSuccess,
      isTrue,
    );
    expect(facade.snapshot.notificationStatus, LoadStatus.empty);
    expect(facade.snapshot.notifications, isEmpty);
    expect((await facade.dismissAllNotifications()).isSuccess, isTrue);
  });

  test(
    'selecting a workspace moves the desk, and refuses one that is not there',
    () async {
      final facade = MockOpenDexFacade();
      addTearDown(facade.dispose);

      expect(facade.snapshot.currentWorkspace, 1);
      expect((await facade.selectWorkspace(3)).isSuccess, isTrue);
      expect(facade.snapshot.currentWorkspace, 3);

      // Out of range is refused rather than clamped: a taskbar that asked for
      // workspace 9 has a bug, and silently landing on 4 would hide it.
      expect((await facade.selectWorkspace(0)).isSuccess, isFalse);
      expect(
        (await facade.selectWorkspace(kWorkspaceCount + 1)).isSuccess,
        isFalse,
      );
      expect(facade.snapshot.currentWorkspace, 3);
    },
  );

  test('a launched app lands on the workspace you are looking at', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    expect((await facade.selectWorkspace(3)).isSuccess, isTrue);
    await facade.launchApplication('com.android.chrome');

    // Opening an app on desk 3 and having it appear on desk 1 is the kind of
    // thing that reads as the window failing to open at all.
    expect(facade.snapshot.windows.single.workspace, 3);
  });

  test('a window can be moved to another workspace', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    final launch = await facade.launchApplication('com.android.chrome');
    final id = (launch as CommandSuccess<String>).value;
    expect(facade.snapshot.windows.single.workspace, 1);

    expect((await facade.moveWindowToWorkspace(id, 2)).isSuccess, isTrue);
    expect(facade.snapshot.windows.single.workspace, 2);

    expect((await facade.moveWindowToWorkspace(id, 99)).isSuccess, isFalse);
    expect(
      (await facade.moveWindowToWorkspace('no-such-window', 2)).isSuccess,
      isFalse,
    );
    expect(facade.snapshot.windows.single.workspace, 2);
  });

  test('per-window zoom accepts the documented range only', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    final launch = await facade.launchApplication('com.android.chrome');
    final id = (launch as CommandSuccess<String>).value;
    expect(facade.snapshot.windows.single.scale, 1.0);

    expect((await facade.setWindowScale(id, 1.25)).isSuccess, isTrue);
    expect(facade.snapshot.windows.single.scale, 1.25);

    for (final rejected in <double>[
      0,
      -1,
      0.4,
      3.1,
      double.nan,
      double.infinity,
    ]) {
      expect(
        (await facade.setWindowScale(id, rejected)).isSuccess,
        isFalse,
        reason: 'scale $rejected must be refused',
      );
    }
    expect(facade.snapshot.windows.single.scale, 1.25);
  });

  test(
    'rotating a window swaps its geometry, and rotating back restores it',
    () async {
      final facade = MockOpenDexFacade();
      addTearDown(facade.dispose);

      final launch = await facade.launchApplication('com.android.chrome');
      final id = (launch as CommandSuccess<String>).value;
      final portrait = facade.snapshot.windows.single.geometry;
      expect(facade.snapshot.windows.single.isLandscape, isFalse);

      expect(
        (await facade.setWindowOrientation(id, landscape: true)).isSuccess,
        isTrue,
      );
      final landscape = facade.snapshot.windows.single;
      expect(landscape.isLandscape, isTrue);
      expect(landscape.geometry.width, portrait.height);
      expect(landscape.geometry.height, portrait.width);

      expect(
        (await facade.setWindowOrientation(id, landscape: false)).isSuccess,
        isTrue,
      );
      expect(facade.snapshot.windows.single.geometry.width, portrait.width);
      expect(facade.snapshot.windows.single.geometry.height, portrait.height);
    },
  );

  test('openUrl accepts web addresses and refuses everything else', () async {
    final facade = MockOpenDexFacade();
    addTearDown(facade.dispose);

    expect(
      (await facade.openUrl('https://example.com/search?q=a')).isSuccess,
      isTrue,
    );
    expect((await facade.openUrl('http://example.com')).isSuccess, isTrue);

    // The desk search feeds this, and a package label or notification body can
    // reach it too. Anything that is not a web address is a command injection
    // waiting to happen, so the facade refuses it rather than the caller.
    for (final rejected in <String>[
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,<script>',
      'ftp://example.com',
      '--version',
      '',
      'not a url',
    ]) {
      expect(
        (await facade.openUrl(rejected)).isSuccess,
        isFalse,
        reason: '"$rejected" must be refused',
      );
    }
  });

  test('the preview has no phone to mirror, and says so', () async {
    final facade = MockOpenDexFacade();
    final result = await facade.startDisplayMirror();
    expect(result, isA<CommandFailure<void>>());
    final state = facade.snapshot.displayMirror;
    expect(state.status, DisplayMirrorStatus.unavailable);
    expect(state.error?.message, 'The preview has no phone to mirror.');
    expect(state.surface, isNull);
    expect(await facade.stopDisplayMirror(), isA<CommandSuccess<void>>());
    expect(facade.snapshot.displayMirror.status, DisplayMirrorStatus.idle);
  });
}
