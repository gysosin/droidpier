import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/desk/desk.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Responsive-layout coverage.
///
/// The boot screen switches between a two-column and a stacked arrangement at
/// 820 px, the app grid reflows on its own, and the side panel is a fixed 320.
/// None of that was ever exercised, so these drive each surface across the
/// range a desktop window actually gets dragged through and fail on any
/// overflow.
const List<Size> _sizes = <Size>[
  Size(1920, 1080), // maximised
  Size(1280, 800), // typical
  Size(1024, 720), // small laptop
  Size(900, 700), // just above the boot breakpoint
  Size(800, 640), // just below it — stacked layout
  Size(640, 560), // narrow
  Size(480, 620), // very narrow
];

AndroidApplication _app(String label) => AndroidApplication(
  packageName: 'com.example.${label.toLowerCase()}',
  label: label,
);

/// Any RenderFlex overflow is reported through FlutterError, so a clean pump
/// is the assertion.
void _expectNoOverflow(WidgetTester tester, Size size) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'overflow at ${size.width.toInt()}x${size.height.toInt()}',
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: DexTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {

  const BootState booting = BootState(
    phase: BootPhase.awaitingHandshakes,
    message: 'Waiting for the phone to answer',
    stages: <BootStage>[
      BootStage(id: 'adb', label: 'ADB', status: StageStatus.complete),
      BootStage(id: 'device', label: 'Device', status: StageStatus.complete),
      BootStage(
        id: 'agent',
        label: 'Agent :3698',
        status: StageStatus.active,
        detail: 'Handshake sent',
      ),
      BootStage(id: 'companion', label: 'Companion :3699'),
      BootStage(id: 'applications', label: 'Applications'),
    ],
  );

  for (final Size size in _sizes) {
    final String at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('boot screen lays out at $at', (WidgetTester tester) async {
      await _pumpAt(
        tester,
        size,
        BootScreen(boot: booting, onConnect: () {}, onRetry: () {}),
      );
      _expectNoOverflow(tester, size);
      // Both arrangements must still show the rail; it is the screen.
      expect(find.text('Agent :3698'), findsOneWidget);
    });

    testWidgets('app drawer lays out at $at', (WidgetTester tester) async {
      await _pumpAt(
        tester,
        size,
        AppDrawer(
          onDismiss: () {},
          status: LoadStatus.ready,
          applications: <AndroidApplication>[
            for (final String l in <String>[
              'Camera',
              'Chrome',
              'Files',
              'Gallery',
              'Maps',
              'Messages',
              'Phone',
              'Settings',
            ])
              _app(l),
          ],
          onLaunch: (_) {},
          onRefresh: () {},
        ),
      );
      _expectNoOverflow(tester, size);
    });

    testWidgets('desk lays out at $at', (WidgetTester tester) async {
      await _pumpAt(
        tester,
        size,
        Desk(
          snapshot: const OpenDexSnapshot(
            media: MediaState(
              status: LoadStatus.ready,
              playback: PlaybackState.playing,
              title: 'Windowlicker',
              artist: 'Aphex Twin',
            ),
            telemetry: DeviceTelemetry(
              batteryPercentage: 62,
              charging: true,
              wifiEnabled: true,
            ),
          ),
          now: DateTime.utc(2026, 8, 24, 22),
          onOpenLauncher: () {},
          onWebSearch: (_) {},
          onMediaAction: (_) {},
          onFocusWindow: (_) {},
          onCloseWindow: (_) {},
          onNavKey: (_) {},
          onToggleControl: (_, _) {},
          onToggleClipboardSync: (_) {},
          onSetVolume: (_, _) {},
          onOpenPermissions: () {},
          onDismissNotification: (_) async {},
          onActivateNotification: (_) async {},
          onDismissAllNotifications: () async {},
          onOpenSettings: () {},
          onToggleFullscreen: () {},
          fullscreenActive: false,
          onLaunchApplication: (_) {},
          workspace: const SizedBox.shrink(),
          // With apps running, which is the state the desk is normally in.
          // Sweeping it empty is why a 35px taskbar overflow at 900 lived
          // through this suite: with no windows there are no running-app
          // chips, and the chips are half of what fills the bar.
          windows: <WorkspaceWindow>[
            for (final String l in <String>['Maps', 'Spotify', 'Camera'])
              WorkspaceWindow(
                session: WindowSessionState(
                  id: l,
                  application: _app(l),
                  status: WindowSessionStatus.streaming,
                  isFocused: l == 'Maps',
                ),
                geometry: const WindowGeometry(
                  x: 0,
                  y: 0,
                  width: 400,
                  height: 300,
                ),
                zOrder: 1,
              ),
          ],
          minimisedWindows: const <String>{},
        ),
      );
      _expectNoOverflow(tester, size);
      // The search bars anchor the desk's top-left; they must survive every
      // width (the bare clock is dropped when the desk is too narrow for it).
      expect(find.text('Search Google'), findsOneWidget);
    });

    testWidgets('taskbar lays out at $at', (WidgetTester tester) async {
      await _pumpAt(
        tester,
        size,
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TaskbarBar(
              minimised: const <String>{},
              // The real tray, not an empty box. Stubbing this out is why a
              // 35px overflow at 900px lived through the whole sweep: the bar
              // was being measured without the half of it that takes room.
              trailing: SystemTray(
                now: DateTime.utc(2026, 8, 25, 22, 10),
                telemetry: const DeviceTelemetry(
                  batteryPercentage: 87,
                  charging: true,
                  wifiEnabled: true,
                ),
                onOpenControls: () {},
                onOpenNotifications: () {},
                notificationCount: 3,
                onOpenSettings: () {},
                onToggleFullscreen: () {},
                fullscreenActive: false,
              ),
              windows: <WorkspaceWindow>[
                for (final String l in <String>['Maps', 'Spotify', 'Camera'])
                  WorkspaceWindow(
                    session: WindowSessionState(
                      id: l,
                      application: _app(l),
                      status: WindowSessionStatus.streaming,
                      isFocused: l == 'Maps',
                    ),
                    geometry: const WindowGeometry(
                      x: 0,
                      y: 0,
                      width: 400,
                      height: 300,
                    ),
                    zOrder: 1,
                  ),
              ],
              onOpenLauncher: () {},
              onFocus: (_) {},
              onClose: (_) {},
            ),
          ],
        ),
      );
      _expectNoOverflow(tester, size);
    });
  }

  // The composed product, not its parts.
  //
  // Surfaces tested in isolation get the full window; inside the shell they get
  // what is left after the rail trace and the menu bar. A clock overflow lived
  // through this whole suite because every case measured the desk alone, so the
  // shell itself is now swept too.
  for (final Size size in _sizes) {
    final String at = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('composed shell lays out at $at', (WidgetTester tester) async {
      final MockOpenDexFacade facade = MockOpenDexFacade(
        scenario: MockScenario.ready,
      );
      addTearDown(facade.dispose);
      await _pumpAt(
        tester,
        size,
        AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 24, 22),
        ),
      );
      _expectNoOverflow(tester, size);
    });
  }
}
