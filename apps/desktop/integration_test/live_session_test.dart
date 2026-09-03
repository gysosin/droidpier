import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/bootstrap/facade_factory.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Drives the real application against the real backend.
///
/// Everything else in this suite runs the widgets against
/// `MockOpenDexFacade`, which is what makes them fast and phone-free — and also
/// what makes them blind to the half of the product that only exists in a
/// running app: the plugins, the texture host, and the whole video path. A
/// window that streams is precisely the thing a widget test cannot render.
///
/// So this is deliberately not an assertion-heavy test. It boots the product,
/// opens an application, and *reports what happened*, because the failures
/// being chased here are ones nobody has been able to see: a stream that will
/// not start, and a window that stays black while claiming to be live.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Written to a file rather than stdout: the app runs in its own process and
  // its stdout does not reach the test runner's console, which is exactly the
  // kind of silent gap this harness exists to close.
  final File report = File(
    Platform.environment['DROIDPIER_REPORT'] ?? '/tmp/droidpier-live.txt',
  );
  report.writeAsStringSync('');
  void say(String line) {
    report.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> settle(WidgetTester tester, {int frames = 20}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('boot, list applications, open one, report the outcome', (
    WidgetTester tester,
  ) async {
    final OpenDexFacade facade = createFacade();
    addTearDown(facade.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data ?? facade.snapshot,
                facade: facade,
                now: DateTime.now(),
              ),
        ),
      ),
    );

    // Discovery, selection and connect, explicitly.
    //
    // The shell auto-connects only when it already sees exactly one authorised
    // phone, so something has to look first. In the product that is the shell's
    // own startup; here it is spelled out, both because the harness should not
    // depend on auto-connect's policy and because doing it by hand is what
    // makes each step's failure attributable.
    final CommandResult<List<DeviceSummary>> found =
        await facade.discoverDevices();
    say('DISCOVER ${found.runtimeType}');
    await settle(tester, frames: 6);

    final List<DeviceSummary> authorised = facade.snapshot.devices
        .where((DeviceSummary d) => d.status == DeviceStatus.authorized)
        .toList();
    for (final DeviceSummary d in facade.snapshot.devices) {
      say(
        'DEVICE ${d.id} ${d.name} ${d.connectionKind.name} ${d.status.name} '
        'android=${d.androidVersion ?? '?'}',
      );
    }
    if (authorised.isEmpty) {
      say('RESULT no authorised phone attached; stopping here');
      return;
    }

    // Prefer a USB phone: the wireless one drops off whenever the phone's
    // Wireless debugging screen closes, which makes a run non-reproducible.
    final DeviceSummary target = authorised.firstWhere(
      (DeviceSummary d) => d.connectionKind == DeviceConnectionKind.usb,
      orElse: () => authorised.first,
    );
    say('SELECT ${target.name} (${target.id})');
    await facade.selectDevice(target.id);
    await settle(tester, frames: 4);
    await facade.connectSelectedDevice();

    // Boot takes real seconds against a real phone.
    for (int i = 0; i < 90 && !facade.snapshot.boot.isReady; i++) {
      await settle(tester, frames: 4);
      if (facade.snapshot.boot.phase == BootPhase.failed) break;
    }

    final OpenDexSnapshot booted = facade.snapshot;
    say('BOOT phase=${booted.boot.phase.name}');
    if (booted.boot.error case final OpenDexError e) {
      say('BOOT error=${e.code.name} message=${e.message}');
      say('BOOT detail=${e.technicalDetails ?? '(none)'}');
    }
    say('APPS ${booted.applications.length}');
    if (!booted.boot.isReady) {
      say('RESULT boot did not reach ready; stopping here');
      return;
    }

    // Open the first launchable application through the real facade, which is
    // the same path the launcher's tap takes.
    final AndroidApplication? app = booted.applications
        .where((AndroidApplication a) => !a.isSystemApp)
        .cast<AndroidApplication?>()
        .firstWhere((AndroidApplication? a) => a != null, orElse: () => null);
    if (app == null) {
      say('RESULT no launchable application to open');
      return;
    }

    say('LAUNCH ${app.label} (${app.packageName})');
    await facade.launchApplication(app.packageName);

    // Give the stream a generous window to come up or fail.
    for (int i = 0; i < 60; i++) {
      await settle(tester, frames: 4);
      if (facade.snapshot.windows.any(
        (WindowSessionState w) =>
            w.status == WindowSessionStatus.streaming ||
            w.status == WindowSessionStatus.failed,
      )) {
        break;
      }
    }

    for (final WindowSessionState w in facade.snapshot.windows) {
      say(
        'WINDOW ${w.application.label} status=${w.status.name} '
        'fps=${w.presentedFramesPerSecond ?? '(unmeasured)'}',
      );
      if (w.error case final OpenDexError e) {
        say('WINDOW error=${e.code.name} message=${e.message}');
        say('WINDOW detail=${e.technicalDetails ?? '(none)'}');
      }
    }
    say('RESULT windows=${facade.snapshot.windows.length}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
