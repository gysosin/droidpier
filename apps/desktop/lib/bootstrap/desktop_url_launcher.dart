import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// Hands a web address to whatever the host desktop uses to open one.
///
/// Each desktop has its own launcher and none of them is `url_launcher`: one
/// call does not justify a plugin, a platform channel and a build dependency on
/// three runners. The process is started detached because the desk must not
/// wait on, or own the lifetime of, a browser.
///
/// The URL is validated by the facade before it reaches here, so this never
/// sees a scheme a shell could misread.
class DesktopUrlLauncher implements UrlLauncherGateway {
  const DesktopUrlLauncher();

  @override
  Future<void> open(Uri url) async {
    final String executable;
    if (Platform.isMacOS) {
      executable = 'open';
    } else if (Platform.isWindows) {
      executable = 'explorer';
    } else {
      executable = 'xdg-open';
    }

    try {
      await Process.start(executable, <String>[
        url.toString(),
      ], mode: ProcessStartMode.detached);
    } on ProcessException catch (error) {
      // No handler installed for the scheme, or no launcher on this box. That
      // is a fact about the machine, not a fault in the link, so it is reported
      // as a missing capability rather than an error the user should retry.
      throw BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: 'This desktop has no application set up to open web links.',
          capability: 'url-launcher',
          technicalDetails: '$executable: ${error.message}',
        ),
      );
    }
  }
}
