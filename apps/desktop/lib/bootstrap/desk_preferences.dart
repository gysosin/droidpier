import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

/// The desk settings that outlive a run: theme, wallpaper and window snapping.
///
/// Deliberately small and plain — it is serialised to a single JSON file, so
/// every field must round-trip through [toJson]/[fromJson].
class DeskPreferencesData {
  const DeskPreferencesData({
    this.themeMode = ThemeMode.system,
    this.wallpaperIndex = 0,
    this.snapEnabled = true,
  });

  final ThemeMode themeMode;

  /// 0 is the theme default; 1..N select [kWallpaperChoices]. Kept as an int so
  /// a stored index that no longer exists degrades to the default rather than
  /// failing to parse.
  final int wallpaperIndex;

  final bool snapEnabled;

  DeskPreferencesData copyWith({
    ThemeMode? themeMode,
    int? wallpaperIndex,
    bool? snapEnabled,
  }) => DeskPreferencesData(
    themeMode: themeMode ?? this.themeMode,
    wallpaperIndex: wallpaperIndex ?? this.wallpaperIndex,
    snapEnabled: snapEnabled ?? this.snapEnabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode.name,
    'wallpaperIndex': wallpaperIndex,
    'snapEnabled': snapEnabled,
  };

  /// Tolerant of anything: an unknown theme name, a wrong type, or a missing
  /// key all fall back to the default for that field. A settings file is not
  /// worth crashing the desk over.
  factory DeskPreferencesData.fromJson(Map<String, Object?> json) {
    ThemeMode mode = ThemeMode.system;
    final Object? raw = json['themeMode'];
    if (raw is String) {
      mode = ThemeMode.values.firstWhere(
        (ThemeMode m) => m.name == raw,
        orElse: () => ThemeMode.system,
      );
    }
    final Object? idx = json['wallpaperIndex'];
    final Object? snap = json['snapEnabled'];
    return DeskPreferencesData(
      themeMode: mode,
      wallpaperIndex: idx is int && idx >= 0 ? idx : 0,
      snapEnabled: snap is bool ? snap : true,
    );
  }
}

/// Reads and writes [DeskPreferencesData] to a JSON file under the user's
/// config directory (`$XDG_CONFIG_HOME/open-android-dex/settings.json`, or
/// `~/.config/...`). All I/O is best-effort: a failure to read returns
/// defaults, a failure to write is swallowed — settings are a convenience, not
/// a thing worth an exception on the startup path.
class DeskPreferences {
  DeskPreferences({Directory? configDir})
    : _dir = configDir ?? _defaultConfigDir();

  final Directory _dir;

  File get _file => File('${_dir.path}/settings.json');

  static Directory _defaultConfigDir() {
    final String? xdg = Platform.environment['XDG_CONFIG_HOME'];
    final String base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : '${Platform.environment['HOME']}/.config';
    return Directory('$base/open-android-dex');
  }

  Future<DeskPreferencesData> load() async {
    try {
      if (!await _file.exists()) return const DeskPreferencesData();
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, Object?>) return const DeskPreferencesData();
      return DeskPreferencesData.fromJson(decoded);
    } catch (_) {
      return const DeskPreferencesData();
    }
  }

  Future<void> save(DeskPreferencesData data) async {
    try {
      await _dir.create(recursive: true);
      await _file.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {
      // Best effort: a read-only home must not take the desk down.
    }
  }
}
