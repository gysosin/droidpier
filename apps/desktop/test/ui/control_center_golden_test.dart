@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/desk/control_center.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

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
  for (final entry in <String, List<String>>{
    'Lucide': ['assets/icons/lucide.ttf'],
    'InstrumentSans': ['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': ['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': ['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('control panel, restyled', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: ControlCenter(
              telemetry: DeviceTelemetry(
                batteryPercentage: 78,
                wifiEnabled: true,
                bluetoothEnabled: false,
                rotationLocked: true,
                volume: <String, VolumeLevel>{
                  'music': VolumeLevel(current: 9, maximum: 15),
                  'ring': VolumeLevel(current: 4, maximum: 7),
                },
              ),
              // The shipping default: the phone can share a clipboard, and
              // sharing is off until the person turns it on.
              clipboard: ClipboardState(
                kind: ClipboardKind.empty,
                availability: ClipboardAvailability.available,
              ),
              onToggleControl: _noop2,
              onToggleClipboardSync: _noop1,
              onSetVolume: _noop2i,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(ControlCenter),
      matchesGoldenFile('goldens/control_center_restyled.png'),
    );
  });
}

void _noop2(DeviceControl c, bool b) {}
void _noop1(bool b) {}
void _noop2i(String s, int i) {}
