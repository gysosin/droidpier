import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get succeeded => exitCode == 0 && !timedOut;
}

abstract interface class ProcessExecutor {
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout,
    String? input,
  });
}

class SystemProcessExecutor implements ProcessExecutor {
  const SystemProcessExecutor();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    if (input != null) process.stdin.write(input);
    await process.stdin.close();
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        if (Platform.isWindows) {
          process.kill();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
        return 124;
      },
    );
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
      timedOut: timedOut,
    );
  }
}
