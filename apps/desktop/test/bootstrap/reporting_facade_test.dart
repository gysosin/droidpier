import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/bootstrap/reporting_facade.dart';

/// The reporting facade turns command failures into a user-facing banner — but
/// a capability the build simply lacks (notification actions on a companion
/// build) must not nag on every tap, while genuine failures still surface.
void main() {
  const capabilityGap = OpenDexError(
    code: OpenDexErrorCode.capabilityUnavailable,
    message: 'Notification actions are unavailable on this companion build.',
  );
  const realFailure = OpenDexError(
    code: OpenDexErrorCode.connectionFailed,
    message: 'The phone dropped.',
  );

  test('a capability gap on a notification action is not reported', () async {
    final errors = <OpenDexError>[];
    final facade = ReportingOpenDexFacade(
      delegate: _FakeDelegate(
        dismiss: const CommandFailure<void>(capabilityGap),
      ),
      onError: errors.add,
    );

    final result = await facade.dismissNotification('n1');

    expect(result.isSuccess, isFalse, reason: 'the failure still propagates');
    expect(errors, isEmpty, reason: 'but it does not reach the banner');
  });

  test('a real failure on a notification action is still reported', () async {
    final errors = <OpenDexError>[];
    final facade = ReportingOpenDexFacade(
      delegate: _FakeDelegate(dismiss: const CommandFailure<void>(realFailure)),
      onError: errors.add,
    );

    await facade.dismissNotification('n1');

    expect(errors, <OpenDexError>[realFailure]);
  });

  test('a capability gap elsewhere is still reported', () async {
    final errors = <OpenDexError>[];
    final facade = ReportingOpenDexFacade(
      delegate: _FakeDelegate(
        launch: const CommandFailure<String>(capabilityGap),
      ),
      onError: errors.add,
    );

    await facade.launchApplication('com.example');

    expect(errors, <OpenDexError>[capabilityGap]);
  });

  test(
    'a mirror the build lacks stays inside its frame, not a banner',
    () async {
      final errors = <OpenDexError>[];
      final facade = ReportingOpenDexFacade(
        delegate: _FakeDelegate(
          mirror: const CommandFailure<void>(capabilityGap),
        ),
        onError: errors.add,
      );

      final result = await facade.startDisplayMirror();

      expect(result.isSuccess, isFalse);
      expect(errors, isEmpty);
    },
  );
}

class _FakeDelegate implements OpenDexFacade {
  _FakeDelegate({this.dismiss, this.launch, this.mirror});

  final VoidResult? dismiss;
  final CommandResult<String>? launch;
  final VoidResult? mirror;

  @override
  Future<VoidResult> startDisplayMirror() async =>
      mirror ?? const CommandSuccess<void>(null);

  @override
  Future<VoidResult> dismissNotification(String notificationId) async =>
      dismiss ?? const CommandSuccess<void>(null);

  @override
  Future<CommandResult<String>> launchApplication(String packageName) async =>
      launch ?? const CommandSuccess<String>('w1');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
