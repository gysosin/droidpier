import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import 'bootstrap/desk_preferences.dart';
import 'bootstrap/desktop_clipboard_coordinator.dart';
import 'bootstrap/facade_factory.dart';
import 'bootstrap/host_shutdown.dart';
import 'bootstrap/reporting_facade.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/dex_theme.dart';

void main() {
  final facade = createFacade();
  installHostShutdownHandler(facade.dispose);
  runApp(OpenDexApplication(facade: facade));
}

class OpenDexApplication extends StatefulWidget {
  const OpenDexApplication({required this.facade, super.key});

  final OpenDexFacade facade;

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

  final DeskPreferences _preferences = DeskPreferences();

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
    unawaited(_preferences.save(next));
  }

  void _showError(OpenDexError error) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
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
      theme: DexTheme.light(),
      darkTheme: DexTheme.dark(),
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
            ),
          );
        },
      ),
    );
  }
}
