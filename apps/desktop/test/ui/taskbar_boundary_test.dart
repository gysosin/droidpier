import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// The width at which the taskbar admits the media strip.
///
/// Thresholds fail at their boundary or nowhere, and this one failed exactly
/// on it: the strip was allowed in at the width where it no longer fits beside
/// the nav pill, the grid button and the tray. The sweep in
/// `responsive_test.dart` steps 480, 640, 800, 900, 1024, 1280, 1920 and so
/// walks straight over the failing case without landing on it.
void main() {
  Future<FlutterError?> pumpAt(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TaskbarBar(
                minimised: const <String>{},
                windows: const <WorkspaceWindow>[],
                // Playing, so the strip is eligible at every width.
                media: const MediaState(
                  status: LoadStatus.ready,
                  playback: PlaybackState.playing,
                  title: 'Windowlicker',
                  artist: 'Aphex Twin',
                ),
                onMediaAction: (_) {},
                onNavKey: (_) {},
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
                onOpenLauncher: () {},
                onFocus: (_) {},
                onClose: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return tester.takeException() as FlutterError?;
  }

  for (final double w in <double>[880, 900, 920, 1000, 1080, 1100, 1120]) {
    testWidgets('the bar does not overflow at ${w.toInt()} wide', (
      WidgetTester tester,
    ) async {
      expect(
        await pumpAt(tester, w),
        isNull,
        reason: 'taskbar overflowed at ${w.toInt()}',
      );
    });
  }
}
