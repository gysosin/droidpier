import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import 'bootstrap/desk_preferences.dart';
import 'bootstrap/desktop_clipboard_coordinator.dart';
import 'bootstrap/facade_factory.dart';
import 'bootstrap/host_shutdown.dart';
import 'bootstrap/reporting_facade.dart';
import 'ui/apps/app_ranking.dart' show AppLaunchStats;
import 'ui/shell/app_shell.dart';
import 'ui/theme/dex_theme.dart';
import 'ui/workspace/window_geometry_store.dart' show RememberedWindow;

void main() {
  final facade = createFacade();
  installHostShutdownHandler(facade.dispose);
  runApp(OpenDexApplication(facade: facade));
}

class OpenDexApplication extends StatefulWidget {
  const OpenDexApplication({required this.facade, this.preferences, super.key});

  final OpenDexFacade facade;
  final DeskPreferences? preferences;

  @override
  State<OpenDexApplication> createState() => _OpenDexApplicationState();
}

class _OpenDexApplicationState extends State<OpenDexApplication> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final OpenDexFacade _facade = ReportingOpenDexFacade(
    delegate: widget.facade,
    onError: _showError,
  );
  late final _clipboardCoordinator = DesktopClipboardCoordinator(
    facade: _facade,
  );

  late final DeskPreferences _preferences =
      widget.preferences ?? DeskPreferences();
  Future<void> _preferenceSaveTail = Future<void>.value();

  /// The persisted desk settings. Starts at defaults and is replaced once the
  /// settings file has loaded, so the first frame is never blocked on disk.
  DeskPreferencesData _prefs = const DeskPreferencesData();

  @override
  void initState() {
    super.initState();
    _clipboardCoordinator.start();
    unawaited(_loadPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_facade.discoverDevices());
    });
  }

  Future<void> _loadPreferences() async {
    final DeskPreferencesData loaded = await _preferences.load();
    if (!mounted) return;
    setState(() => _prefs = loaded);
  }

  void _updatePreferences(DeskPreferencesData next) {
    setState(() => _prefs = next);
    _preferenceSaveTail = _preferenceSaveTail.then(
      (_) => _preferences.save(next),
    );
    unawaited(_preferenceSaveTail);
  }

  void _showError(OpenDexError error) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  }

  Future<void> _copyText(String text) async {
    try {
      await _clipboardCoordinator.writeHostText(text);
    } on Object catch (error) {
      if (!mounted) return;
      _showError(
        OpenDexError(
          code: OpenDexErrorCode.internal,
          message: 'Could not copy diagnostics to the desktop clipboard.',
          technicalDetails: error.toString(),
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_disposeServices());
    super.dispose();
  }

  Future<void> _disposeServices() async {
    await _clipboardCoordinator.dispose();
    await _facade.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DroidPier',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: DexTheme.light(accentIndex: _prefs.accentIndex),
      darkTheme: DexTheme.dark(accentIndex: _prefs.accentIndex),
      themeMode: _prefs.themeMode,
      home: StreamBuilder<OpenDexSnapshot>(
        stream: _facade.states,
        initialData: _facade.snapshot,
        builder: (context, state) {
          final snapshot = state.data ?? _facade.snapshot;
          return Scaffold(
            body: AppShell(
              snapshot: snapshot,
              facade: _facade,
              themeMode: _prefs.themeMode,
              onThemeChanged: (ThemeMode m) =>
                  _updatePreferences(_prefs.copyWith(themeMode: m)),
              snapEnabled: _prefs.snapEnabled,
              onSnapChanged: (bool v) =>
                  _updatePreferences(_prefs.copyWith(snapEnabled: v)),
              wallpaperIndex: _prefs.wallpaperIndex,
              onWallpaperChanged: (int i) =>
                  _updatePreferences(_prefs.copyWith(wallpaperIndex: i)),
              accentIndex: _prefs.accentIndex,
              onAccentChanged: (int i) =>
                  _updatePreferences(_prefs.copyWith(accentIndex: i)),
              glassEnabled: _prefs.glassEnabled,
              onGlassChanged: (bool v) =>
                  _updatePreferences(_prefs.copyWith(glassEnabled: v)),
              reduceMotion: _prefs.reduceMotion,
              onReduceMotionChanged: (bool v) =>
                  _updatePreferences(_prefs.copyWith(reduceMotion: v)),
              onCopyText: (String text) => unawaited(_copyText(text)),
              launchHistory: <String, AppLaunchStats>{
                for (final MapEntry<String, LaunchRecord> entry
                    in _prefs.launchHistory.entries)
                  entry.key: AppLaunchStats(
                    count: entry.value.count,
                    lastLaunchedMs: entry.value.lastLaunchedMs,
                  ),
              },
              onLaunchHistoryChanged: (Map<String, AppLaunchStats> history) =>
                  _updatePreferences(
                    _prefs.copyWith(
                      launchHistory: <String, LaunchRecord>{
                        for (final MapEntry<String, AppLaunchStats> entry
                            in history.entries)
                          entry.key: LaunchRecord(
                            count: entry.value.count,
                            lastLaunchedMs: entry.value.lastLaunchedMs,
                          ),
                      },
                    ),
                  ),
              pinnedPackages: _prefs.pinnedPackages,
              onPinnedChanged: (List<String> packages) =>
                  _updatePreferences(_prefs.copyWith(pinnedPackages: packages)),
              rememberedWindows: <String, RememberedWindow>{
                for (final MapEntry<String, StoredWindowGeometry> entry
                    in _prefs.windowGeometry.entries)
                  entry.key: RememberedWindow(
                    geometry: WindowGeometry(
                      x: entry.value.x,
                      y: entry.value.y,
                      width: entry.value.width,
                      height: entry.value.height,
                    ),
                    maximised: entry.value.maximised,
                  ),
              },
              onRememberedWindowsChanged:
                  (Map<String, RememberedWindow> windows) => _updatePreferences(
                    _prefs.copyWith(
                      windowGeometry: <String, StoredWindowGeometry>{
                        for (final MapEntry<String, RememberedWindow> entry
                            in windows.entries)
                          entry.key: StoredWindowGeometry(
                            x: entry.value.geometry.x,
                            y: entry.value.geometry.y,
                            width: entry.value.geometry.width,
                            height: entry.value.geometry.height,
                            maximised: entry.value.maximised,
                          ),
                      },
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }
}
