@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/diagnostics/health_hud.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

Future<void> _loadFonts() async {
  final String root =
      Platform.environment['FLUTTER_ROOT'] ??
      Directory('../../.tools/flutter').absolute.path;
  final File icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader l = FontLoader('MaterialIcons');
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await l.load();
  }
  const Map<String, List<String>> fam = <String, List<String>>{
    'InstrumentSans': <String>['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final MapEntry<String, List<String>> e in fam.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String p in e.value) {
      final File f = File(p);
      if (f.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

/// All three grades side by side, so the amber is checked against the green
/// and the red rather than admired on its own.
void main() {
  setUpAll(_loadFonts);

  Widget hud(double fps, double latency, String label) => HealthHud(
    framesPerSecond: fps,
    latency: TelemetryMeasurement(
      value: latency,
      unit: TelemetryUnit.milliseconds,
    ),
    throughput: const TelemetryMeasurement(
      value: 2400000,
      unit: TelemetryUnit.bytesPerSecond,
    ),
    windowLabel: label,
  );

  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', DexTheme.dark()),
    ('light', DexTheme.light()),
  ]) {
    testWidgets('health hud, all grades, $name', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(460, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DeskWallpaper(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    hud(58.4, 22, 'Maps'),
                    const SizedBox(height: 12),
                    hud(38, 90, 'Spotify'),
                    const SizedBox(height: 12),
                    hud(9, 220, 'YouTube'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(DeskWallpaper),
        matchesGoldenFile('goldens/health_hud_$name.png'),
      );
    });
  }
}
