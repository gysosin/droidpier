import 'dart:convert';
import 'dart:io';

import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test('system executor writes input through a closed stdin pipe', () async {
    if (!Platform.isLinux && !Platform.isMacOS) return;

    final output = await const SystemProcessExecutor().run('/bin/sh', const [
      '-c',
      r'read value; printf "%s" "$value"',
    ], input: '654321\n');

    expect(output.succeeded, isTrue);
    expect(output.stdout, '654321');
  });

  test('managed process writes binary stdin without text encoding', () async {
    if (!Platform.isLinux || !File('/usr/bin/od').existsSync()) return;
    final process = await const SystemManagedProcessLauncher().start(
      '/usr/bin/od',
      const ['-An', '-t', 'u1'],
      captureOutput: true,
    );
    final output = utf8.decoder.bind(process.stdout).join();

    await process.writeBytes(const [0, 127, 255]);
    await process.flushInput();
    await process.closeInput();

    expect(await process.exitCode, 0);
    expect((await output).trim().split(RegExp(r'\s+')), ['0', '127', '255']);
  });
}
