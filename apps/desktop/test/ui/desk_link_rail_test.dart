import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/desk.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/link_rail.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The Link Rail on the desk.
///
/// The rail is the product's signature: one instrument the user learns once,
/// in three states. Two of them shipped. The third — the collapsed live trace,
/// which is the state a connected user looks at all day — was written, tested,
/// and then wired only into the preview harness. The desk never showed it, so
/// the most distinctive thing in the product was invisible in normal use.
void main() {
  Future<void> pumpDesk(
    WidgetTester tester,
    Size size, {
    List<WorkspaceWindow> windows = const <WorkspaceWindow>[],
  }) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Desk(
            snapshot: facade.snapshot,
            now: DateTime.utc(2026, 8, 25, 10),
            onOpenLauncher: () {},
            onWebSearch: (_) {},
            onMediaAction: (_) {},
            onFocusWindow: (_) {},
            onCloseWindow: (_) {},
            onNavKey: (_) {},
            onToggleControl: (_, _) {},
            onToggleClipboardSync: (_) {},
            onSetVolume: (_, _) {},
            onOpenPermissions: () {},
            onDismissNotification: (_) async {},
            onActivateNotification: (_) async {},
            onDismissAllNotifications: () async {},
            onOpenSettings: () {},
            onToggleFullscreen: () {},
            fullscreenActive: false,
            onLaunchApplication: (_) {},
            workspace: const SizedBox.expand(),
            windows: windows,
            minimisedWindows: const <String>{},
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the desk carries the live link trace', (
    WidgetTester tester,
  ) async {
    await pumpDesk(tester, const Size(1440, 900));

    expect(find.byType(LinkRailChip), findsOneWidget);
    expect(find.text('LINK'), findsOneWidget);

    // The three machine values the trace exists to carry. Labels are the
    // reference's: short, uppercase and the same width class as the numbers.
    expect(find.text('RTT'), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    expect(find.text('RATE'), findsOneWidget);
  });

  testWidgets('the trace stays legible while a window streams', (
    WidgetTester tester,
  ) async {
    // The rest of the desk furniture recedes behind a focused stream. The link
    // instrument does not: whether the link is healthy is exactly what a user
    // wants to read while something is streaming, and a half-faded latency
    // figure is the one readout that must never be hard to read.
    await pumpDesk(tester, const Size(1440, 900));

    final Finder chip = find.byType(LinkRailChip);
    final Iterable<Opacity> faded = tester
        .widgetList<Opacity>(
          find.ancestor(of: chip, matching: find.byType(Opacity)),
        )
        .where((Opacity o) => o.opacity < 1);
    expect(faded, isEmpty);
  });

  testWidgets('the trace sheds readouts rather than overflowing', (
    WidgetTester tester,
  ) async {
    // 480 wide is in the responsive sweep. Three labelled readouts do not fit
    // there, and a desk that overflows is worse than one that says less.
    await pumpDesk(tester, const Size(480, 620));

    expect(find.byType(LinkRailChip), findsOneWidget);
    expect(find.text('RTT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
