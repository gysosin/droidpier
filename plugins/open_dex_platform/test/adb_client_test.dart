import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test(
    'signature conflict gives migration guidance and never uninstalls',
    () async {
      final executor = FakeProcessExecutor(
        const ProcessOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
        ),
      );
      final client = AdbClient(executor: executor);
      await expectLater(
        client.install('test-device', '/tmp/companion.apk'),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'migration guidance',
            contains('will not uninstall it automatically'),
          ),
        ),
      );
      expect(executor.invocations, 1);
      expect(executor.arguments, [
        '-s',
        'test-device',
        'install',
        '-r',
        '/tmp/companion.apk',
      ]);
    },
  );

  test('parses authorized, unauthorized, and Wi-Fi devices', () {
    const output = '''
List of devices attached
usb-serial device usb:1-2 product:aosp model:Pixel_Emulator device:generic transport_id:1
pending unauthorized usb:1-3 transport_id:2
192.0.2.4:5555 device product:sdk model:Pixel_Emulator device:generic
''';

    final devices = AdbClient.parseDevices(output);

    expect(devices, hasLength(3));
    expect(devices[0].name, 'Pixel Emulator');
    expect(devices[0].status, DeviceStatus.authorized);
    expect(devices[1].status, DeviceStatus.unauthorized);
    expect(devices[2].connectionKind, DeviceConnectionKind.wifi);
  });

  test('uses argument arrays for device shell commands', () async {
    final executor = FakeProcessExecutor(
      const ProcessOutput(exitCode: 0, stdout: 'violet\n', stderr: ''),
    );
    final client = AdbClient(executor: executor);

    final result = await client.shell('serial-1', const [
      'getprop',
      'ro.product.device',
    ]);

    expect(result, 'violet');
    expect(executor.arguments, [
      '-s',
      'serial-1',
      'shell',
      'getprop',
      'ro.product.device',
    ]);
  });

  test('surfaces timeouts without leaking a command line', () async {
    final client = AdbClient(
      executor: FakeProcessExecutor(
        const ProcessOutput(
          exitCode: 124,
          stdout: '',
          stderr: '',
          timedOut: true,
        ),
      ),
    );

    expect(
      client.startServer,
      throwsA(
        isA<AdbException>()
            .having((error) => error.timedOut, 'timedOut', isTrue)
            .having(
              (error) => error.message,
              'message',
              'The operation timed out.',
            ),
      ),
    );
  });

  test('allows extra time for companion APK installation', () async {
    final executor = FakeProcessExecutor(
      const ProcessOutput(exitCode: 0, stdout: 'Success\n', stderr: ''),
    );
    final client = AdbClient(executor: executor);

    await client.install('serial-1', '/artifacts/companion.apk');

    expect(executor.timeout, const Duration(seconds: 60));
  });

  test(
    'supplies wireless pairing codes through stdin, not arguments',
    () async {
      final executor = FakeProcessExecutor(
        const ProcessOutput(
          exitCode: 0,
          stdout: 'Successfully paired\n',
          stderr: '',
        ),
      );
      final client = AdbClient(executor: executor);

      await client.pairWireless('192.0.2.20:37123', '123456');

      expect(executor.arguments, ['pair', '192.0.2.20:37123']);
      expect(executor.input, '123456\n');
    },
  );

  test('rejects malformed pairing codes before invoking ADB', () async {
    final executor = FakeProcessExecutor(
      const ProcessOutput(exitCode: 0, stdout: '', stderr: ''),
    );
    final client = AdbClient(executor: executor);

    await expectLater(
      client.pairWireless('192.0.2.20:37123', '12 3456'),
      throwsA(isA<AdbException>()),
    );
    expect(executor.invocations, 0);
  });

  test('rejects invalid reverse ports before invoking ADB', () async {
    final executor = FakeProcessExecutor(
      const ProcessOutput(exitCode: 0, stdout: '', stderr: ''),
    );
    final client = AdbClient(executor: executor);

    expect(
      () => client.reverse('serial-1', devicePort: 0, hostPort: 3698),
      throwsA(isA<AdbException>()),
    );
    expect(executor.invocations, 0);
  });

  test('creates and removes localabstract reverse tunnels', () async {
    final executor = FakeProcessExecutor(
      const ProcessOutput(exitCode: 0, stdout: '', stderr: ''),
    );
    final client = AdbClient(executor: executor);

    await client.reverseAbstract(
      'serial-1',
      deviceSocket: 'scrcpy_1234abcd',
      hostPort: 41234,
    );
    expect(executor.arguments, [
      '-s',
      'serial-1',
      'reverse',
      'localabstract:scrcpy_1234abcd',
      'tcp:41234',
    ]);

    await client.removeReverseByName('serial-1', 'scrcpy_1234abcd');
    expect(executor.arguments, [
      '-s',
      'serial-1',
      'reverse',
      '--remove',
      'localabstract:scrcpy_1234abcd',
    ]);
  });
}

class FakeProcessExecutor implements ProcessExecutor {
  FakeProcessExecutor(this.output);

  final ProcessOutput output;
  List<String>? arguments;
  Duration? timeout;
  String? input;
  int invocations = 0;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    invocations++;
    this.arguments = arguments;
    this.timeout = timeout;
    this.input = input;
    return output;
  }
}
