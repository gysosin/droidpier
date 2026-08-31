import 'dart:async';
import 'dart:io';

void installHostShutdownHandler(Future<void> Function() dispose) {
  if (!Platform.isLinux && !Platform.isMacOS) return;

  var shuttingDown = false;
  Future<void> shutDown(ProcessSignal signal) async {
    if (shuttingDown) return;
    shuttingDown = true;
    await dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutDown);
  ProcessSignal.sigterm.watch().listen(shutDown);
}
