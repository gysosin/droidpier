import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import '../apps/app_drawer.dart';
import '../boot/first_run_tour.dart';
import '../design/token_sheet.dart';
import '../desk/control_center.dart';
import '../desk/notification_center.dart';
import '../desk/phone_mirror.dart';
import '../diagnostics/health_hud.dart';
import '../diagnostics/stream_diagnostics.dart';
import '../settings/desk_settings.dart';
import '../shell/command_palette.dart';
import '../shell/commands.dart';
import '../shell/shortcut_sheet.dart';
import '../shell/shortcuts.dart';
import '../workspace/window_model.dart';
import '../workspace/window_switcher.dart';
import '../boot/boot_screen.dart';
import '../connect/connection_screen.dart';
import '../permissions/permission_panel.dart';
import '../recovery/recovery_overlay.dart';
import '../shell/app_shell.dart';
import '../widgets/link_rail.dart';
import '../companion/companion_view.dart';
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

  /// The shell's own overlay geometry, so a surface reviewed here is the size
  /// it will be in the product rather than stretched to the window.
  Widget _centred(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
      child: Padding(padding: const EdgeInsets.all(DexSpace.xxl), child: child),
    ),
  );

  /// Enough of the shell's hooks to render the shortcut sheet, which builds
  /// itself from the accelerator registry rather than from its own strings.
  ShellShortcutHooks get _previewHooks => ShellShortcutHooks(
    openPalette: () {},
    isPaletteOpen: () => false,
    closePalette: () {},
    openSheet: () {},
    isSheetOpen: () => false,
    closeSheet: () {},
    keyboardIsFree: () => true,
    toggleDiagnostics: () {},
    toggleHealthHud: () {},
    toggleDrawer: () {},
    toggleFullscreen: () {},
    cycleFocus: () {},
    cycleFocusBack: () {},
    isFullscreen: () => false,
    exitFullscreen: () {},
    isDiagnosticsOpen: () => false,
    closeDiagnostics: () {},
    isSwitcherOpen: () => false,
    cancelSwitch: () {},
    isDeskSurfaceOpen: () => false,
    closeDeskSurfaces: () {},
    isConnectOpen: () => false,
    closeConnect: () {},
    previousWorkspace: () => _stepWorkspace(-1),
    nextWorkspace: () => _stepWorkspace(1),
  );

  void _stepWorkspace(int delta) {
    final int index = _facade.snapshot.currentWorkspace - 1 + delta;
    final int next =
        ((index % kWorkspaceCount) + kWorkspaceCount) % kWorkspaceCount + 1;
    _facade.selectWorkspace(next);
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
      case _Surface.settings:
        return _centred(
          DeskSettings(
            snapEnabled: true,
            onSnapChanged: (bool _) {},
            themeMode: _mode,
            onThemeChanged: (ThemeMode m) => setState(() => _mode = m),
            wallpaperIndex: 0,
            onWallpaperChanged: (int _) {},
            onDisconnect: () => _select(MockScenario.disconnected),
            onOpenPermissions: () =>
                setState(() => _surface = _Surface.permissions),
            deviceLabel: state.selectedDevice?.name,
          ),
        );
      case _Surface.palette:
        return _centred(
          CommandPalette(
            commands: buildCommands(
              applications: state.applications,
              windows: state.windows,
              shellEntries: const <DexCommandEntry>[],
              onLaunchApplication: _facade.launchApplication,
              onFocusWindow: _facade.focusWindow,
            ),
            onDismiss: () {},
          ),
        );
      case _Surface.shortcuts:
        return _centred(
          ShortcutSheet(
            shortcuts: buildShortcuts(_previewHooks),
            onClose: () {},
          ),
        );
      case _Surface.diagnostics:
        return StreamDiagnostics(
          snapshot: state,
          recentExits: const <String>[
            '22:14  Camera — stopped unexpectedly',
            '21:58  Maps — closed',
          ],
          onClose: () {},
        );
      case _Surface.health:
        return Center(
          child: HealthHud(
            framesPerSecond: state.telemetry.framesPerSecond?.value,
            latency: state.telemetry.linkLatency,
            throughput: state.telemetry.throughput,
            windowLabel: state.windows.firstOrNull?.application.label,
          ),
        );
      case _Surface.notifications:
        return NotificationCenter(
          notifications: state.notifications,
          applications: state.applications,
          status: state.notificationStatus,
          now: DateTime.now(),
          onDismiss: (String id) async => _facade.dismissNotification(id),
          onActivate: (String id) async => _facade.activateNotification(id),
          onDismissAll: () async => _facade.dismissAllNotifications(),
          onClose: () {},
          onOpenPermissions: () =>
              setState(() => _surface = _Surface.permissions),
        );
      case _Surface.controls:
        return ControlCenter(
          telemetry: state.telemetry,
          clipboard: state.clipboard,
          agentStatus: state.agentStatus,
          onToggleControl: (DeviceControl c, bool on) =>
              _facade.setDeviceControl(c, on),
          onSetVolume: (String stream, int v) => _facade.setVolume(stream, v),
          onToggleClipboardSync: (bool on) => _facade.setClipboardSync(on),
          onOpenSettings: () => setState(() => _surface = _Surface.settings),
        );
      case _Surface.switcher:
        return WindowSwitcher(
          windows: const <WorkspaceWindow>[],
          selected: 0,
          onPick: (String _) {},
          onDismiss: () {},
        );
      case _Surface.tour:
        return FirstRunTour(onFinished: () {});
      case _Surface.mirror:
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(DexSpace.xl),
            child: PhoneMirror(
              snapshot: state,
              now: DateTime.now(),
              onClose: () {},
              onLaunch: (AndroidApplication a) =>
                  _facade.launchApplication(a.packageName),
              onRetry: () => _facade.startDisplayMirror(),
            ),
          ),
        );
      case _Surface.tokens:
        return _centred(TokenSheet(onClose: () {}));
      case _Surface.companion:
        return _centred(
          CompanionView(
            snapshot: state,
            onClose: () => setState(() => _surface = _Surface.desktop),
          ),
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
              // Every surface gets a Material, the way AppShell gives itself
              // one. Without it anything reaching for ink — a text field, a
              // ChoiceChip, an InkWell — throws the moment it is selected,
              // which is exactly the class of breakage a harness exists to
              // catch rather than to have.
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: _surfaceFor(state),
                ),
              ),
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
                    mode == ThemeMode.dark
                        ? DexIcons.lightMode
                        : DexIcons.darkMode,
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
/// Every surface the harness can put on screen.
///
/// It used to name six of roughly eighteen. Settings, the palette, the
/// shortcut sheet, diagnostics, the health readout, the notification and
/// control centres, the switcher, the tour, the mirror and the token sheet
/// could not be reviewed here at all — which is the same argument this file
/// already made for having a switcher, applied to the twelve it left out.
enum _Surface {
  desktop,
  boot,
  connect,
  apps,
  permissions,
  recovery,
  settings,
  palette,
  shortcuts,
  diagnostics,
  health,
  notifications,
  controls,
  switcher,
  tour,
  mirror,
  tokens,
  companion,
}
