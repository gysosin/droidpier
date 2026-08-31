import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import '../apps/app_drawer.dart';
import '../boot/boot_screen.dart';
import '../connect/connection_screen.dart';
import '../permissions/permission_panel.dart';
import '../recovery/recovery_overlay.dart';
import '../shell/app_shell.dart';
import '../widgets/link_rail.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// UI-owned preview harness.
///
/// Runs the UI against [MockOpenDexFacade] with a scenario switcher, so design
/// work can be reviewed without a device and without touching the real
/// bootstrap in `lib/main.dart` (backend-owned).
///
/// Run with:
///   flutter run -d linux -t lib/ui/preview/preview_app.dart
void main() => runApp(const PreviewApp());

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final MockOpenDexFacade _facade = MockOpenDexFacade(
    scenario: MockScenario.disconnected,
  );
  MockScenario _scenario = MockScenario.disconnected;
  ThemeMode _mode = ThemeMode.dark;
  _Surface _surface = _Surface.desktop;
  String? _selectedDeviceId;

  @override
  void dispose() {
    _facade.dispose();
    super.dispose();
  }

  void _select(MockScenario scenario) {
    setState(() => _scenario = scenario);
    _facade.showScenario(scenario);
  }

  Widget _surfaceFor(OpenDexSnapshot state) {
    switch (_surface) {
      case _Surface.desktop:
        // The whole product, exactly as the bootstrap will show it.
        return AppShell(snapshot: state, facade: _facade, now: DateTime.now());
      case _Surface.boot:
        return BootScreen(
          boot: state.boot,
          onConnect: () => _select(MockScenario.ready),
          onRetry: () => _select(MockScenario.recovering),
        );
      case _Surface.connect:
        return Center(
          child: ConnectionScreen.forFacade(
            facade: _facade,
            snapshot: state,
            selectedId: _selectedDeviceId ?? state.selectedDevice?.id,
            onSelect: (String id) => setState(() => _selectedDeviceId = id),
            onRefreshDevices: () => _facade.discoverDevices(),
            onConnectSelected: () => _select(MockScenario.ready),
            onClose: () => setState(() => _surface = _Surface.desktop),
          ),
        );
      case _Surface.apps:
        return Column(
          children: <Widget>[
            Expanded(
              child: AppDrawer(
                onDismiss: () {},
                status: state.applicationStatus,
                applications: state.applications,
                onLaunch: (String pkg) => _facade.launchApplication(pkg),
                onRefresh: () => _facade.discoverDevices(),
              ),
            ),
            // The rail's third state: collapsed to a live trace.
            LinkRailTrace(
              telemetry: state.telemetry,
              live: state.recovery.phase != RecoveryPhase.failed,
            ),
          ],
        );
      case _Surface.permissions:
        return PermissionPanel(
          permissions: state.permissions,
          onGrant: (String id) => _select(MockScenario.permissionRequired),
          onOpenSettings: (String id) =>
              () => _select(MockScenario.ready),
        );
      case _Surface.recovery:
        return RecoveryOverlay(
          recovery: state.recovery,
          onReconnect: () => _select(MockScenario.recovering),
          onDisconnect: () => _select(MockScenario.disconnected),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DroidPier — UI preview',
      debugShowCheckedModeBanner: false,
      theme: DexTheme.light(),
      darkTheme: DexTheme.dark(),
      themeMode: _mode,
      home: StreamBuilder<OpenDexSnapshot>(
        stream: _facade.states,
        initialData: _facade.snapshot,
        builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> snap) {
          final OpenDexSnapshot state = snap.data ?? _facade.snapshot;
          return Column(
            children: <Widget>[
              _PreviewBar(
                scenario: _scenario,
                mode: _mode,
                surface: _surface,
                onSurface: (_Surface s) => setState(() => _surface = s),
                onScenario: _select,
                onToggleMode: () => setState(() {
                  _mode = _mode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                }),
              ),
              Expanded(child: _surfaceFor(state)),
            ],
          );
        },
      ),
    );
  }
}

/// Harness chrome. Not part of the product UI.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({
    required this.scenario,
    required this.mode,
    required this.surface,
    required this.onSurface,
    required this.onScenario,
    required this.onToggleMode,
  });

  final MockScenario scenario;
  final ThemeMode mode;
  final _Surface surface;
  final ValueChanged<_Surface> onSurface;
  final ValueChanged<MockScenario> onScenario;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    // Material ancestor: this bar sits above the Scaffold, so nothing else
    // provides one, and Material widgets such as ChoiceChip require it.
    return Material(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DexSpace.lg,
          vertical: DexSpace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Without this row four surfaces — boot, apps, permissions and
            // recovery — are rendered by [_surfaceFor] with nothing able to
            // open them. A screen nobody can reach is a screen nobody reviews.
            Row(
              children: <Widget>[
                Text('surface', style: DexTheme.data(c, size: 11)),
                const SizedBox(width: DexSpace.md),
                Expanded(
                  child: Wrap(
                    spacing: DexSpace.sm,
                    children: <Widget>[
                      for (final _Surface s in _Surface.values)
                        ChoiceChip(
                          label: Text(s.name),
                          selected: s == surface,
                          onSelected: (_) => onSurface(s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DexSpace.sm),
            Row(
              children: <Widget>[
                Text('scenario', style: DexTheme.data(c, size: 11)),
                const SizedBox(width: DexSpace.md),
                Expanded(
                  child: Wrap(
                    spacing: DexSpace.sm,
                    children: <Widget>[
                      for (final MockScenario s in MockScenario.values)
                        ChoiceChip(
                          label: Text(s.name),
                          selected: s == scenario,
                          onSelected: (_) => onScenario(s),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onToggleMode,
                  tooltip: 'Toggle light and dark',
                  icon: Icon(
                    mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Which product surface the harness is showing.
enum _Surface { desktop, boot, connect, apps, permissions, recovery }
