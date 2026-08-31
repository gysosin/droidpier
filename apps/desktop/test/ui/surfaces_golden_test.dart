@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/connect/phone_list.dart';
import 'package:open_android_dex/ui/permissions/permission_panel.dart';
import 'package:open_android_dex/ui/recovery/recovery_overlay.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/bench_backdrop.dart';
import 'package:open_android_dex/ui/widgets/link_rail.dart';

Future<void> _loadFonts() async {
  const Map<String, List<String>> families = <String, List<String>>{
    'InstrumentSans': <String>['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  // Material's icon font is not loaded in the test binding by default, so
  // icons render as tofu. Load it from the SDK cache so goldens show the truth.
  final String flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      Directory('../../.tools/flutter').absolute.path;
  final File iconFont = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    final FontLoader icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future<ByteData>.value(ByteData.sublistView(iconFont.readAsBytesSync())),
    );
    await icons.load();
  }

  for (final MapEntry<String, List<String>> entry in families.entries) {
    final FontLoader loader = FontLoader(entry.key);
    for (final String path in entry.value) {
      final File file = File(path);
      if (file.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

Widget _harness(Widget child, ThemeData theme) => MaterialApp(
  theme: theme,
  debugShowCheckedModeBanner: false,
  // Surfaces are never seen on bare white: put them on the product ground
  // so the golden shows what the person actually sees.
  home: Scaffold(
    backgroundColor: Colors.transparent,
    body: BenchBackdrop(child: child),
  ),
);

void main() {
  setUpAll(_loadFonts);

  // Dual-mode is part of the design bar, not an afterthought: every surface is
  // rendered in both themes so a contrast or hierarchy failure in light mode
  // shows up here rather than in front of a user.
  for (final (String mode, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('app drawer with placeholder labels, $mode', (
      WidgetTester tester,
    ) async {
      // What the live device actually sends today: label == packageName.
      await tester.binding.setSurfaceSize(const Size(900, 520));
      await tester.pumpWidget(
        _harness(
          AppDrawer(
            onDismiss: () {},
            status: LoadStatus.ready,
            applications: const <AndroidApplication>[
              AndroidApplication(
                packageName: 'com.android.settings',
                label: 'com.android.settings',
              ),
              AndroidApplication(
                packageName: 'com.google.android.gm',
                label: 'com.google.android.gm',
              ),
              AndroidApplication(
                packageName: 'com.spotify.music',
                label: 'com.spotify.music',
              ),
              AndroidApplication(
                packageName: 'com.example.mediaPlayer',
                label: 'com.example.mediaPlayer',
              ),
            ],
            onLaunch: _ignore,
            onRefresh: _ignoreVoid,
          ),
          theme,
        ),
      );
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(
        find.byType(AppDrawer),
        matchesGoldenFile('goldens/apps_placeholder_labels_$mode.png'),
      );
    });

    testWidgets('app drawer with the live trace, $mode', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 780));
      const List<String> labels = <String>[
        'Camera',
        'Chrome',
        'Files',
        'Gallery',
        'Gmail',
        'Maps',
        'Messages',
        'Phone',
        'Settings',
        'Spotify',
        'WhatsApp',
        'YouTube',
      ];
      await tester.pumpWidget(
        _harness(
          Column(
            children: <Widget>[
              Expanded(
                child: AppDrawer(
                  onDismiss: () {},
                  status: LoadStatus.ready,
                  applications: <AndroidApplication>[
                    for (final String l in labels)
                      AndroidApplication(
                        packageName: 'com.example.${l.toLowerCase()}',
                        label: l,
                      ),
                    const AndroidApplication(
                      packageName: 'com.android.systemui',
                      label: 'System UI',
                      isSystemApp: true,
                    ),
                  ],
                  onLaunch: (_) {},
                  onRefresh: () {},
                ),
              ),
              const LinkRailTrace(
                telemetry: DeviceTelemetry(
                  linkLatency: TelemetryMeasurement(
                    value: 24,
                    unit: TelemetryUnit.milliseconds,
                  ),
                  throughput: TelemetryMeasurement(
                    value: 1887436,
                    unit: TelemetryUnit.bytesPerSecond,
                  ),
                  framesPerSecond: TelemetryMeasurement(
                    value: 60,
                    unit: TelemetryUnit.framesPerSecond,
                  ),
                ),
              ),
            ],
          ),
          theme,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byType(AppDrawer),
        matchesGoldenFile('goldens/apps_$mode.png'),
      );
    });

    testWidgets('permissions, mixed grants, $mode', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 860));
      await tester.pumpWidget(
        _harness(
          PermissionPanel(
            permissions: const PermissionState(
              status: LoadStatus.ready,
              grants: <String, PermissionGrant>{
                'notifications': PermissionGrant.granted,
                'media': PermissionGrant.denied,
                'audio': PermissionGrant.requiresSettings,
                'clipboard': PermissionGrant.granted,
                'calls': PermissionGrant.unavailable,
              },
            ),
            onGrant: (_) {},
            onOpenSettings: (_) => () {},
          ),
          theme,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byType(PermissionPanel),
        matchesGoldenFile('goldens/permissions_$mode.png'),
      );
    });

    testWidgets('phones, mixed states, $mode', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await tester.pumpWidget(
        _harness(
          Center(
            child: PhoneList(
              status: LoadStatus.ready,
              devices: const <DeviceSummary>[
                DeviceSummary(
                  id: 'demo-usb-phone',
                  name: 'Redmi Note 7 Pro',
                  connectionKind: DeviceConnectionKind.usb,
                  status: DeviceStatus.authorized,
                  androidVersion: '13',
                ),
                DeviceSummary(
                  id: '192.0.2.42:5555',
                  name: 'Pixel 7a',
                  connectionKind: DeviceConnectionKind.wifi,
                  status: DeviceStatus.unauthorized,
                  androidVersion: '14',
                ),
                DeviceSummary(
                  id: 'demo-offline-phone',
                  name: 'Galaxy S21',
                  connectionKind: DeviceConnectionKind.usb,
                  status: DeviceStatus.offline,
                ),
              ],
              selectedId: 'demo-usb-phone',
              onSelect: (_) {},
              onRefresh: () {},
              onConnect: () {},
              onDisconnect: (_) {},
            ),
          ),
          theme,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byType(PhoneList),
        matchesGoldenFile('goldens/phones_$mode.png'),
      );
    });

    testWidgets('recovery, failed, $mode', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 620));
      await tester.pumpWidget(
        _harness(
          RecoveryOverlay(
            recovery: const RecoveryState(
              phase: RecoveryPhase.failed,
              attempt: 3,
              message: 'The phone stopped answering',
              error: OpenDexError(
                code: OpenDexErrorCode.connectionFailed,
                message: 'The cable was unplugged or the phone went to sleep.',
                retryable: true,
              ),
            ),
            onReconnect: () {},
            onDisconnect: () {},
          ),
          theme,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byType(RecoveryOverlay),
        matchesGoldenFile('goldens/recovery_failed_$mode.png'),
      );
    });
  }
}

void _ignore(String _) {}

void _ignoreVoid() {}
