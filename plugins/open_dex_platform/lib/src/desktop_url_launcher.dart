import 'dart:io';

import 'package:open_dex_core/open_dex_core.dart';

/// Opens URLs with the desktop's own handler.
///
/// This used to live in the interface, as a bare `Process.start('xdg-open')`
/// inside the shell. That made the one widget using it unrenderable without a
/// real desktop behind it, and it was the only thing in `lib/ui` reaching past
/// the facade. Moving it here costs a class and buys the rule back.
class ProcessDesktopUrlLauncher implements DesktopUrlLauncher {
  const ProcessDesktopUrlLauncher({this.executable});

  /// Overridable so a test can observe the call without opening a browser.
  /// Null means "whatever this platform uses", resolved when it is needed —
  /// a const constructor cannot call a getter for its default.
  final String? executable;

  static String get _platformOpener => switch (Platform.operatingSystem) {
    'macos' => 'open',
    'windows' => 'explorer',
    _ => 'xdg-open',
  };

  @override
  Future<void> open(String url) async {
    // Detached on purpose: the browser outlives the desk, and waiting on it
    // would hold a process handle for the rest of the session.
    await Process.start(
      executable ?? _platformOpener,
      <String>[url],
      mode: ProcessStartMode.detached,
    );
  }
}
