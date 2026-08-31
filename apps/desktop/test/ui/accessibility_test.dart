import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/desk/control_center.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_android_dex/ui/devices/device_selection_dialog.dart';
import 'package:open_android_dex/ui/permissions/permission_panel.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Accessibility and keyboard behaviour.
///
/// These are the checks the UI's accessibility bar commits to: every control
/// reachable and named, tap targets at least 24 px however small they draw,
/// and text that clears contrast. They run against both themes, because light
/// mode is a first-class surface rather than an afterthought.
AndroidApplication _app(String label) => AndroidApplication(
  packageName: 'com.example.${label.toLowerCase()}',
  label: label,
);

Widget _wrap(Widget child, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(body: child),
);

Widget _drawer({ValueChanged<String>? onLaunch}) => AppDrawer(
  onDismiss: () {},
  status: LoadStatus.ready,
  applications: <AndroidApplication>[
    _app('Camera'),
    _app('Chrome'),
    _app('Spotify'),
    const AndroidApplication(
      packageName: 'com.android.systemui',
      label: 'System UI',
      isSystemApp: true,
    ),
  ],
  onLaunch: onLaunch ?? (_) {},
  onRefresh: () {},
);

/// Assert every tappable node clears the WCAG 2.2 pointer minimum of 24x24.
///
/// Flutter ships `androidTapTargetGuideline` at 48 dp, which is the right rule
/// for a phone and the wrong one for a desktop taskbar driven by a mouse. This
/// checks the standard that does apply, rather than skipping the check.
void expectMeetsPointerTargetSize(WidgetTester tester) {
  const double floor = 24;
  final List<String> violations = <String>[];

  void visit(SemanticsNode node) {
    final bool tappable = node.getSemanticsData().hasAction(
      SemanticsAction.tap,
    );
    if (tappable) {
      final Rect r = node.rect;
      if (r.width < floor || r.height < floor) {
        violations.add(
          '${node.label.isEmpty ? node.tooltip : node.label}: '
          '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}',
        );
      }
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  // The root pipeline owner delegates; the semantics owner lives on one of its
  // children, so walk down to find it rather than assuming a fixed depth.
  SemanticsNode? root;
  void findRoot(PipelineOwner owner) {
    root ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(findRoot);
  }

  findRoot(tester.binding.rootPipelineOwner);
  expect(root, isNotNull, reason: 'semantics must be enabled for this check');
  visit(root!);
  expect(
    violations,
    isEmpty,
    reason:
        'tap targets below ${floor}x$floor (WCAG 2.2 SC 2.5.8): '
        '${violations.join(', ')}',
  );
}

void main() {
  group('agent awareness', _agentAwarenessTests);

  group('app drawer keyboard behaviour', () {
    testWidgets('search holds focus when the drawer opens', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_drawer(), DexTheme.dark()));
      await tester.pump();

      final EditableText field = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(
        field.focusNode.hasFocus,
        isTrue,
        reason: 'the drawer must open ready to type',
      );
    });

    testWidgets('typing filters the grid', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(_drawer(), DexTheme.dark()));
      await tester.pump();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'spot');
      await tester.pump();

      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Camera'), findsNothing);
    });

    testWidgets('Enter launches the first match', (WidgetTester tester) async {
      String? launched;
      await tester.pumpWidget(
        _wrap(_drawer(onLaunch: (String p) => launched = p), DexTheme.dark()),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'chr');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(launched, 'com.example.chrome');
    });

    testWidgets('system apps sit in their own section, with no toggle', (
      WidgetTester tester,
    ) async {
      // The launcher splits apps into System and User sections, as the
      // reference does — no toggle cluttering the overview.
      await tester.pumpWidget(_wrap(_drawer(), DexTheme.dark()));
      await tester.pump();

      expect(find.text('SYSTEM APPS'), findsOneWidget);
      expect(find.text('USER APPS'), findsOneWidget);
      expect(find.text('System UI'), findsOneWidget);
      expect(find.text('Show system apps'), findsNothing);
    });

    testWidgets('an empty search offers a way out', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_drawer(), DexTheme.dark()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();

      // No dead ends: the empty state carries the action that resolves it.
      expect(find.text('Clear search'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      await tester.pump();
      expect(find.text('Camera'), findsOneWidget);
    });
  });

  group('device selection', () {
    testWidgets('connect stays disabled until an authorized device is chosen', (
      WidgetTester tester,
    ) async {
      Widget dialog(String? selected) => _wrap(
        DeviceSelectionDialog(
          status: LoadStatus.ready,
          devices: const <DeviceSummary>[
            DeviceSummary(
              id: 'authorized-1',
              name: 'Redmi Note 7 Pro',
              connectionKind: DeviceConnectionKind.usb,
              status: DeviceStatus.authorized,
            ),
            DeviceSummary(
              id: 'unauthorized-1',
              name: 'Pixel 7a',
              connectionKind: DeviceConnectionKind.usb,
              status: DeviceStatus.unauthorized,
            ),
          ],
          selectedId: selected,
          onSelect: (_) {},
          onRefresh: () {},
          onConnect: () {},
        ),
        DexTheme.dark(),
      );

      await tester.pumpWidget(dialog(null));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'nothing selected',
      );

      await tester.pumpWidget(dialog('unauthorized-1'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'an unauthorized device cannot be connected',
      );

      await tester.pumpWidget(dialog('authorized-1'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });
  });

  group('permissions without a backend command', () {
    testWidgets('offers guidance rather than a button that does nothing', (
      WidgetTester tester,
    ) async {
      // The product path: OpenDexFacade has no permission command yet, so the
      // shell passes no handlers. A control that does nothing when pressed is
      // worse than no control.
      await tester.pumpWidget(
        _wrap(
          const PermissionPanel(
            permissions: PermissionState(
              status: LoadStatus.ready,
              grants: <String, PermissionGrant>{
                'media': PermissionGrant.denied,
                'audio': PermissionGrant.requiresSettings,
              },
            ),
          ),
          DexTheme.dark(),
        ),
      );
      await tester.pump();

      expect(find.text('Turn on'), findsNothing);
      expect(find.text('Open on phone'), findsNothing);
      expect(find.text('Turn on from the phone'), findsOneWidget);
      expect(find.text('Allow on the phone'), findsOneWidget);
    });
  });

  group('desktop surfaces', () {
    WorkspaceWindow wrap(WindowSessionState session) => WorkspaceWindow(
      session: session,
      geometry: const WindowGeometry(x: 0, y: 0, width: 400, height: 300),
      zOrder: 1,
    );

    Widget dock({Set<String> minimised = const <String>{}}) => TaskbarBar(
      minimised: minimised,
      windows: <WindowSessionState>[
        WindowSessionState(
          id: '1',
          application: _app('Maps'),
          status: WindowSessionStatus.streaming,
          isFocused: true,
        ),
        WindowSessionState(
          id: '2',
          application: _app('Camera'),
          status: WindowSessionStatus.failed,
        ),
      ].map(wrap).toList(),
      onOpenLauncher: () {},
      onFocus: (_) {},
      onClose: (_) {},
      trailing: const SizedBox.shrink(),
    );

    Widget controlCenter({
      DeviceControl? toggled,
      void Function(DeviceControl, bool)? onToggle,
    }) => ControlCenter(
      telemetry: const DeviceTelemetry(
        wifiEnabled: true,
        bluetoothEnabled: false,
        // Never reported: must not be pressable.
        torchEnabled: null,
        volume: <String, VolumeLevel>{
          'music': VolumeLevel(current: 7, maximum: 15),
        },
      ),
      clipboard: const ClipboardState(kind: ClipboardKind.text, text: 'copied'),
      onToggleControl: onToggle ?? (_, _) {},
      onToggleClipboardSync: (_) {},
      onSetVolume: (_, _) {},
    );

    testWidgets('dock names every window and its state', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(dock(), DexTheme.dark()));
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp('Focus Maps')), findsOneWidget);
      // A minimised window offers Restore, because focusing something not on
      // screen does nothing the person can see.
      await tester.pumpWidget(
        _wrap(dock(minimised: const <String>{'1'}), DexTheme.dark()),
      );
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Restore Maps')), findsOneWidget);
      // Closing a window is a long-press (right-click no longer closes), so the
      // spoken label has to say so — a screen reader user cannot discover a
      // tooltip.
      expect(
        find.bySemanticsLabel(RegExp('hold to close')),
        findsWidgets,
      );
      // A failed window says so to a screen reader, not only by colour.
      expect(
        find.bySemanticsLabel(RegExp('Focus Camera — failed')),
        findsOneWidget,
      );
      expectMeetsPointerTargetSize(tester);
      handle.dispose();
    });

    testWidgets('a capability the phone never reported cannot be toggled', (
      WidgetTester tester,
    ) async {
      final List<DeviceControl> toggled = <DeviceControl>[];
      await tester.pumpWidget(
        _wrap(
          controlCenter(onToggle: (DeviceControl c, bool _) => toggled.add(c)),
          DexTheme.dark(),
        ),
      );
      await tester.pump();

      // Wi-Fi was reported, so it responds.
      await tester.tap(find.text('Wi-Fi'));
      await tester.pump();
      expect(toggled, <DeviceControl>[DeviceControl.wifi]);

      // Torch was not. Pressing it must do nothing rather than send a command
      // the phone cannot honour.
      await tester.tap(find.text('Torch'));
      await tester.pump();
      expect(toggled, <DeviceControl>[DeviceControl.wifi]);
    });

    testWidgets('unavailable controls say why to a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(controlCenter(), DexTheme.dark()));
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp('Torch, not available on this phone')),
        findsOneWidget,
      );
      handle.dispose();
    });

    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('dark', DexTheme.dark()),
      ('light', DexTheme.light()),
    ]) {
      testWidgets('control centre clears contrast and targets ($name)', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpWidget(_wrap(controlCenter(), theme));
        await tester.pump();

        expectMeetsPointerTargetSize(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('accessibility guidelines', () {
    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('dark', DexTheme.dark()),
      ('light', DexTheme.light()),
    ]) {
      testWidgets('app drawer text clears contrast ($name)', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpWidget(_wrap(_drawer(), theme));
        await tester.pump();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}

void _agentAwarenessTests() {
  Widget host(AgentConnectionStatus status) => MaterialApp(
    theme: DexTheme.dark(),
    home: Scaffold(
      body: ControlCenter(
        telemetry: const DeviceTelemetry(
          wifiEnabled: true,
          bluetoothEnabled: true,
        ),
        clipboard: const ClipboardState(),
        agentStatus: status,
        onToggleControl: (_, _) {},
        onToggleClipboardSync: (_) {},
        onSetVolume: (_, _) {},
      ),
    ),
  );

  testWidgets('controls say why they are unavailable before they are pressed', (
    WidgetTester tester,
  ) async {
    // Pressing Bluetooth used to give "The Android command could not be
    // completed" — a failure reported after the fact, with no cause. When the
    // agent is down the person should be told first.
    await tester.pumpWidget(host(AgentConnectionStatus.unavailable));
    await tester.pump();
    expect(find.textContaining('not connected'), findsOneWidget);
  });

  testWidgets('a connected agent leaves the controls alone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(AgentConnectionStatus.connected));
    await tester.pump();
    expect(find.textContaining('not connected'), findsNothing);
  });

  testWidgets('reconnecting is distinguished from disconnected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(AgentConnectionStatus.reconnecting));
    await tester.pump();
    expect(find.textContaining('Reconnecting'), findsOneWidget);
  });
}
