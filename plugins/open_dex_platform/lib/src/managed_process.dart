import 'dart:async';
import 'dart:io';

abstract interface class ManagedProcess {
  Future<int> get exitCode;

  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<void> writeInput(String data);

  Future<void> writeBytes(List<int> data);

  Future<void> flushInput();

  Future<void> closeInput();

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

abstract interface class ManagedProcessLauncher {
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment,
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  });
}

class SystemManagedProcessLauncher implements ManagedProcessLauncher {
  const SystemManagedProcessLauncher();

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    bool captureOutput = false,
    bool lineBufferedOutput = false,
  }) async {
    final lineBuffer = lineBufferedOutput ? _lineBufferExecutable() : null;
    final process = await Process.start(
      lineBuffer ?? executable,
      lineBuffer == null ? arguments : ['-oL', '-eL', executable, ...arguments],
      mode: ProcessStartMode.normal,
      runInShell: false,
      environment: environment.isEmpty ? null : environment,
      workingDirectory: workingDirectory,
    );
    if (!captureOutput) {
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
    }
    return SystemManagedProcess(process, captureOutput: captureOutput);
  }

  static String? _lineBufferExecutable() {
    if (!Platform.isLinux) return null;
    for (final path in const ['/usr/bin/stdbuf', '/bin/stdbuf']) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}

class SystemManagedProcess implements ManagedProcess {
  SystemManagedProcess(this._process, {required this.captureOutput});

  final Process _process;
  final bool captureOutput;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stdout =>
      captureOutput ? _process.stdout : const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr =>
      captureOutput ? _process.stderr : const Stream<List<int>>.empty();

  @override
  Future<void> writeInput(String data) async {
    _process.stdin.write(data);
    await _process.stdin.flush();
  }

  @override
  Future<void> writeBytes(List<int> data) async {
    _process.stdin.add(data);
  }

  @override
  Future<void> flushInput() => _process.stdin.flush();

  @override
  Future<void> closeInput() => _process.stdin.close();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}
