import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';

/// The taskbar's composition.
///
/// Two things the dock was missing. The launcher was an unlabelled coloured
/// square, which is a guess rather than a control — the one button on the desk
/// that opens everything should say what it does. And there was nowhere to
/// switch virtual desktops, despite the window manager now carrying a
/// workspace per window.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    int currentWorkspace = 1,
    ValueChanged<int>? onSelectWorkspace,
    Size size = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TaskbarBar(
              windows: const <WorkspaceWindow>[],
              minimised: const <String>{},
              onOpenLauncher: () {},
              onFocus: (_) {},
              onClose: (_) {},
              currentWorkspace: currentWorkspace,
              onSelectWorkspace: onSelectWorkspace ?? (_) {},
              trailing: const SizedBox(width: 120, height: 44),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the launcher button says what it opens', (
    WidgetTester tester,
  ) async {
    await pumpBar(tester);
    expect(find.text('Your Apps'), findsOneWidget);
  });

  testWidgets('the dock offers every workspace and marks the current one', (
    WidgetTester tester,
  ) async {
    await pumpBar(tester, currentWorkspace: 3);

    for (int i = 1; i <= kWorkspaceCount; i++) {
      expect(find.text('$i'), findsOneWidget, reason: 'workspace $i is missing');
    }

    // Selection must be announced, not only painted: the difference between
    // the current desk and the others is the whole point of the control.
    bool selectedFor(String label) => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics w) => w.properties.label == label)
        .every((Semantics w) => w.properties.selected ?? false);

    expect(selectedFor('Workspace 3'), isTrue);
    expect(selectedFor('Workspace 1'), isFalse);
  });

  testWidgets('choosing a workspace reports which one', (
    WidgetTester tester,
  ) async {
    final List<int> chosen = <int>[];
    await pumpBar(tester, onSelectWorkspace: chosen.add);

    await tester.tap(find.text('2'));
    await tester.pump();

    expect(chosen, <int>[2]);
  });

  testWidgets('switching desks changes which windows are on screen', (
    WidgetTester tester,
  ) async {
    // The point of the control. A switcher that changes a number and leaves
    // the same windows on screen is a control that lies, which the design bar
    // here rates as worse than having no control at all.
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data!,
                facade: facade,
                now: DateTime.utc(2026, 8, 24, 22),
              ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await facade.launchApplication('com.android.chrome');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(AppWindow), findsOneWidget, reason: 'opened on desk 1');

    await facade.selectWorkspace(2);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(AppWindow), findsNothing, reason: 'desk 2 is empty');

    // And it is still there when you go back — switching is a change of view,
    // not of state.
    await facade.selectWorkspace(1);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(AppWindow), findsOneWidget);
  });

  testWidgets('a narrow dock sheds the workspace keys rather than overflowing',
      (WidgetTester tester) async {
    // 640 is in the responsive sweep. The nav pill already sheds below 760;
    // switching desks is a rarer job than reaching the launcher, so it goes
    // too rather than squeezing everything.
    await pumpBar(tester, size: const Size(640, 560));

    expect(find.text('Your Apps'), findsNothing);
    expect(find.text('4'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
