import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/desktop_clipboard_coordinator.dart';
import 'package:open_dex_core/open_dex_core.dart';

void main() {
  test('synchronizes text both ways only while sharing is enabled', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final host = _FakeHostClipboard('from desktop');
    final coordinator = DesktopClipboardCoordinator(
      facade: facade,
      hostClipboard: host,
      pollInterval: const Duration(days: 1),
    )..start();
    addTearDown(() async {
      await coordinator.dispose();
      await facade.dispose();
    });

    await facade.setClipboardSync(true);
    await Future<void>.delayed(Duration.zero);
    expect(facade.snapshot.clipboard.text, 'from desktop');

    await facade.setClipboardText('from phone');
    await Future<void>.delayed(Duration.zero);
    expect(host.text, 'from phone');

    await facade.setClipboardSync(false);
    host.text = 'sharing is off';
    await coordinator.synchronizeOnce();
    expect(facade.snapshot.clipboard.text, 'from phone');
  });

  test('does not send oversized host clipboard text', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final original = facade.snapshot.clipboard.text;
    final host = _FakeHostClipboard(
      'x' * (DesktopClipboardCoordinator.maximumTextLength + 1),
    );
    final coordinator = DesktopClipboardCoordinator(
      facade: facade,
      hostClipboard: host,
      pollInterval: const Duration(days: 1),
    )..start();
    addTearDown(() async {
      await coordinator.dispose();
      await facade.dispose();
    });

    await facade.setClipboardSync(true);
    await Future<void>.delayed(Duration.zero);

    expect(facade.snapshot.clipboard.text, original);
  });
}

class _FakeHostClipboard implements HostClipboardGateway {
  _FakeHostClipboard(this.text);

  String? text;

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeText(String value) async => text = value;
}
