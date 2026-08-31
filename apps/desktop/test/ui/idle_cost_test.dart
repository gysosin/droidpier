import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// A connected desk that is not being touched must stop scheduling frames.
///
/// The link rail's signal band ran `AnimationController.repeat()` for the whole
/// connected session. A thin band on its own; stacked under a desk of
/// `BackdropFilter` glass and a live video texture it forced the entire tree to
/// re-blur at 60 fps, and was measured holding ~72% host CPU with one embedded
/// window.
///
/// `pumpAndSettle` is the right instrument: it returns only when no frame is
/// scheduled, so it times out on any perpetual animation. This test cannot pass
/// while one exists.
void main() {
  testWidgets('an idle connected desk schedules no further frames', (
    WidgetTester tester,
  ) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          // Pinned, so the shell's own once-per-ten-seconds clock ticker does
          // not keep the tree busy. That timer is not the subject here.
          now: DateTime.utc(2026, 8, 25, 10),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'an untouched desk must cost nothing to keep on screen',
    );
  });
}
