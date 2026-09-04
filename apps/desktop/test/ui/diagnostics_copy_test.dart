import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/diagnostics/stream_diagnostics.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Copying a bug report out of the diagnostics panel.
///
/// The report itself is covered as a pure function in
/// diagnostics_report_test.dart; what matters here is that the button exists
/// only when something can actually receive the text, and hands over the real
/// report when it does.
void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    ValueChanged<String>? onCopyText,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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
          builder:
              (BuildContext context, AsyncSnapshot<OpenDexSnapshot> snap) =>
                  AppShell(
                    snapshot: snap.data ?? facade.snapshot,
                    facade: facade,
                    now: DateTime.utc(2026, 9, 1, 22),
                    onCopyText: onCopyText,
                  ),
        ),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> openDiagnostics(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the button is absent when the host has no clipboard', (
    WidgetTester tester,
  ) async {
    // lib/ui never touches the system clipboard — that belongs to the
    // bootstrap lane — so without a handler there is nothing to copy with.
    // Absent, not disabled: a control that does nothing is worse than none.
    await pumpShell(tester);
    await openDiagnostics(tester);
    expect(find.byType(StreamDiagnostics), findsOneWidget);
    expect(find.text('Copy diagnostics report'), findsNothing);
  });

  testWidgets('it hands the host a paste-ready report', (
    WidgetTester tester,
  ) async {
    final List<String> copied = <String>[];
    await pumpShell(tester, onCopyText: copied.add);
    await openDiagnostics(tester);

    expect(find.text('Copy diagnostics report'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostics report'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, startsWith('### DroidPier diagnostics'));
    expect(
      copied.single,
      contains('| Build |'),
      reason: 'a report without a build cannot be matched to a version',
    );
  });
}
