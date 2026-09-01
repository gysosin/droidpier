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
      final pendingRead = Completer<String?>();
      final host = _FakeHostClipboard('late synthetic content')
        ..pendingRead = pendingRead;
      final coordinator = DesktopClipboardCoordinator(
        facade: facade,
        hostClipboard: host,
        pollInterval: const Duration(days: 1),
      )..start();
      await facade.setClipboardSync(true);
      await Future<void>.delayed(Duration.zero);
      await facade.disconnect();
      pendingRead.complete('late synthetic content');
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

  test(
    'explicit host write waits for sync and wins pending phone text',
    () async {
      final facade = MockOpenDexFacade(scenario: MockScenario.ready);
      final pendingRead = Completer<String?>();
      final host = _FakeHostClipboard('old desktop text')
        ..pendingRead = pendingRead;
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
      await facade.setClipboardText('new phone text');
      final Future<void> firstWrite = coordinator.writeHostText(
        '### synthetic diagnostics',
      );
      final Future<void> secondWrite = coordinator.writeHostText(
        '### newer diagnostics',
      );
      await Future<void>.delayed(Duration.zero);
      expect(host.writes, isEmpty);

      pendingRead.complete('old desktop text');
      await Future.wait(<Future<void>>[firstWrite, secondWrite]);
      await Future<void>.delayed(Duration.zero);

      expect(host.writes, <String>[
        'new phone text',
        '### synthetic diagnostics',
        '### newer diagnostics',
      ]);
      expect(host.text, '### newer diagnostics');
      expect(facade.snapshot.clipboard.text, '### newer diagnostics');
    },
  );

  test('two initially idle explicit writes are serialized in order', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final pendingWrite = Completer<void>();
    final host = _FakeHostClipboard(null)..pendingWrite = pendingWrite;
    final coordinator = DesktopClipboardCoordinator(
      facade: facade,
      hostClipboard: host,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await facade.dispose();
    });

    final Future<void> first = coordinator.writeHostText('first copy');
    final Future<void> second = coordinator.writeHostText('second copy');
    await Future<void>.delayed(Duration.zero);
    expect(host.writes, <String>['first copy']);

    pendingWrite.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(host.writes, <String>['first copy', 'second copy']);
    expect(host.text, 'second copy');
  });

  test('phone text arriving during a host write is preserved', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final host = _FakeHostClipboard('initial desktop text');
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
    host.writes.clear();
    final pendingWrite = Completer<void>();
    host.pendingWrite = pendingWrite;

    final Future<void> write = coordinator.writeHostText(
      '### synthetic diagnostics',
    );
    await Future<void>.delayed(Duration.zero);
    await facade.setClipboardText('newer phone text');
    await Future<void>.delayed(Duration.zero);

    pendingWrite.complete();
    await write;
    await Future<void>.delayed(Duration.zero);

    expect(host.writes, <String>[
      '### synthetic diagnostics',
      'newer phone text',
    ]);
    expect(host.text, 'newer phone text');
    expect(facade.snapshot.clipboard.text, 'newer phone text');
  });

  test('explicit host write reports platform failure to its caller', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final host = _FakeHostClipboard(null)..failWrite = true;
    final coordinator = DesktopClipboardCoordinator(
      facade: facade,
      hostClipboard: host,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await facade.dispose();
    });

    await expectLater(
      coordinator.writeHostText('### synthetic diagnostics'),
      throwsA(isA<StateError>()),
    );
  });

  test('a queued explicit write fails after disposal', () async {
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);
    final pendingWrite = Completer<void>();
    final host = _FakeHostClipboard(null)..pendingWrite = pendingWrite;
    final coordinator = DesktopClipboardCoordinator(
      facade: facade,
      hostClipboard: host,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(facade.dispose);

    final Future<void> inFlight = coordinator.writeHostText('in flight');
    final Future<void> queued = coordinator.writeHostText('queued');
    final Future<void> queuedExpectation = expectLater(
      queued,
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(Duration.zero);

    await coordinator.dispose();
    pendingWrite.complete();
    await inFlight;
    await queuedExpectation;

    expect(host.writes, <String>['in flight']);
  });

  test(
    'failed write after disconnect cannot leak phone text on reconnect',
    () async {
      final facade = MockOpenDexFacade(scenario: MockScenario.ready);
      final host = _FakeHostClipboard('initial desktop text');
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
      final pendingWrite = Completer<void>();
      host
        ..pendingWrite = pendingWrite
        ..failWrite = true;

      final Future<void> failedWrite = coordinator.writeHostText(
        '### synthetic diagnostics',
      );
      final Future<void> failureExpectation = expectLater(
        failedWrite,
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      await facade.setClipboardText('stale phone text');
      await Future<void>.delayed(Duration.zero);
      await facade.disconnect();

      pendingWrite.complete();
      await failureExpectation;
      host
        ..failWrite = false
        ..writes.clear();
      facade.showScenario(MockScenario.ready);
      await facade.setClipboardSync(true);
      await Future<void>.delayed(Duration.zero);

      expect(host.writes, isNot(contains('stale phone text')));
      expect(host.text, 'initial desktop text');
    },
  );
}

class _FakeHostClipboard implements HostClipboardGateway {
  _FakeHostClipboard(this.text);

  String? text;
  int reads = 0;
  bool failRead = false;
  bool failWrite = false;
  Completer<String?>? pendingRead;
  Completer<void>? pendingWrite;
  final List<String> writes = <String>[];

  @override
  Future<String?> readText() async {
    reads++;
    if (failRead) throw StateError('Synthetic host clipboard failure');
    final gate = pendingRead;
    pendingRead = null;
    return gate != null ? await gate.future : text;
  }

  @override
  Future<void> writeText(String value) async {
    writes.add(value);
    final gate = pendingWrite;
    pendingWrite = null;
    if (gate != null) await gate.future;
    if (failWrite) throw StateError('Synthetic host clipboard write failure');
    text = value;
  }
}
