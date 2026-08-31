import 'dart:async';
import 'dart:io';

import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a service already stopped is safe even when Android returns 255',
    () async {
      final adb = AdbClient(
        executor: _Executor(
          const ProcessOutput(
            exitCode: 255,
            stdout: 'Stopping service: Intent {}\n',
            stderr: 'Service not stopped: was not running.\n',
          ),
        ),
      );
      await adb.stopServiceIfRunning(
        'synthetic-device',
        'example/.CompanionService',
      );
    },
  );
  test('an explicitly stopped service is safe despite OEM exit 255', () async {
    final adb = AdbClient(
      executor: _Executor(
        const ProcessOutput(
          exitCode: 255,
          stdout: 'Stopping service: Intent {}\n',
          stderr: 'Service stopped\n',
        ),
      ),
    );
    await adb.stopServiceIfRunning(
      'synthetic-device',
      'example/.CompanionService',
    );
  });
  test('service permission failure still aborts startup', () async {
    final adb = AdbClient(
      executor: _Executor(
        const ProcessOutput(
          exitCode: 255,
          stdout: '',
          stderr: 'Permission Denial: not allowed',
        ),
      ),
    );
    await expectLater(
      adb.stopServiceIfRunning('synthetic-device', 'example/.CompanionService'),
      throwsA(isA<AdbException>()),
    );
  });
  test(
    'ADB zero exit with rejected pairing is not successful pairing',
    () async {
      final adb = AdbClient(
        executor: _Executor(
          const ProcessOutput(
            exitCode: 0,
            stdout: 'Enter pairing code: Failed: Wrong password or connection was dropped.\n',
            stderr: '',
          ),
        ),
      );
      await expectLater(
        adb.pairWireless('192.0.2.1:12345', '012345'),
        throwsA(isA<AdbException>()),
      );
    },
  );
  test('ADB zero exit with connect failure is not success', () async {
    final adb = AdbClient(
      executor: _Executor(
        const ProcessOutput(
          exitCode: 0,
          stdout: 'failed to connect: connection refused',
          stderr: '',
        ),
      ),
    );
    await expectLater(
      adb.connectWireless('192.0.2.1:12345'),
      throwsA(isA<AdbException>()),
    );
  });
  test(
    'QR secrets and leading-zero codes go to stdin, not process arguments',
    () async {
      final executor = _Executor(
        const ProcessOutput(
          exitCode: 0,
          stdout: 'Enter pairing code: Successfully paired to 192.0.2.1:12345 [guid=synthetic-guid]\n',
          stderr: '',
        ),
      );
      final adb = AdbClient(executor: executor);
      expect(
        await adb.pairWirelessSecret('192.0.2.1:12345', 'synthetic_QR-secret'),
        'synthetic-guid',
      );
      expect(executor.arguments, ['pair', '192.0.2.1:12345']);
      expect(executor.input, 'synthetic_QR-secret\n');
      await adb.pairWireless('192.0.2.1:12345', '012345');
      expect(executor.input, '012345\n');
    },
  );
  test(
    'scoped IPv6 endpoints are accepted, invalid ports never start ADB',
    () async {
      final executor = _Executor(
        const ProcessOutput(
          exitCode: 0,
          stdout: 'connected to [fe80::1%3]:12345',
          stderr: '',
        ),
      );
      final adb = AdbClient(executor: executor);
      await adb.connectWireless('[fe80::1%3]:12345');
      final count = executor.calls;
      await expectLater(
        adb.connectWireless('192.0.2.1:65536'),
        throwsA(isA<AdbException>()),
      );
      expect(executor.calls, count);
    },
  );
  test(
    'cancel terminates only the owned client and closes its output pipes',
    () async {
      if (!Platform.isLinux) return;
      final cancellation = ProcessCancellation();
      final timer = Timer(
        const Duration(milliseconds: 100),
        cancellation.cancel,
      );
      addTearDown(timer.cancel);
      final watch = Stopwatch()..start();
      final result = await const SystemProcessExecutor().runCancellable(
        '/usr/bin/python3',
        ['-c', 'import time; time.sleep(20)'],
        cancellation: cancellation,
      );
      expect(result.cancelled, isTrue);
      expect(result.succeeded, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    },
  );
}

class _Executor implements ProcessExecutor {
  _Executor(this.output);
  final ProcessOutput output;
  List<String>? arguments;
  String? input;
  int calls = 0;
  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    this.arguments = arguments;
    this.input = input;
    calls++;
    return output;
  }
}
