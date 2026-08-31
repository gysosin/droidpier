import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.cancelled = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool cancelled;

  bool get succeeded => exitCode == 0 && !timedOut && !cancelled;
}

class ProcessCancellation {
  final _completion = Completer<void>();
  bool get isCancelled => _completion.isCompleted;
  Future<void> get future => _completion.future;
  void cancel() {
    if (!isCancelled) _completion.complete();
  }
}

abstract interface class CancellableProcessExecutor {
  Future<ProcessOutput> runCancellable(
    String executable,
    List<String> arguments, {
    Duration timeout,
    String? input,
    ProcessCancellation? cancellation,
  });
}

abstract interface class ProcessExecutor {
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout,
    String? input,
  });
}

class SystemProcessExecutor
    implements ProcessExecutor, CancellableProcessExecutor {
  const SystemProcessExecutor();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) => runCancellable(executable, arguments, timeout: timeout, input: input);

  @override
  Future<ProcessOutput> runCancellable(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
    ProcessCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return const ProcessOutput(
        exitCode: 130,
        stdout: '',
        stderr: '',
        cancelled: true,
      );
    }
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final deadline = Completer<int>();
    final timer = Timer(timeout, () => deadline.complete(124));
    final exitCode = await Future.any<int>([
      process.exitCode,
      deadline.future,
      if (cancellation != null) cancellation.future.then((_) => 130),
      () async {
        if (input != null) process.stdin.write(input);
        await process.stdin.close();
        return process.exitCode;
      }(),
    ]).whenComplete(timer.cancel);
    final cancelled = cancellation?.isCancelled ?? false;
    final timedOut = deadline.isCompleted && !cancelled;
    if (cancelled || timedOut) {
      process.kill(
        Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill,
      );
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => exitCode,
      );
    }
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdoutFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      ),
      stderr: await stderrFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      ),
      timedOut: timedOut,
      cancelled: cancelled,
    );
  }
}
