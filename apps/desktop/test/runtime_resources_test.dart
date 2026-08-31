import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/runtime_resources.dart';

void main() {
  test('finds resources beside the packaged executable', () {
    final root = Directory.systemTemp.createTempSync('open-dex-runtime-');
    addTearDown(() => root.deleteSync(recursive: true));
    final executable = File('${root.path}/open_android_dex')
      ..writeAsStringSync('');
    final resource = File('${root.path}/resources/android/agent.jar')
      ..createSync(recursive: true)
      ..writeAsStringSync('agent');

    expect(
      findRuntimeFile(
        'resources/android/agent.jar',
        resolvedExecutable: executable.path,
        workingDirectory: Directory.systemTemp,
      )?.path,
      resource.path,
    );
  });

  test('falls back to the launch directory for archive wrappers', () {
    final root = Directory.systemTemp.createTempSync('open-dex-runtime-');
    addTearDown(() => root.deleteSync(recursive: true));
    final resource = File('${root.path}/resources/scrcpy/scrcpy')
      ..createSync(recursive: true)
      ..writeAsStringSync('scrcpy');

    expect(
      findRuntimeFile(
        'resources/scrcpy/scrcpy',
        resolvedExecutable: '/unrelated/open_android_dex',
        workingDirectory: root,
      )?.path,
      resource.path,
    );
  });

  test('finds an explicitly named executable on PATH', () {
    final root = Directory.systemTemp.createTempSync('open-dex-path-');
    addTearDown(() => root.deleteSync(recursive: true));
    final executable = File('${root.path}/ffmpeg')..writeAsStringSync('');

    expect(
      findExecutableOnPath('ffmpeg', pathEnvironment: root.path)?.path,
      executable.path,
    );
    expect(
      findExecutableOnPath('../ffmpeg', pathEnvironment: root.path),
      isNull,
    );
  });
}
