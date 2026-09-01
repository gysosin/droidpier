import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/desk_preferences.dart';
import 'package:open_android_dex/bootstrap/reporting_facade.dart';
import 'package:open_android_dex/main.dart';
import 'package:open_android_dex/ui/apps/app_ranking.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_geometry_store.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

void main() {
  testWidgets('bootstrap injects the facade and auto-connects one phone', (
    tester,
  ) async {
    final facade = MockOpenDexFacade(scenario: MockScenario.disconnected);

    await tester.pumpWidget(OpenDexApplication(facade: facade));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('Your apps'), findsOneWidget);
    expect(find.text('Connect phone'), findsNothing);
    expect(facade.snapshot.boot.phase, BootPhase.ready);

    // Let the connected desk's bounded entrance stagger finish, then dispose
    // its production clock before the test binding checks for pending timers.
    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('bootstrap maps persisted shell state in both directions', (
    tester,
  ) async {
    final preferences = _ControlledDeskPreferences(
      const DeskPreferencesData(
        launchHistory: <String, LaunchRecord>{
          'com.example.notes': LaunchRecord(
            count: 4,
            lastLaunchedMs: 1788256200000,
          ),
        },
        pinnedPackages: <String>['com.example.notes'],
        windowGeometry: <String, StoredWindowGeometry>{
          'com.example.notes': StoredWindowGeometry(
            x: 12,
            y: 24,
            width: 900,
            height: 640,
            maximised: true,
          ),
        },
      ),
    );
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);

    await tester.pumpWidget(
      OpenDexApplication(facade: facade, preferences: preferences),
    );
    await tester.pump();

    AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
    expect(shell.launchHistory['com.example.notes']?.count, 4);
    expect(
      shell.launchHistory['com.example.notes']?.lastLaunchedMs,
      1788256200000,
    );
    expect(shell.pinnedPackages, <String>['com.example.notes']);
    final RememberedWindow remembered =
        shell.rememberedWindows['com.example.notes']!;
    expect(remembered.geometry.x, 12);
    expect(remembered.geometry.y, 24);
    expect(remembered.geometry.width, 900);
    expect(remembered.geometry.height, 640);
    expect(remembered.maximised, true);

    shell.onLaunchHistoryChanged(const <String, AppLaunchStats>{
      'com.example.mail': AppLaunchStats(
        count: 2,
        lastLaunchedMs: 1788256300000,
      ),
    });
    shell.onPinnedChanged(const <String>['com.example.mail']);
    shell.onRememberedWindowsChanged(const <String, RememberedWindow>{
      'com.example.mail': RememberedWindow(
        geometry: WindowGeometry(x: 30, y: 40, width: 700, height: 500),
        maximised: false,
      ),
    });
    await tester.pump();

    expect(preferences.activeSaves, 1);
    expect(preferences.maxConcurrentSaves, 1);
    expect(preferences.startedSaves, hasLength(1));

    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.activeSaves, 1);
    expect(preferences.maxConcurrentSaves, 1);
    expect(preferences.startedSaves, hasLength(2));

    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.activeSaves, 1);
    expect(preferences.maxConcurrentSaves, 1);
    expect(preferences.startedSaves, hasLength(3));

    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.activeSaves, 0);

    expect(preferences.data.launchHistory['com.example.mail']?.count, 2);
    expect(
      preferences.data.launchHistory['com.example.mail']?.lastLaunchedMs,
      1788256300000,
    );
    expect(preferences.data.pinnedPackages, <String>['com.example.mail']);
    final StoredWindowGeometry stored =
        preferences.data.windowGeometry['com.example.mail']!;
    expect(stored.x, 30);
    expect(stored.y, 40);
    expect(stored.width, 700);
    expect(stored.height, 500);
    expect(stored.maximised, false);

    shell = tester.widget<AppShell>(find.byType(AppShell));
    expect(shell.launchHistory['com.example.mail']?.count, 2);
    expect(
      shell.launchHistory['com.example.mail']?.lastLaunchedMs,
      1788256300000,
    );
    expect(shell.pinnedPackages, <String>['com.example.mail']);
    final RememberedWindow rebuilt =
        shell.rememberedWindows['com.example.mail']!;
    expect(rebuilt.geometry.x, 30);
    expect(rebuilt.geometry.y, 40);
    expect(rebuilt.geometry.width, 700);
    expect(rebuilt.geometry.height, 500);
    expect(rebuilt.maximised, false);

    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('bootstrap restores and persists appearance preferences', (
    tester,
  ) async {
    final preferences = _ControlledDeskPreferences(
      const DeskPreferencesData(
        accentIndex: 3,
        glassEnabled: false,
        reduceMotion: true,
      ),
    );
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);

    await tester.pumpWidget(
      OpenDexApplication(facade: facade, preferences: preferences),
    );
    await tester.pump();

    MaterialApp application = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(
      application.theme?.colorScheme.primary,
      DexTheme.light(accentIndex: 3).colorScheme.primary,
    );
    expect(
      application.darkTheme?.colorScheme.primary,
      DexTheme.dark(accentIndex: 3).colorScheme.primary,
    );

    AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
    expect(shell.accentIndex, 3);
    expect(shell.glassEnabled, false);
    expect(shell.reduceMotion, true);
    shell.onAccentChanged(4);
    shell.onGlassChanged(true);
    shell.onReduceMotionChanged(false);
    await tester.pump();

    expect(preferences.startedSaves, hasLength(1));
    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.startedSaves, hasLength(2));
    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.startedSaves, hasLength(3));
    preferences.completeNextSave();
    await tester.pump();
    expect(preferences.data.accentIndex, 4);
    expect(preferences.data.glassEnabled, true);
    expect(preferences.data.reduceMotion, false);

    application = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      application.theme?.colorScheme.primary,
      DexTheme.light(accentIndex: 4).colorScheme.primary,
    );
    expect(
      application.darkTheme?.colorScheme.primary,
      DexTheme.dark(accentIndex: 4).colorScheme.primary,
    );
    shell = tester.widget<AppShell>(find.byType(AppShell));
    expect(shell.accentIndex, 4);
    expect(shell.glassEnabled, true);
    expect(shell.reduceMotion, false);

    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('bootstrap supplies a desktop clipboard writer', (tester) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      platformCalls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);

    await tester.pumpWidget(OpenDexApplication(facade: facade));
    await tester.pump();

    final AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
    expect(shell.onCopyText, isNotNull);
    shell.onCopyText!('### synthetic diagnostics');
    await tester.pump();

    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having(
              (MethodCall call) => call.method,
              'method',
              'Clipboard.setData',
            )
            .having(
              (MethodCall call) => call.arguments,
              'arguments',
              <String, String>{'text': '### synthetic diagnostics'},
            ),
      ),
    );

    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('clipboard write failure is reported in the shell', (
    tester,
  ) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'synthetic-copy-failure');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final facade = MockOpenDexFacade(scenario: MockScenario.ready);

    await tester.pumpWidget(OpenDexApplication(facade: facade));
    await tester.pump();

    final AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
    shell.onCopyText!('### synthetic diagnostics');
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Could not copy diagnostics to the desktop clipboard.'),
      findsOneWidget,
    );

    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('reporting facade publishes typed command failures', () async {
    final errors = <OpenDexError>[];
    final facade = ReportingOpenDexFacade(
      delegate: MockOpenDexFacade(scenario: MockScenario.ready),
      onError: errors.add,
    );
    addTearDown(facade.dispose);

    final result = await facade.focusWindow('missing-window');

    expect(result, isA<CommandFailure<void>>());
    expect(errors, hasLength(1));
    expect(errors.single.message, 'That application window has closed.');
  });
}

class _ControlledDeskPreferences extends DeskPreferences {
  _ControlledDeskPreferences(this.data);

  DeskPreferencesData data;
  final List<DeskPreferencesData> startedSaves = <DeskPreferencesData>[];
  final List<Completer<void>> _pendingSaves = <Completer<void>>[];
  int activeSaves = 0;
  int maxConcurrentSaves = 0;

  @override
  Future<DeskPreferencesData> load() async => data;

  @override
  Future<void> save(DeskPreferencesData next) async {
    startedSaves.add(next);
    activeSaves += 1;
    if (activeSaves > maxConcurrentSaves) {
      maxConcurrentSaves = activeSaves;
    }
    final Completer<void> completion = Completer<void>();
    _pendingSaves.add(completion);
    await completion.future;
    data = next;
    activeSaves -= 1;
  }

  void completeNextSave() => _pendingSaves.removeAt(0).complete();
}
