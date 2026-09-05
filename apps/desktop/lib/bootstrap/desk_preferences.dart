import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

/// One window's remembered placement. Restored per package on relaunch.
class StoredWindowGeometry {
  const StoredWindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.maximised = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool maximised;

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'maximised': maximised,
  };

  /// Returns null rather than throwing on anything unexpected: one bad entry
  /// must cost that window its position, not the whole settings file.
  static StoredWindowGeometry? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? x = json['x'];
    final Object? y = json['y'];
    final Object? width = json['width'];
    final Object? height = json['height'];
    if (x is! num ||
        y is! num ||
        width is! num ||
        height is! num ||
        !x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return StoredWindowGeometry(
      x: x.toDouble(),
      y: y.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      maximised: json['maximised'] == true,
    );
  }
}

/// How often and how recently one package was launched, for search ranking.
class LaunchRecord {
  const LaunchRecord({required this.count, required this.lastLaunchedMs});

  final int count;

  /// Milliseconds since epoch, UTC. Stored as an int so it round-trips through
  /// JSON without a date format to disagree about.
  final int lastLaunchedMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'count': count,
    'lastLaunchedMs': lastLaunchedMs,
  };

  static LaunchRecord? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? count = json['count'];
    final Object? lastLaunchedMs = json['lastLaunchedMs'];
    if (count is! int ||
        lastLaunchedMs is! int ||
        count < 0 ||
        lastLaunchedMs < 0) {
      return null;
    }
    return LaunchRecord(count: count, lastLaunchedMs: lastLaunchedMs);
  }
}

/// The desk settings that outlive a run.
///
/// Deliberately small and plain — it is serialised to a single JSON file, so
/// every field must round-trip through [toJson]/[fromJson].
class DeskPreferencesData {
  const DeskPreferencesData({
    this.themeMode = ThemeMode.dark,
    this.wallpaperIndex = 0,
    this.accentIndex = 0,
    this.glassEnabled = true,
    this.reduceMotion = false,
    this.tourCompleted = false,
    this.snapEnabled = true,
    this.windowGeometry = const <String, StoredWindowGeometry>{},
    this.pinnedPackages = const <String>[],
    this.launchHistory = const <String, LaunchRecord>{},
  });

  static const int maxRememberedWindows = 64;

  final ThemeMode themeMode;

  /// 0 is the theme default; 1..N select [kWallpaperChoices]. Kept as an int so
  /// a stored index that no longer exists degrades to the default rather than
  /// failing to parse.
  final int wallpaperIndex;

  /// Which accent tints links, focus rings and the selected row. 0 is the
  /// product's own blue, so an unset preference needs no special case.
  final int accentIndex;

  /// Whether panels frost what is behind them. Off is the low-end-GPU and
  /// legibility path.
  final bool glassEnabled;

  /// Whether to cut motion beyond whatever the platform already asks for.
  /// Can only ever reduce; see `DexMotion.enabled`.
  final bool reduceMotion;

  /// Whether the first-run tour has been seen through to the end.
  ///
  /// False on a fresh install, so the tour actually happens. It never did:
  /// the shell defaulted it to true and nothing persisted it, so 214 fully
  /// tested lines could not appear in the product.
  final bool tourCompleted;

  final bool snapEnabled;

  /// Remembered window placement by package name. Capped at
  /// [maxRememberedWindows] so a long-lived install does not grow the settings
  /// file without bound.
  final Map<String, StoredWindowGeometry> windowGeometry;

  /// Packages pinned to the top of the app drawer, in pin order.
  final List<String> pinnedPackages;

  /// Launch counts and recency by package name, for drawer search ranking.
  final Map<String, LaunchRecord> launchHistory;

  DeskPreferencesData copyWith({
    ThemeMode? themeMode,
    int? wallpaperIndex,
    int? accentIndex,
    bool? glassEnabled,
    bool? reduceMotion,
    bool? tourCompleted,
    bool? snapEnabled,
    Map<String, StoredWindowGeometry>? windowGeometry,
    List<String>? pinnedPackages,
    Map<String, LaunchRecord>? launchHistory,
  }) => DeskPreferencesData(
    themeMode: themeMode ?? this.themeMode,
    wallpaperIndex: wallpaperIndex ?? this.wallpaperIndex,
    accentIndex: accentIndex ?? this.accentIndex,
    glassEnabled: glassEnabled ?? this.glassEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    tourCompleted: tourCompleted ?? this.tourCompleted,
    snapEnabled: snapEnabled ?? this.snapEnabled,
    windowGeometry: windowGeometry ?? this.windowGeometry,
    pinnedPackages: pinnedPackages ?? this.pinnedPackages,
    launchHistory: launchHistory ?? this.launchHistory,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode.name,
    'wallpaperIndex': wallpaperIndex,
    'accentIndex': accentIndex,
    'glassEnabled': glassEnabled,
    'reduceMotion': reduceMotion,
    'tourCompleted': tourCompleted,
    'snapEnabled': snapEnabled,
    'windowGeometry': windowGeometry.map(
      (String packageName, StoredWindowGeometry geometry) =>
          MapEntry<String, Object?>(packageName, geometry.toJson()),
    ),
    'pinnedPackages': pinnedPackages,
    'launchHistory': launchHistory.map(
      (String packageName, LaunchRecord record) =>
          MapEntry<String, Object?>(packageName, record.toJson()),
    ),
  };

  /// Tolerant of anything: an unknown theme name, a wrong type, or a missing
  /// key all fall back to the default for that field. A settings file is not
  /// worth crashing the desk over.
  factory DeskPreferencesData.fromJson(Map<String, Object?> json) {
    ThemeMode mode = ThemeMode.dark;
    final Object? raw = json['themeMode'];
    if (raw is String) {
      mode = ThemeMode.values.firstWhere(
        (ThemeMode m) => m.name == raw,
        orElse: () => ThemeMode.dark,
      );
    }
    final Object? idx = json['wallpaperIndex'];
    final Object? accent = json['accentIndex'];
    final Object? glass = json['glassEnabled'];
    final Object? motion = json['reduceMotion'];
    final Object? tour = json['tourCompleted'];
    final Object? snap = json['snapEnabled'];

    // Each entry decodes independently: one malformed record is dropped rather
    // than costing the user every remembered window.
    final Map<String, StoredWindowGeometry> geometry =
        <String, StoredWindowGeometry>{};
    final Object? rawGeometry = json['windowGeometry'];
    if (rawGeometry is Map<String, Object?>) {
      for (final MapEntry<String, Object?> entry in rawGeometry.entries) {
        final StoredWindowGeometry? decoded = StoredWindowGeometry.fromJson(
          entry.value,
        );
        if (decoded != null) geometry[entry.key] = decoded;
      }
    }

    final List<String> pinned = <String>[];
    final Set<String> seenPinned = <String>{};
    final Object? rawPinned = json['pinnedPackages'];
    if (rawPinned is List) {
      for (final Object? entry in rawPinned) {
        if (entry is String && entry.isNotEmpty && seenPinned.add(entry)) {
          pinned.add(entry);
        }
      }
    }

    final Map<String, LaunchRecord> history = <String, LaunchRecord>{};
    final Object? rawHistory = json['launchHistory'];
    if (rawHistory is Map<String, Object?>) {
      for (final MapEntry<String, Object?> entry in rawHistory.entries) {
        final LaunchRecord? decoded = LaunchRecord.fromJson(entry.value);
        if (decoded != null) history[entry.key] = decoded;
      }
    }

    return DeskPreferencesData(
      themeMode: mode,
      wallpaperIndex: idx is int && idx >= 0 ? idx : 0,
      accentIndex: accent is int && accent >= 0 ? accent : 0,
      glassEnabled: glass is bool ? glass : true,
      reduceMotion: motion is bool ? motion : false,
      // Anything unreadable shows the tour again. Once too often is
      // recoverable; never is the failure this replaces.
      tourCompleted: tour is bool ? tour : false,
      snapEnabled: snap is bool ? snap : true,
      windowGeometry: geometry,
      pinnedPackages: pinned,
      launchHistory: history,
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
