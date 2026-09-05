import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/desk_preferences.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_dex_prefs_test');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('missing file loads defaults', () async {
    final DeskPreferences prefs = DeskPreferences(configDir: dir);
    final DeskPreferencesData data = await prefs.load();
    expect(data.themeMode, ThemeMode.dark);
    expect(data.wallpaperIndex, 0);
    expect(data.accentIndex, 0);
    expect(data.glassEnabled, true);
    expect(data.reduceMotion, false);
    expect(data.snapEnabled, true);
    expect(data.windowGeometry, isEmpty);
    expect(data.pinnedPackages, isEmpty);
    expect(data.launchHistory, isEmpty);
  });

  test('saved settings round-trip', () async {
    final DeskPreferences prefs = DeskPreferences(configDir: dir);
    await prefs.save(
      const DeskPreferencesData(
        themeMode: ThemeMode.light,
        wallpaperIndex: 3,
        accentIndex: 4,
        glassEnabled: false,
        reduceMotion: true,
        snapEnabled: false,
        windowGeometry: <String, StoredWindowGeometry>{
          'com.example.notes': StoredWindowGeometry(
            x: 12.5,
            y: 24,
            width: 900,
            height: 640,
            maximised: true,
          ),
        },
        pinnedPackages: <String>['com.example.notes', 'com.example.mail'],
        launchHistory: <String, LaunchRecord>{
          'com.example.notes': LaunchRecord(
            count: 7,
            lastLaunchedMs: 1788256200000,
          ),
        },
      ),
    );
    final DeskPreferencesData data = await DeskPreferences(configDir: dir)
        .load();
    expect(data.themeMode, ThemeMode.light);
    expect(data.wallpaperIndex, 3);
    expect(data.accentIndex, 4);
    expect(data.glassEnabled, false);
    expect(data.reduceMotion, true);
    expect(data.snapEnabled, false);
    final StoredWindowGeometry geometry =
        data.windowGeometry['com.example.notes']!;
    expect(geometry.x, 12.5);
    expect(geometry.y, 24);
    expect(geometry.width, 900);
    expect(geometry.height, 640);
    expect(geometry.maximised, true);
    expect(data.pinnedPackages, <String>[
      'com.example.notes',
      'com.example.mail',
    ]);
    final LaunchRecord launch = data.launchHistory['com.example.notes']!;
    expect(launch.count, 7);
    expect(launch.lastLaunchedMs, 1788256200000);
  });

  test('malformed records are dropped without losing valid siblings', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync('''
{
  "windowGeometry": {
    "com.example.valid": {
      "x": 1,
      "y": 2.5,
      "width": 800,
      "height": 600,
      "maximised": false
    },
    "com.example.invalid": {
      "x": 1,
      "y": 2,
      "width": 0,
      "height": 600
    },
    "com.example.infinite": {
      "x": 1,
      "y": 2,
      "width": 1e999,
      "height": 600
    }
  },
  "pinnedPackages": [
    "com.example.valid",
    42,
    "",
    "com.example.valid",
    "com.example.other"
  ],
  "launchHistory": {
    "com.example.valid": {"count": 3, "lastLaunchedMs": 1788256200000},
    "com.example.invalid": {"count": -1, "lastLaunchedMs": 0}
  }
}
''');

    final DeskPreferencesData data = await DeskPreferences(configDir: dir)
        .load();

    expect(data.windowGeometry.keys, <String>['com.example.valid']);
    expect(data.pinnedPackages, <String>[
      'com.example.valid',
      'com.example.other',
    ]);
    expect(data.launchHistory.keys, <String>['com.example.valid']);
  });

  test('missing persisted collection keys use empty defaults', () {
    final DeskPreferencesData data = DeskPreferencesData.fromJson(
      <String, Object?>{'themeMode': 'dark'},
    );

    expect(data.accentIndex, 0);
    expect(data.glassEnabled, true);
    expect(data.reduceMotion, false);
    expect(data.windowGeometry, isEmpty);
    expect(data.pinnedPackages, isEmpty);
    expect(data.launchHistory, isEmpty);
  });

  test('copyWith replaces persisted values', () {
    final DeskPreferencesData data = const DeskPreferencesData().copyWith(
      accentIndex: 5,
      glassEnabled: false,
      reduceMotion: true,
      windowGeometry: const <String, StoredWindowGeometry>{
        'com.example.app': StoredWindowGeometry(
          x: 10,
          y: 20,
          width: 640,
          height: 480,
        ),
      },
      pinnedPackages: const <String>['com.example.app'],
      launchHistory: const <String, LaunchRecord>{
        'com.example.app': LaunchRecord(count: 1, lastLaunchedMs: 1234),
      },
    );

    expect(data.accentIndex, 5);
    expect(data.glassEnabled, false);
    expect(data.reduceMotion, true);
    expect(data.windowGeometry.keys, <String>['com.example.app']);
    expect(data.pinnedPackages, <String>['com.example.app']);
    expect(data.launchHistory['com.example.app']?.count, 1);
  });

  test('a corrupt file falls back to defaults instead of throwing', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync('{ not json ]');
    final DeskPreferencesData data = await DeskPreferences(configDir: dir)
        .load();
    expect(data.themeMode, ThemeMode.dark);
    expect(data.wallpaperIndex, 0);
    expect(data.snapEnabled, true);
  });

  test('an unknown theme name degrades to the default', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync(
      '{"themeMode":"neon","wallpaperIndex":-2,"accentIndex":-1,'
      '"glassEnabled":"yes","reduceMotion":1,"snapEnabled":"yes"}',
    );
    final DeskPreferencesData data = await DeskPreferences(configDir: dir)
        .load();
    expect(data.themeMode, ThemeMode.dark);
    // Negative index and non-bool snap fall back too.
    expect(data.wallpaperIndex, 0);
    expect(data.accentIndex, 0);
    expect(data.glassEnabled, true);
    expect(data.reduceMotion, false);
    expect(data.snapEnabled, true);
  });
}
