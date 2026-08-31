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
}
