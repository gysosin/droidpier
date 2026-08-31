import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/desktop_clipboard_coordinator.dart';
import 'package:open_dex_core/open_dex_core.dart';

void main() {
  test(
    'host failure pauses once with an explanation and supports retry',
    () async {
      final facade = MockOpenDexFacade(scenario: MockScenario.ready);
      final host = _FakeHostClipboard('synthetic retry text')..failRead = true;
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
      expect(facade.snapshot.clipboard.syncEnabled, isFalse);
      expect(facade.snapshot.clipboard.message, contains('desktop clipboard'));
      for (var i = 0; i < 20; i++) {
        await coordinator.synchronizeOnce();
      }
      expect(host.reads, 1);
      host.failRead = false;
      await facade.setClipboardSync(true);
      await Future<void>.delayed(Duration.zero);
      expect(facade.snapshot.clipboard.text, 'synthetic retry text');
      expect(facade.snapshot.clipboard.message, isNull);
    },
  );
  test(
    'disconnected startup never reads host clipboard or produces a command',
    () async {
      final facade = MockOpenDexFacade(scenario: MockScenario.disconnected);
      final host = _FakeHostClipboard('private synthetic text');
      final coordinator = DesktopClipboardCoordinator(
        facade: facade,
        hostClipboard: host,
        pollInterval: const Duration(days: 1),
      )..start();
      for (var i = 0; i < 20; i++) {
        await coordinator.synchronizeOnce();
      }
      expect(host.reads, 0);
      expect(facade.snapshot.clipboard.syncEnabled, isFalse);
      await coordinator.dispose();
      await facade.dispose();
    },
  );
  test(
    'a clipboard read completed after disconnect never writes to the phone',
    () async {
      final facade = MockOpenDexFacade(scenario: MockScenario.ready);
      final host = _FakeHostClipboard('late synthetic content')
        ..pendingRead = Completer<String?>();
      final coordinator = DesktopClipboardCoordinator(
        facade: facade,
        hostClipboard: host,
        pollInterval: const Duration(days: 1),
      )..start();
      await facade.setClipboardSync(true);
      await Future<void>.delayed(Duration.zero);
      await facade.disconnect();
      host.pendingRead!.complete('late synthetic content');
      await Future<void>.delayed(Duration.zero);
      expect(facade.snapshot.clipboard.text, isNot('late synthetic content'));
      await coordinator.dispose();
      await facade.dispose();
    },
  );

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
  int reads = 0;
  bool failRead = false;
  Completer<String?>? pendingRead;

  @override
  Future<String?> readText() async {
    reads++;
    if (failRead) throw StateError('Synthetic host clipboard failure');
    return pendingRead != null ? await pendingRead!.future : text;
  }

  @override
  Future<void> writeText(String value) async => text = value;
}
