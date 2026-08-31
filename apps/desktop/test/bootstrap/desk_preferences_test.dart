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
    expect(data.themeMode, ThemeMode.system);
    expect(data.wallpaperIndex, 0);
    expect(data.snapEnabled, true);
  });

  test('saved settings round-trip', () async {
    final DeskPreferences prefs = DeskPreferences(configDir: dir);
    await prefs.save(
      const DeskPreferencesData(
        themeMode: ThemeMode.light,
        wallpaperIndex: 3,
        snapEnabled: false,
      ),
    );
    final DeskPreferencesData data = await DeskPreferences(
      configDir: dir,
    ).load();
    expect(data.themeMode, ThemeMode.light);
    expect(data.wallpaperIndex, 3);
    expect(data.snapEnabled, false);
  });

  test('a corrupt file falls back to defaults instead of throwing', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync('{ not json ]');
    final DeskPreferencesData data = await DeskPreferences(
      configDir: dir,
    ).load();
    expect(data.themeMode, ThemeMode.system);
    expect(data.wallpaperIndex, 0);
    expect(data.snapEnabled, true);
  });

  test('an unknown theme name degrades to system', () async {
    dir.createSync(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync(
      '{"themeMode":"neon","wallpaperIndex":-2,"snapEnabled":"yes"}',
    );
    final DeskPreferencesData data = await DeskPreferences(
      configDir: dir,
    ).load();
    expect(data.themeMode, ThemeMode.system);
    // Negative index and non-bool snap fall back too.
    expect(data.wallpaperIndex, 0);
    expect(data.snapEnabled, true);
  });
}
