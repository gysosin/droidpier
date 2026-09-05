import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/desk_switch_label.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Switching desks by keyboard has no visible target, so the desk names the
/// desk it landed on, briefly, and then gets out of the way for good: no
/// timer, no animation and no frame left behind.
void main() {
  Future<void> pump(WidgetTester tester, int workspace) => tester.pumpWidget(
    MaterialApp(
      theme: DexTheme.dark(),
      home: Scaffold(body: DeskSwitchLabel(workspace: workspace)),
    ),
  );

  testWidgets('says nothing on first build, names the desk on a switch', (
    WidgetTester tester,
  ) async {
    await pump(tester, 1);
    await tester.pump();
    expect(find.text('Desk 1'), findsNothing);

    await pump(tester, 2);
    await tester.pump();
    expect(find.text('Desk 2'), findsOneWidget);
    final Finder fade = find.ancestor(
      of: find.text('Desk 2'),
      matching: find.byType(AnimatedOpacity),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);

    // Gone after its moment, and quiet: nothing scheduled once it has faded.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('Desk 2'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a second switch restarts the moment with the new name', (
    WidgetTester tester,
  ) async {
    await pump(tester, 1);
    await tester.pump();
    await pump(tester, 2);
    await tester.pump(const Duration(milliseconds: 500));
    await pump(tester, 3);
    await tester.pump();
    expect(find.text('Desk 3'), findsOneWidget);
    expect(find.text('Desk 2'), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Desk 3'), findsOneWidget, reason: 'the timer restarted');
    // A pending timer is not a scheduled frame, so settle only after it fires.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Desk 3'), findsNothing);
  });

  testWidgets('the label never takes the pointer', (WidgetTester tester) async {
    await pump(tester, 1);
    await tester.pump();
    await pump(tester, 2);
    await tester.pump();
    expect(
      find.ancestor(
        of: find.text('Desk 2'),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
  });
}
